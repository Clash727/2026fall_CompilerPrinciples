#!/usr/bin/env bash
# Run from Linux or WSL with: bash run.sh
set -euo pipefail
export LC_ALL=C
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

for tool in gcc clang ar llvm-as llvm-dis opt llc lli diff cmp awk sha256sum timeout; do
    command -v "$tool" >/dev/null || { printf 'Missing tool: %s\n' "$tool" >&2; exit 1; }
done
[[ -r lib/sylib.c && -r lib/sylib.h ]] || {
    printf 'Missing SysY runtime source: lib/sylib.c or lib/sylib.h\n' >&2
    exit 1
}

mkdir -p build results
exec 3>results/commands.log
printf '# Working directory: %s\n' "$script_dir" >&3

log_command() {
    printf '%q ' "$@" >&3
    printf '\n' >&3
}

run() {
    log_command "$@"
    "$@"
}

run_to_file() {
    local destination=$1
    shift
    printf '%q ' "$@" >&3
    printf '> %q\n' "$destination" >&3
    "$@" > "$destination"
}

# Build the course runtime from source so a fresh clone needs no checked-in
# static archive or shared object.
run gcc -std=c11 -O2 -fPIC -c lib/sylib.c -o build/sylib.o
run ar rcs lib/libsysy_x86.a build/sylib.o
run gcc -shared build/sylib.o -o lib/sylib.so

{
    date -u '+Run time: %Y-%m-%dT%H:%M:%SZ'
    uname -srmo
    . /etc/os-release
    printf 'Distribution: %s\n' "$PRETTY_NAME"
    for tool in gcc clang llvm-as llvm-dis opt llc lli; do
        printf '%s: ' "$tool"
        "$tool" --version | sed -n '1p'
    done
} > results/versions.txt
printf 'RUNNING: see commands.log and test-results.tsv for current progress.\n' > results/summary.txt

# Keep a checksum of the handwritten baseline before any processing.
run_to_file results/baseline-before.sha256 sha256sum average_base.ll
run llvm-as average_base.ll -o build/average_base.bc
run opt -passes=verify -disable-output build/average_base.bc
run llvm-dis build/average_base.bc -o build/average_base_roundtrip.ll

# This is the only IR optimization pass used in the experiment.
run opt -S -passes=mem2reg average_base.ll -o average_mem2reg.ll
run llvm-as average_mem2reg.ll -o build/average_mem2reg.bc
run opt -passes=verify -disable-output build/average_mem2reg.bc

# Compile the same SysY source as C for a reference, without changing its body.
run gcc -std=c11 -O0 -Wall -Wextra -include runtime_decls.h -x c \
    -c average.sy -o build/average_source.o
run gcc build/average_source.o lib/libsysy_x86.a -o build/average_source

# Both IR versions use identical backend/link options. -O0 applies to llc's
# machine-code generation; the report compares textual IR before this stage.
for variant in base mem2reg; do
    run llc -O0 -relocation-model=pic -filetype=obj \
        "build/average_${variant}.bc" -o "build/average_${variant}.o"
    run clang "build/average_${variant}.o" lib/libsysy_x86.a \
        -o "build/average_${variant}"
done

# diff returns 1 for ordinary differences, which are expected here.
diff_status=0
run_to_file results/base-vs-mem2reg.diff diff -u \
    --label average_base.ll --label average_mem2reg.ll \
    average_base.ll average_mem2reg.ll || diff_status=$?
if (( diff_status > 1 )); then
    exit "$diff_status"
fi

printf 'version\talloca\tload\tstore\tphi\n' > results/instruction-counts.tsv
for variant in base mem2reg; do
    awk -v version="$variant" '
        {
            line = $0
            sub(/;.*/, "", line)
            sub(/^[[:space:]]+/, "", line)
            sub(/^%[^=]+=[[:space:]]*/, "", line)
            split(line, fields, /[[:space:]]+/)
            count[fields[1]]++
        }
        END {
            printf "%s\t%d\t%d\t%d\t%d\n", version,
                count["alloca"], count["load"], count["store"], count["phi"]
        }
    ' "average_${variant}.ll" >> results/instruction-counts.tsv
done

printf 'case\tmode\texit_code\texpected_match\tsource_match\n' > results/test-results.tsv
failures=0
executions=0
test_run() {
    local case_name=$1 mode=$2
    shift 2
    local prefix="results/${case_name}.${mode}"
    local status=0 expected_match=PASS source_match=PASS
    printf '%q ' timeout 10s "$@" >&3
    printf '< %q > %q 2> %q\n' "tests/$case_name.in" \
        "$prefix.stdout" "$prefix.stderr" >&3
    timeout 10s "$@" < "tests/$case_name.in" \
        > "$prefix.stdout" 2> "$prefix.stderr" || status=$?

    if ! run cmp -s "tests/$case_name.expected" "$prefix.stdout"; then
        expected_match=FAIL
    fi
    if ! run cmp -s "results/$case_name.source.stdout" "$prefix.stdout"; then
        source_match=FAIL
    fi
    printf '%s\t%s\t%d\t%s\t%s\n' "$case_name" "$mode" "$status" \
        "$expected_match" "$source_match" >> results/test-results.tsv
    executions=$((executions + 1))
    if (( status != 0 )) || [[ "$expected_match" != PASS || "$source_match" != PASS ]]; then
        failures=$((failures + 1))
        printf 'FAIL: %s / %s (exit %d); inspect %s.*\n' \
            "$case_name" "$mode" "$status" "$prefix" >&2
    fi
}

for case_name in below equal above negative mixed; do
    before=$failures
    test_run "$case_name" source ./build/average_source
    test_run "$case_name" base_native ./build/average_base
    test_run "$case_name" mem2reg_native ./build/average_mem2reg
    test_run "$case_name" base_jit lli -load=./lib/sylib.so average_base.ll
    test_run "$case_name" mem2reg_jit lli -load=./lib/sylib.so average_mem2reg.ll
    if (( failures == before )); then
        printf 'PASS: %s (source, base/native, mem2reg/native, base/JIT, mem2reg/JIT)\n' "$case_name"
    fi
done

run_to_file results/baseline-preserved.txt sha256sum -c results/baseline-before.sha256
run_to_file results/checksums.sha256 sha256sum average.sy runtime_decls.h run.sh \
    average_base.ll average_mem2reg.ll tests/*.in tests/*.expected \
    lib/libsysy_x86.a lib/sylib.so

{
    printf 'IR optimization pipeline: mem2reg only\n'
    printf 'Pointer representation: opaque pointers in both IR versions\n'
    printf 'Baseline: preserved (checksum verified)\n'
    printf 'IR verification: PASS (both versions)\n'
    printf 'Cases: 5; executions: %d; failures: %d\n' "$executions" "$failures"
    if (( failures == 0 )); then
        printf 'PASS: all executions exited with 0 and matched expected/source stdout.\n'
    else
        printf 'FAIL: inspect test-results.tsv and per-execution stdout/stderr files.\n'
    fi
    printf 'Timing output: stored separately in *.stderr; no speedup claim.\n'
} > results/summary.txt
cat results/summary.txt
cat results/instruction-counts.tsv
(( failures == 0 ))

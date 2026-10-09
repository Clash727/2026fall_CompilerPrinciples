#!/usr/bin/env bash
# RISC-V 语言编写（第 7 部分）：手写 rv64gc 汇编 + SysY 运行库，
# 交叉编译、静态链接后用 qemu-riscv64 运行验证，并与 SysY 源程序对照。
# 运行环境：Linux / WSL，需安装 gcc-riscv64-linux-gnu 与 qemu-user。
# 用法：bash run.sh
set -euo pipefail
export LC_ALL=C
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

RISCV_GCC=${RISCV_GCC:-riscv64-linux-gnu-gcc}
QEMU=${QEMU:-qemu-riscv64}

for tool in "$RISCV_GCC" "$QEMU" diff cmp timeout ar; do
    command -v "$tool" >/dev/null || { printf 'Missing tool: %s\n' "$tool" >&2; exit 1; }
done
[[ -r lib/sylib.c && -r lib/sylib.h && -r avg_hand.s && -r average.sy ]] || {
    printf 'Missing source: lib/sylib.c lib/sylib.h avg_hand.s average.sy\n' >&2; exit 1; }

mkdir -p build results
exec 3>results/commands.log
printf '# Working directory: %s\n' "$script_dir" >&3
printf '# RISCV_GCC=%s QEMU=%s\n' "$RISCV_GCC" "$QEMU" >&3

log_command() { printf '%q ' "$@" >&3; printf '\n' >&3; }
run() { log_command "$@"; "$@"; }
run_to_file() {
    local destination=$1; shift
    printf '%q ' "$@" >&3; printf '> %q\n' "$destination" >&3
    "$@" > "$destination"
}

FLAGS=(-march=rv64gc -mabi=lp64d)

# ---------- 1. 编译 SysY 运行库 ----------
# 课程提供的 libsysy_riscv.a 基于 newlib，无法与 glibc 目标链接（引用 _impure_ptr），
# 故此处直接使用其源码 lib/sylib.c 用 riscv64-linux-gnu-gcc 交叉编译。
run "$RISCV_GCC" "${FLAGS[@]}" -c lib/sylib.c -o build/sylib.o

# ---------- 2. 手写汇编：汇编 + 静态链接 ----------
run "$RISCV_GCC" "${FLAGS[@]}" -c avg_hand.s -o build/avg_hand.o
run "$RISCV_GCC" "${FLAGS[@]}" -static build/avg_hand.o build/sylib.o -o build/avg_hand
run_to_file results/avg_hand-file.txt file build/avg_hand

# ---------- 3. 语义参考：把 average.sy 按 C 源码交叉编译，用于对照验证 ----------
run "$RISCV_GCC" "${FLAGS[@]}" -include runtime_decls.h -x c -c average.sy -o build/average_source.o
run "$RISCV_GCC" "${FLAGS[@]}" -static build/average_source.o build/sylib.o -o build/average_source

# ---------- 4. 运行验证 ----------
printf 'case\texit_code\tas_matched_expected\tas_matched_source\n' > results/test-results.tsv
failures=0
for case_name in above below equal mixed negative; do
    status=0
    timeout 10s "$QEMU" build/avg_hand < "tests/$case_name.in" \
        > "results/$case_name.stdout" 2> "results/$case_name.stderr" || status=$?

    source_status=0
    timeout 10s "$QEMU" build/average_source < "tests/$case_name.in" \
        > "results/$case_name.source.stdout" 2> "results/$case_name.source.stderr" || source_status=$?

    as_expected=PASS
    cmp -s "tests/$case_name.expected" "results/$case_name.stdout" || as_expected=FAIL
    as_source=PASS
    cmp -s "results/$case_name.stdout" "results/$case_name.source.stdout" || as_source=FAIL

    printf '%s\t%d\t%s\t%s\n' "$case_name" "$status" "$as_expected" "$as_source" \
        >> results/test-results.tsv

    if (( status != 0 )) || (( source_status != 0 )) \
        || [[ "$as_expected" != PASS ]] || [[ "$as_source" != PASS ]]; then
        failures=$((failures+1))
        printf 'FAIL: %s (exit %d, as_expected=%s, as_source=%s)\n' \
            "$case_name" "$status" "$as_expected" "$as_source" >&2
    fi
done

# ---------- 汇总 ----------
{
    printf 'Target: rv64gc / lp64d; runtime: lib/sylib.c (static)\n'
    printf 'Cases: 5; failures: %d\n' "$failures"
    if (( failures == 0 )); then
        printf 'PASS: hand-written assembly matches both expected output and SysY source reference.\n'
    else
        printf 'FAIL: see results/test-results.tsv.\n'
    fi
} > results/summary.txt
cat results/summary.txt
printf '\n'
cat results/test-results.tsv
(( failures == 0 ))

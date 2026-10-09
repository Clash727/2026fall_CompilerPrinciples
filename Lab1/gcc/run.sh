#!/usr/bin/env bash
# 编译过程探究（第 5 部分）：演示「预处理 -> 编译 -> 汇编 -> 链接」四阶段流水线，
# 以及宏展开、GIMPLE 转储、多文件编译、静态/动态链接、-O0/-O2 优化对比与运行验证。
# 运行环境：Linux 或 WSL；用法：bash run.sh
set -euo pipefail
export LC_ALL=C
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

for tool in gcc readelf file ldd wc diff cmp timeout; do
    command -v "$tool" >/dev/null || { printf 'Missing tool: %s\n' "$tool" >&2; exit 1; }
done

mkdir -p build results
exec 3>results/commands.log
printf '# Working directory: %s\n' "$script_dir" >&3

log_command() { printf '%q ' "$@" >&3; printf '\n' >&3; }
run() { log_command "$@"; "$@"; }
run_to_file() {
    local destination=$1; shift
    printf '%q ' "$@" >&3; printf '> %q\n' "$destination" >&3
    "$@" > "$destination"
}

# ---------- 1. 预处理：宏展开 + 头文件展开 ----------
run gcc -E prime.c -o build/prime.i
run_to_file results/preprocess-lines.txt wc -l build/prime.i
run gcc -E macro.c -o build/macro.i
run_to_file results/macro-expanded.txt tail -n 6 build/macro.i

# ---------- 2. 编译：GIMPLE 转储 + 生成汇编（-O0） ----------
run gcc -fdump-tree-gimple -S -O0 prime.c -o build/prime_O0.s
run_to_file results/compile-O0-lines.txt wc -l build/prime_O0.s
gimple_dump=$(find . -maxdepth 1 -name '*.gimple' -print -quit)
if [[ -n "$gimple_dump" ]]; then mv "$gimple_dump" results/prime.gimple; fi

# ---------- 3. 汇编：生成可重定位目标文件，查看符号表 ----------
run gcc -c build/prime_O0.s -o build/prime.o
run_to_file results/prime-o-symbols.txt readelf -s build/prime.o

# ---------- 4. 链接：动态链接，查看文件类型与动态依赖 ----------
run gcc build/prime.o -o build/prime
run_to_file results/prime-file.txt file build/prime
run_to_file results/prime-ldd.txt ldd build/prime

# ---------- 5. 多文件编译：分别汇编再统一链接 ----------
run gcc -c isprime.c -o build/isprime.o
run gcc -c main2.c -o build/main2.o
run_to_file results/isprime-symbols.txt readelf -s build/isprime.o
run_to_file results/main2-undefined.txt bash -c "readelf -s build/main2.o | grep -E 'is_prime|main|UND'"
run gcc build/isprime.o build/main2.o -o build/multi
run gcc -static build/isprime.o build/main2.o -o build/multi_static
run_to_file results/multi-file.txt file build/multi
run_to_file results/multi-static-file.txt file build/multi_static
run_to_file results/multi-sizes.txt bash -c "ls -la build/multi build/multi_static"

# ---------- 6. 优化对比：-O0 与 -O2 生成的汇编规模 ----------
run gcc -S -O2 prime.c -o build/prime_O2.s
run_to_file results/compile-O2-lines.txt wc -l build/prime_O2.s

# ---------- 7. 运行验证 ----------
printf 'case\texit_code\tmatched_expected\n' > results/test-results.tsv
failures=0
for case_name in prime two large_prime composite below_two; do
    status=0
    timeout 10s ./build/prime < "tests/$case_name.in" \
        > "results/$case_name.stdout" 2> "results/$case_name.stderr" || status=$?
    matched=PASS
    cmp -s "tests/$case_name.expected" "results/$case_name.stdout" || matched=FAIL
    printf '%s\t%d\t%s\n' "$case_name" "$status" "$matched" >> results/test-results.tsv
    if (( status != 0 )) || [[ "$matched" != PASS ]]; then
        failures=$((failures+1))
        printf 'FAIL: %s (exit %d)\n' "$case_name" "$status" >&2
    fi
done

# ---------- 汇总 ----------
{
    printf 'Pipeline: preprocess -> compile -> assemble -> link\n'
    printf 'Cases: 5; failures: %d\n' "$failures"
    if (( failures == 0 )); then
        printf 'PASS: all prime test cases matched expected stdout.\n'
    else
        printf 'FAIL: see results/test-results.tsv.\n'
    fi
} > results/summary.txt
cat results/summary.txt
printf '\n'
cat results/test-results.tsv
(( failures == 0 ))

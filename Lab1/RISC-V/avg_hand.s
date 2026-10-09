# avg_hand.s —— 手写 RISC-V 汇编，实现与 average.sy 相同的语义
# 目标：rv64gc 指令集 + lp64d 浮点 ABI
# 编译：riscv64-linux-gnu-gcc -march=rv64gc -mabi=lp64d -c avg_hand.s -o avg_hand.o
# 链接：与 lib/sylib.c 编译出的 sylib.o 静态链接，再由 qemu-riscv64 运行

    .data
    .align 2
threshold:
    .word 3                      # int threshold = 3

    .text
    .globl average
    .globl main

# float average(int a[], int n)
#   a0 = 数组基地址，a1 = 数组长度 n，返回单精度浮点平均值于 fa0
average:
    addi sp, sp, -32
    sd   s0, 0(sp)
    sd   s1, 8(sp)
    sd   s2, 16(sp)
    sd   s3, 24(sp)
    mv   s2, a1                 # s2 = n
    mv   s3, a0                 # s3 = a（数组基地址）
    li   s0, 0                  # i = 0
    li   s1, 0                  # sum = 0
.Lavg_cond:
    bge  s0, s2, .Lavg_end      # 若 i >= n 则结束循环
    slli t0, s0, 2              # t0 = i * 4
    add  t0, s3, t0             # t0 = &a[i]
    lw   t1, 0(t0)              # t1 = a[i]
    add  s1, s1, t1             # sum = sum + a[i]
    addi s0, s0, 1              # i = i + 1
    j    .Lavg_cond
.Lavg_end:
    fcvt.s.w fa0, s1            # fa0 = (float)sum
    fcvt.s.w fa1, s2            # fa1 = (float)n
    fdiv.s fa0, fa0, fa1        # fa0 = sum / n
    ld   s0, 0(sp)
    ld   s1, 8(sp)
    ld   s2, 16(sp)
    ld   s3, 24(sp)
    addi sp, sp, 32
    ret

# int main()
main:
    addi sp, sp, -64
    sd   ra, 0(sp)
    sd   s0, 8(sp)
    sd   s1, 16(sp)
    sd   s2, 24(sp)
    li   s0, 0                  # i = 0
.Linput_cond:
    li   t0, 5
    bge  s0, t0, .Linput_done   # 若 i >= 5 则结束输入
    call getint                 # a0 = getint()
    slli t1, s0, 2              # t1 = i * 4
    addi t1, t1, 32
    add  t1, sp, t1             # t1 = &a[i]（局部数组 a 位于 sp+32 起的栈区）
    sw   a0, 0(t1)              # a[i] = getint()
    addi s0, s0, 1              # i = i + 1
    j    .Linput_cond
.Linput_done:
    addi a0, sp, 32             # a0 = &a[0]
    li   a1, 5
    call average                # fa0 = average(a, 5)
    fsw  fa0, 52(sp)            # 将返回值暂存到栈上
    flw  fa0, 52(sp)
    call putfloat               # putfloat(avg)
    li   a0, 10
    call putch                  # putch('\n')
    flw  fa0, 52(sp)            # 重新加载 avg
    la   t0, threshold
    lw   t1, 0(t0)              # t1 = threshold
    fcvt.s.w fa1, t1            # fa1 = (float)threshold
    fge.s t0, fa0, fa1          # t0 = (avg >= threshold)
    beqz t0, .Lelse
    li   a0, 1
    call putint                 # putint(1)
    j    .Lend_if
.Lelse:
    li   a0, 0
    call putint                 # putint(0)
.Lend_if:
    li   a0, 10
    call putch                  # putch('\n')
    li   a0, 0                  # return 0
    ld   ra, 0(sp)
    ld   s0, 8(sp)
    ld   s1, 16(sp)
    ld   s2, 24(sp)
    addi sp, sp, 64
    ret

    .section .note.GNU-stack,"",@progbits

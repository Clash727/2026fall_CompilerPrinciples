; Handwritten LLVM IR for average.sy. This file is the preserved baseline.
; Opaque pointers use ptr; load/store/GEP still specify the accessed type.
; Run only mem2reg to generate average_mem2reg.ll; do not overwrite this file.
source_filename = "average.sy"

@threshold = global i32 3, align 4

declare i32 @getint()
declare void @putint(i32)
declare void @putfloat(float)
declare void @putch(i32)

define float @average(ptr %a, i32 %n) {
entry:
    ; Scalar local variables are deliberately kept in stack slots.
    %i.addr = alloca i32, align 4
    %sum.addr = alloca i32, align 4
    %result.addr = alloca float, align 4
    store i32 0, ptr %i.addr, align 4
    store i32 0, ptr %sum.addr, align 4
    br label %loop.cond

loop.cond:
    %i.cond = load i32, ptr %i.addr, align 4
    %keep.going = icmp slt i32 %i.cond, %n
    br i1 %keep.going, label %loop.body, label %loop.end

loop.body:
    %i.body = load i32, ptr %i.addr, align 4
    ; The array parameter points at its first i32 element.
    %element.ptr = getelementptr inbounds i32, ptr %a, i32 %i.body
    %element = load i32, ptr %element.ptr, align 4
    %sum.old = load i32, ptr %sum.addr, align 4
    %sum.next = add nsw i32 %sum.old, %element
    store i32 %sum.next, ptr %sum.addr, align 4
    %i.old = load i32, ptr %i.addr, align 4
    %i.next = add nsw i32 %i.old, 1
    store i32 %i.next, ptr %i.addr, align 4
    br label %loop.cond

loop.end:
    %sum.final = load i32, ptr %sum.addr, align 4
    %sum.float = sitofp i32 %sum.final to float
    store float %sum.float, ptr %result.addr, align 4
    %result = load float, ptr %result.addr, align 4
    %n.float = sitofp i32 %n to float
    %mean = fdiv float %result, %n.float
    ret float %mean
}

define i32 @main() {
entry:
    %a = alloca [5 x i32], align 4
    %i.addr = alloca i32, align 4
    %avg.addr = alloca float, align 4
    store i32 0, ptr %i.addr, align 4
    br label %input.cond

input.cond:
    %i.cond = load i32, ptr %i.addr, align 4
    %need.input = icmp slt i32 %i.cond, 5
    br i1 %need.input, label %input.body, label %input.end

input.body:
    %input = call i32 @getint()
    %i.body = load i32, ptr %i.addr, align 4
    ; First index selects the array object; second selects its element.
    %element.ptr = getelementptr inbounds [5 x i32], ptr %a, i32 0, i32 %i.body
    store i32 %input, ptr %element.ptr, align 4
    %i.old = load i32, ptr %i.addr, align 4
    %i.next = add nsw i32 %i.old, 1
    store i32 %i.next, ptr %i.addr, align 4
    br label %input.cond

input.end:
    %a.first = getelementptr inbounds [5 x i32], ptr %a, i32 0, i32 0
    %avg.value = call float @average(ptr %a.first, i32 5)
    store float %avg.value, ptr %avg.addr, align 4
    %avg.output = load float, ptr %avg.addr, align 4
    call void @putfloat(float %avg.output)
    call void @putch(i32 10)
    ; SysY converts the integer threshold to float for this comparison.
    %avg.compare = load float, ptr %avg.addr, align 4
    %threshold.int = load i32, ptr @threshold, align 4
    %threshold.float = sitofp i32 %threshold.int to float
    %at.least.threshold = fcmp oge float %avg.compare, %threshold.float
    br i1 %at.least.threshold, label %if.then, label %if.else

if.then:
    call void @putint(i32 1)
    br label %if.end

if.else:
    call void @putint(i32 0)
    br label %if.end

if.end:
    call void @putch(i32 10)
    ret i32 0
}

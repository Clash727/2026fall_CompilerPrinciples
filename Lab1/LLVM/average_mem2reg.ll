; ModuleID = 'average_base.ll'
source_filename = "average.sy"

@threshold = global i32 3, align 4

declare i32 @getint()

declare void @putint(i32)

declare void @putfloat(float)

declare void @putch(i32)

define float @average(ptr %a, i32 %n) {
entry:
  br label %loop.cond

loop.cond:                                        ; preds = %loop.body, %entry
  %sum.addr.0 = phi i32 [ 0, %entry ], [ %sum.next, %loop.body ]
  %i.addr.0 = phi i32 [ 0, %entry ], [ %i.next, %loop.body ]
  %keep.going = icmp slt i32 %i.addr.0, %n
  br i1 %keep.going, label %loop.body, label %loop.end

loop.body:                                        ; preds = %loop.cond
  %element.ptr = getelementptr inbounds i32, ptr %a, i32 %i.addr.0
  %element = load i32, ptr %element.ptr, align 4
  %sum.next = add nsw i32 %sum.addr.0, %element
  %i.next = add nsw i32 %i.addr.0, 1
  br label %loop.cond

loop.end:                                         ; preds = %loop.cond
  %sum.float = sitofp i32 %sum.addr.0 to float
  %n.float = sitofp i32 %n to float
  %mean = fdiv float %sum.float, %n.float
  ret float %mean
}

define i32 @main() {
entry:
  %a = alloca [5 x i32], align 4
  br label %input.cond

input.cond:                                       ; preds = %input.body, %entry
  %i.addr.0 = phi i32 [ 0, %entry ], [ %i.next, %input.body ]
  %need.input = icmp slt i32 %i.addr.0, 5
  br i1 %need.input, label %input.body, label %input.end

input.body:                                       ; preds = %input.cond
  %input = call i32 @getint()
  %element.ptr = getelementptr inbounds [5 x i32], ptr %a, i32 0, i32 %i.addr.0
  store i32 %input, ptr %element.ptr, align 4
  %i.next = add nsw i32 %i.addr.0, 1
  br label %input.cond

input.end:                                        ; preds = %input.cond
  %a.first = getelementptr inbounds [5 x i32], ptr %a, i32 0, i32 0
  %avg.value = call float @average(ptr %a.first, i32 5)
  call void @putfloat(float %avg.value)
  call void @putch(i32 10)
  %threshold.int = load i32, ptr @threshold, align 4
  %threshold.float = sitofp i32 %threshold.int to float
  %at.least.threshold = fcmp oge float %avg.value, %threshold.float
  br i1 %at.least.threshold, label %if.then, label %if.else

if.then:                                          ; preds = %input.end
  call void @putint(i32 1)
  br label %if.end

if.else:                                          ; preds = %input.end
  call void @putint(i32 0)
  br label %if.end

if.end:                                           ; preds = %if.else, %if.then
  call void @putch(i32 10)
  ret i32 0
}

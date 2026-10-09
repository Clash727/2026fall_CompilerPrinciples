/* macro.c —— 预处理阶段宏展开示例（观察 gcc -E 之后的文本替换结果） */
#include <stdio.h>

#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define LIMIT     10

int main(void) {
    int x = 3, y = 7;

    printf("%d %d\n", MAX(x, y), LIMIT);
    return 0;
}

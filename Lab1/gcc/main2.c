/* main2.c —— 多文件编译示例：主函数通过外部声明调用 isprime.c 中的 is_prime */
#include <stdio.h>

int is_prime(int n);

int main(void) {
    int n;

    scanf("%d", &n);
    printf("%d\n", is_prime(n));

    return 0;
}

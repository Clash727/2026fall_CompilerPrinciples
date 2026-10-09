/* prime.c —— 素数判断演示程序（第 5 部分「编译过程探究」的入口源码） */
#include <stdio.h>

int main(void) {
    int n;
    int i = 2;
    int prime = 1;

    scanf("%d", &n);

    if (n < 2) {
        prime = 0;
    } else {
        while (i <= n / i) {
            if (n % i == 0) {
                prime = 0;
                break;
            }
            i = i + 1;
        }
    }

    printf("%d\n", prime);
    return 0;
}

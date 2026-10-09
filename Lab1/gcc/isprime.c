/* isprime.c —— 多文件编译示例：素数判断逻辑单独放在一个编译单元 */
int is_prime(int n) {
    int i = 2;

    if (n < 2) {
        return 0;
    }

    while (i <= n / i) {
        if (n % i == 0) {
            return 0;
        }
        i = i + 1;
    }

    return 1;
}

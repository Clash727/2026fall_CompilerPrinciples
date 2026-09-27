#ifndef AVERAGE_RUNTIME_DECLS_H
#define AVERAGE_RUNTIME_DECLS_H

/* Declarations only, for compiling the unchanged SysY source as C.
 * Implementations are built from the course SysY runtime source in lib/.
 * Its sylib.h also defines timer globals, so it is not injected here.
 */
int getint(void);
void putint(int value);
void putfloat(float value);
void putch(int value);

#endif

// freestanding compile+link smoke-test.
// proves the abclog library can build without libc (embedded, WASM, etc.).
// not intended to be run — the build succeeding is the test.
//
// build:  make freestanding
//
// ABCLOG_FREESTANDING and NDEBUG are passed via compiler flags.

typedef __builtin_va_list va_list;
#define va_start __builtin_va_start
#define va_end __builtin_va_end
#define va_arg __builtin_va_arg
#define _VA_LIST_DEFINED

typedef __SIZE_TYPE__ size_t;

static int       stub_strcmp(const char *a, const char *b)              { (void)a; (void)b; return 0; }
static int       stub_strncmp(const char *a, const char *b, size_t n)  { (void)a; (void)b; (void)n; return 0; }
static size_t    stub_strlen(const char *s)                            { (void)s; return 0; }
static char     *stub_strrchr(const char *s, int c)                    { (void)s; (void)c; return 0; }
static size_t    stub_strcspn(const char *s, const char *r)            { (void)s; (void)r; return 0; }
static char     *stub_strncpy(char *d, const char *s, size_t n)       { (void)s; (void)n; return d; }
static char     *stub_strncat(char *d, const char *s, size_t n)       { (void)s; (void)n; return d; }
static char     *stub_strcpy(char *d, const char *s)                   { (void)s; return d; }
static void     *stub_memcpy(void *d, const void *s, size_t n)        { (void)s; (void)n; return d; }
static void     *stub_memset(void *d, int c, size_t n)                { (void)c; (void)n; return d; }
static int       stub_isspace(int c)  { (void)c; return 0; }
static int       stub_isdigit(int c)  { (void)c; return 0; }
static int       stub_isalpha(int c)  { (void)c; return 0; }
static int       stub_isalnum(int c)  { (void)c; return 0; }
static int       stub_isupper(int c)  { (void)c; return 0; }
static int       stub_vsnprintf(char *b, size_t sz, const char *f, va_list a) { (void)b; (void)sz; (void)f; (void)a; return 0; }

static int stub_snprintf(char *b, size_t sz, const char *f, ...) {
  (void)b; (void)sz; (void)f;
  return 0;
}

#define strcmp    stub_strcmp
#define strncmp  stub_strncmp
#define strlen   stub_strlen
#define strrchr  stub_strrchr
#define strcspn  stub_strcspn
#define strncpy  stub_strncpy
#define strncat  stub_strncat
#define strcpy   stub_strcpy
#define memcpy   stub_memcpy
#define memset   stub_memset
#define isspace  stub_isspace
#define isdigit  stub_isdigit
#define isalpha  stub_isalpha
#define isalnum  stub_isalnum
#define isupper  stub_isupper
#define vsnprintf stub_vsnprintf
#define snprintf stub_snprintf
#define assert(x) ((void)0)

#include "../src/builtins.c"
#include "../src/debug.c"
#include "../src/env.c"
#include "../src/ffi.c"
#include "../src/io.c"
#include "../src/parse.c"
#include "../src/print.c"
#include "../src/solve.c"
#include "../src/term.c"
#include "../src/unify.c"

#ifdef __x86_64__
__attribute__((naked)) void _start(void) {
  __asm__("xor %%edi, %%edi\n"
          "mov $60, %%eax\n"
          "syscall\n" ::: "memory");
}
#else
int main(void) { return 0; }
#endif

#undef memset
#undef memcpy
void *memset(void *d, int c, size_t n) { return stub_memset(d, c, n); }
void *memcpy(void *d, const void *s, size_t n) { return stub_memcpy(d, s, n); }

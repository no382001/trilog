#include "trilog.h"
#include "trilog_platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

size_t trilog_format_float(char *buf, size_t cap, double v) {
  int n = snprintf(buf, cap, "%#g", v);
  return n < 0 ? 0 : (size_t)n;
}

double trilog_parse_float(const char *s, const char **end) {
  char *e;
  double v = strtod(s, &e);
  if (end)
    *end = e;
  return v;
}

static void *host_realloc(void *ud, void *p, size_t n) {
  (void)ud;
  return realloc(p, n);
}

static void host_free(void *ud, void *p) {
  (void)ud;
  free(p);
}

static void *host_open(void *ud, const char *path, const char *mode) {
  (void)ud;
  return fopen(path, mode);
}

static long host_read(void *ud, void *h, char *buf, size_t n) {
  (void)ud;
  return (long)fread(buf, 1, n, h);
}

static long host_write(void *ud, void *h, const char *buf, size_t n) {
  (void)ud;
  return (long)fwrite(buf, 1, n, h);
}

static void host_close(void *ud, void *h) {
  (void)ud;
  fclose(h);
}

static int failures = 0;

#define CHECK(cond)                                                            \
  do {                                                                         \
    if (!(cond)) {                                                             \
      printf("not ok - %s [%s]\n", #cond, answer);                             \
      failures++;                                                              \
    } else {                                                                   \
      printf("ok - %s\n", #cond);                                              \
    }                                                                          \
  } while (0)

static char answer[64];

static bool first(trilog_t *t, void *ud, bool has_more) {
  (void)ud;
  (void)has_more;
  trilog_format(t, trilog_binding_value(t, 0), 0, answer, sizeof answer);
  return false;
}

static bool last(trilog_t *t, void *ud, bool has_more) {
  (void)ud;
  (void)has_more;
  int n = trilog_binding_count(t);
  trilog_format(t, trilog_binding_value(t, n - 1), 0, answer, sizeof answer);
  return false;
}

int main(void) {
  CHECK(trilog_new(NULL) == NULL);
  trilog_io_t io = {.open = host_open,
                    .read = host_read,
                    .write = host_write,
                    .close = host_close,
                    .in = stdin,
                    .out = stdout,
                    .err = stderr};
  trilog_t *t = trilog_new(&(trilog_config_t){
      .realloc = host_realloc, .free = host_free, .io = &io});
  CHECK(t != NULL);
  if (!t)
    return 1;
  CHECK(trilog_query(t, "X is 1 / 4.0", first, NULL) == TRILOG_TRUE);
  CHECK(strcmp(answer, "0.25") == 0);
  CHECK(trilog_query(t,
                     "X is 1 / 4.0, Y is 2.5 * 2, Z is 1.5e10, W is 1 / 3.0, "
                     "V is -0.5, U is 100.0, R = [X, Y, Z, W, V, U]",
                     last, NULL) == TRILOG_TRUE);
  CHECK(strcmp(answer, "[0.25, 5.0, 1.5e+10, 0.333333, -0.5, 100.0]") == 0);
  CHECK(trilog_query(t, "atom_codes('1.5e3', C), number_codes(X, C), Y = X",
                     last, NULL) == TRILOG_TRUE);
  CHECK(strcmp(answer, "1500.0") == 0);
  CHECK(trilog_query(t, "append(X, [3], [1, 2, 3])", first, NULL) ==
        TRILOG_TRUE);
  CHECK(strcmp(answer, "[1, 2]") == 0);
  CHECK(trilog_query(t,
                     "catch(get_time_ms(_), error(E, _), true), "
                     "E = existence_error(_, _), X = no_platform_predicates",
                     last, NULL) == TRILOG_TRUE);
  CHECK(strcmp(answer, "no_platform_predicates") == 0);
  trilog_free(t);
  return failures != 0;
}

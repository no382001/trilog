#include "trilog.h"
#include <stdio.h>

int unify(int a, int b) { return a + b; }
int heap_init(void) { return 7; }
int atom_intern(const char *s) { return s[0]; }
int db_add(int x) { return x; }
int consult_file(int x) { return x; }
int arena_alloc(int x) { return x; }
int platform_monotonic_ms(void) { return 0; }

static bool first(trilog_t *t, void *ud, bool has_more) {
  (void)has_more;
  trilog_get_int(t, trilog_binding_value(t, trilog_binding_count(t) - 1), ud);
  return false;
}

int main(void) {
  trilog_t *t = trilog_new(&(trilog_config_t){.boot_path = "boot/core.pl"});
  if (!t)
    return 1;
  int64_t n = 0;
  trilog_status_t s =
      trilog_query(t, "X = f(Y), Y = 2, N is 40 + Y", first, &n);
  trilog_free(t);
  if (s != TRILOG_TRUE || n != 42 || unify(1, 2) != 3 || heap_init() != 7) {
    fprintf(stderr, "api_namespace_test: failed\n");
    return 1;
  }
  printf("api_namespace_test: ok\n");
  return 0;
}

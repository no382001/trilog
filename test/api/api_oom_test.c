#include "trilog.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  long calls;
  long fail_at;
  long live;
} counter;

static void *counting_realloc(void *ud, void *p, size_t n) {
  counter *c = ud;
  if (++c->calls == c->fail_at)
    return NULL;
  void *r = realloc(p, n);
  if (r && !p)
    c->live++;
  return r;
}

static void counting_free(void *ud, void *p) {
  counter *c = ud;
  c->live--;
  free(p);
}

static bool first_int(trilog_t *t, void *ud, bool has_more) {
  (void)has_more;
  int64_t *n = ud;
  if (!trilog_get_int(t, trilog_binding_value(t, trilog_binding_count(t) - 1),
                      n))
    *n = -1;
  return false;
}

static bool ignore(trilog_t *t, void *ud, bool has_more) {
  (void)t;
  (void)ud;
  (void)has_more;
  return true;
}

static const char *const workload[] = {
    "assertz(k(1)), assertz(k(2)), asserta(k(0)), retract(k(1))",
    "findall(X, k(X), L), msort(L, S), length(S, N)",
    "atom_codes(A, \"hello\"), atom_length(A, N)",
    "catch(throw(oops(1)), oops(N), true)",
    "numlist(1, 20000, L), sum_list(L, N)",
    "X = f(X), Y = f(Y), X = Y, N = 1",
    "undefined_pred_here",
};

static int failures = 0;

static void fail(long n, const char *what) {
  printf("fail_at=%ld: %s\n", n, what);
  failures++;
}

int main(void) {
  long n = 1;
  for (;; n++) {
    counter c = {.fail_at = n};
    trilog_config_t cfg = {.boot_path = "boot/core.pl",
                           .realloc = counting_realloc,
                           .free = counting_free,
                           .alloc_ud = &c};
    trilog_t *t = trilog_new(&cfg);
    if (!t) {
      if (c.calls < n)
        fail(n, "trilog_new failed without an allocation failure");
      if (c.live != 0)
        fail(n, "trilog_new leaked after failing");
      continue;
    }
    trilog_load_string(t, "w(7).\n:- dynamic(k/1).\n");
    for (size_t i = 0; i < sizeof workload / sizeof *workload; i++)
      trilog_query(t, workload[i], ignore, NULL);

    long reached = c.calls;
    c.fail_at = -1;
    int64_t v = 0;
    if (trilog_query(t, "atom_length(hello, N)", first_int, &v) !=
            TRILOG_TRUE ||
        v != 5)
      fail(n, "interpreter unusable after the failure");
    if (trilog_load_string(t, "after(42).") != TRILOG_TRUE ||
        trilog_query(t, "after(N)", first_int, &v) != TRILOG_TRUE || v != 42)
      fail(n, "cannot load after the failure");
    v = 0;
    if (trilog_query(t, "numlist(1, 20000, L), sum_list(L, N)", first_int,
                     &v) != TRILOG_TRUE ||
        v != 200010000)
      fail(n, "wrong answer after the failure");
    trilog_free(t);
    if (c.live != 0)
      fail(n, "leaked allocations");
    if (reached < n)
      break;
  }
  if (failures) {
    printf("api_oom_test: %d failure(s)\n", failures);
    return 1;
  }
  printf("api_oom_test: ok (failed each of %ld allocations)\n", n - 1);
  return 0;
}

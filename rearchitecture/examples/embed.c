#include "trilog.h"
#include <stdio.h>
#include <time.h>

static bool c_square(trilog_t *t, void *ud, const trilog_value_t *in,
                     trilog_value_t *out) {
  (void)t;
  (void)ud;
  out[0].i = in[0].i * in[0].i;
  return true;
}

static bool print_answer(trilog_t *t, void *ud, bool has_more) {
  (void)ud;
  (void)has_more;
  for (int i = 0; i < trilog_binding_count(t); i++) {
    char text[128];
    trilog_format(t, trilog_binding_value(t, i), TRILOG_FORMAT_QUOTED, text,
                  sizeof text);
    printf("%s%s = %s", i ? ", " : "", trilog_binding_name(t, i), text);
  }
  printf("\n");
  return true;
}

static bool before_deadline(trilog_t *t, size_t depth, void *ud) {
  (void)t;
  (void)depth;
  return clock() < *(clock_t *)ud;
}

int main(void) {
  trilog_t *t = trilog_new(&(trilog_config_t){.boot_path = "boot/core.pl"});
  if (!t)
    return 1;

  trilog_register(t, "square", "i>i", c_square, NULL);
  trilog_load_string(t, "edge(a, b). edge(b, c).\n"
                        "path(X, Y) :- edge(X, Y).\n"
                        "path(X, Z) :- edge(X, Y), path(Y, Z).\n"
                        "forever :- forever.\n");

  trilog_query(t, "path(a, Where)", print_answer, NULL);
  trilog_query(t, "square(12, N)", print_answer, NULL);

  clock_t deadline = clock() + CLOCKS_PER_SEC / 10;
  trilog_set_yield(t, before_deadline, 10000, &deadline);
  if (trilog_query(t, "forever", print_answer, NULL) == TRILOG_ABORTED)
    printf("forever: stopped after 0.1s\n");

  trilog_free(t);
  return 0;
}

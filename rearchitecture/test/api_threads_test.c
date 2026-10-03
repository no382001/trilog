#include "trilog.h"
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#define THREADS 4
#define ROUNDS 3

typedef struct {
  int id;
  int failures;
} worker;

static bool expect_n(trilog_t *t, void *ud, bool has_more) {
  (void)has_more;
  int64_t *n = ud;
  if (!trilog_get_int(t, trilog_binding_value(t, trilog_binding_count(t) - 1),
                      n))
    *n = -1;
  return false;
}

static void *run(void *arg) {
  worker *w = arg;
  for (int round = 0; round < ROUNDS; round++) {
    trilog_t *t = trilog_new(&(trilog_config_t){.boot_path = "boot/core.pl"});
    if (!t) {
      w->failures++;
      continue;
    }
    char src[64];
    snprintf(src, sizeof src, "mine(%d).", w->id);
    if (!trilog_load_string(t, src))
      w->failures++;
    int64_t n = 0;
    if (trilog_query(t,
                     "mine(I), numlist(1, 30000, L), sum_list(L, S), "
                     "assertz(seen(S)), retract(seen(S)), N is S + I",
                     expect_n, &n) != TRILOG_TRUE ||
        n != 450015000 + w->id)
      w->failures++;
    if (trilog_query(t, "catch(throw(x), x, true)", expect_n, &n) !=
        TRILOG_TRUE)
      w->failures++;
    trilog_free(t);
  }
  return NULL;
}

int main(void) {
  pthread_t threads[THREADS];
  worker workers[THREADS];
  for (int i = 0; i < THREADS; i++) {
    workers[i] = (worker){.id = i};
    if (pthread_create(&threads[i], NULL, run, &workers[i]) != 0) {
      fprintf(stderr, "pthread_create failed\n");
      return 1;
    }
  }
  int failures = 0;
  for (int i = 0; i < THREADS; i++) {
    pthread_join(threads[i], NULL);
    failures += workers[i].failures;
  }
  if (failures) {
    fprintf(stderr, "api_threads_test: %d failure(s)\n", failures);
    return 1;
  }
  printf("api_threads_test: ok\n");
  return 0;
}

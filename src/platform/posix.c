#define _POSIX_C_SOURCE 200809L
#include "platform.h"
#include <sys/resource.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

bool platform_cwd(char *buf, size_t cap) { return getcwd(buf, cap) != NULL; }

size_t platform_address_space_limit(void) {
  struct rlimit rl;
  if (getrlimit(RLIMIT_AS, &rl) != 0 || rl.rlim_cur == RLIM_INFINITY)
    return 0;
  return (size_t)rl.rlim_cur;
}

static bool get_time_ms(trilog_t *t, void *ud, const trilog_value_t *in,
                        trilog_value_t *out) {
  (void)t;
  (void)ud;
  (void)in;
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  out[0].i = (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
  return true;
}

static bool file_mtime(trilog_t *t, void *ud, const trilog_value_t *in,
                       trilog_value_t *out) {
  (void)t;
  (void)ud;
  struct stat st;
  if (stat(in[0].a, &st) != 0)
    return false;
  out[0].i = (int64_t)st.st_mtime;
  return true;
}

void platform_register(trilog_t *t) {
  trilog_register(t, "get_time_ms", ">i", get_time_ms, NULL);
  trilog_register(t, "file_mtime", "a>i", file_mtime, NULL);
}

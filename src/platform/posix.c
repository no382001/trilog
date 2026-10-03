#define _POSIX_C_SOURCE 200809L
#include "platform.h"
#include <sys/resource.h>
#include <sys/stat.h>
#include <time.h>

long long platform_monotonic_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

size_t platform_address_space_limit(void) {
  struct rlimit rl;
  if (getrlimit(RLIMIT_AS, &rl) != 0 || rl.rlim_cur == RLIM_INFINITY)
    return 0;
  return (size_t)rl.rlim_cur;
}

long long platform_file_mtime(const char *path) {
  struct stat st;
  return stat(path, &st) == 0 ? (long long)st.st_mtime : -1LL;
}

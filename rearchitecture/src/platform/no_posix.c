#include "platform.h"
#include <stdio.h>
#include <time.h>

long long platform_monotonic_ms(void) {
  struct timespec ts;
  if (timespec_get(&ts, TIME_UTC) != TIME_UTC)
    return 0;
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

size_t platform_address_space_limit(void) { return 0; }

long long platform_file_mtime(const char *path) {
  (void)path;
  return -1;
}

bool platform_stdin_is_tty(void) { return true; }

int platform_read_key(void) { return getchar(); }

bool platform_executable_path(char *buf, size_t cap) {
  (void)buf;
  (void)cap;
  return false;
}

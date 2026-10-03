#define _POSIX_C_SOURCE 200809L
#include "platform.h"
#include <stdio.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

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

bool platform_stdin_is_tty(void) { return isatty(fileno(stdin)); }

int platform_read_key(void) {
  struct termios old, raw;
  if (tcgetattr(STDIN_FILENO, &old) != 0)
    return getchar();
  raw = old;
  raw.c_lflag &= ~(ICANON | ECHO);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
  int c = getchar();
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &old);
  return c;
}

bool platform_executable_path(char *buf, size_t cap) {
  if (cap == 0)
    return false;
  ssize_t len = readlink("/proc/self/exe", buf, cap - 1);
  if (len <= 0)
    return false;
  buf[len] = '\0';
  return true;
}

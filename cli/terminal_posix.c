#define _POSIX_C_SOURCE 200809L
#include "terminal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

bool terminal_stdin_is_tty(void) { return isatty(fileno(stdin)); }

static struct termios cooked;
static bool raw_on;

bool terminal_raw(bool on) {
  if (on == raw_on)
    return true;
  if (on) {
    if (!isatty(STDIN_FILENO) || tcgetattr(STDIN_FILENO, &cooked) != 0)
      return false;
    struct termios raw = cooked;
    raw.c_lflag &= ~(ICANON | ECHO);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
  } else {
    tcsetattr(STDIN_FILENO, TCSANOW, &cooked);
  }
  raw_on = on;
  return true;
}

int terminal_read_key(void) {
  if (raw_on)
    return getchar();
  struct termios old, raw;
  if (tcgetattr(STDIN_FILENO, &old) != 0)
    return getchar();
  raw = old;
  raw.c_lflag &= ~(ICANON | ECHO);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  tcsetattr(STDIN_FILENO, TCSANOW, &raw);
  int c = getchar();
  tcsetattr(STDIN_FILENO, TCSANOW, &old);
  return c;
}

bool terminal_read_line(char *buf, size_t cap) {
  if (!fgets(buf, (int)cap, stdin))
    return false;
  buf[strcspn(buf, "\n")] = '\0';
  return true;
}

bool terminal_executable_path(char *buf, size_t cap) {
  if (cap == 0)
    return false;
  ssize_t len = readlink("/proc/self/exe", buf, cap - 1);
  if (len <= 0)
    return false;
  buf[len] = '\0';
  return true;
}

bool terminal_history_path(char *buf, size_t cap) {
  const char *home = getenv("HOME");
  if (!home || !home[0])
    return false;
  int n = snprintf(buf, cap, "%s/.trilog_history", home);
  return n > 0 && (size_t)n < cap;
}

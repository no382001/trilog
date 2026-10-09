#define _POSIX_C_SOURCE 200809L
#include "terminal.h"
#include <stdio.h>
#include <termios.h>
#include <unistd.h>

bool terminal_stdin_is_tty(void) { return isatty(fileno(stdin)); }

int terminal_read_key(void) {
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

bool terminal_executable_path(char *buf, size_t cap) {
  if (cap == 0)
    return false;
  ssize_t len = readlink("/proc/self/exe", buf, cap - 1);
  if (len <= 0)
    return false;
  buf[len] = '\0';
  return true;
}

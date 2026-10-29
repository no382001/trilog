#include "terminal.h"
#include <stdio.h>

bool terminal_stdin_is_tty(void) { return true; }

int terminal_read_key(void) { return getchar(); }

// USB serial does not echo, so this echoes and handles backspace itself.
bool terminal_read_line(char *buf, size_t cap) {
  size_t i = 0;
  for (;;) {
    int c = getchar();
    if (c == EOF)
      return false;
    if (c == '\r' || c == '\n') {
      putchar('\n');
      break;
    }
    if (c == 127 || c == '\b') {
      if (i > 0) {
        i--;
        fputs("\b \b", stdout);
      }
      continue;
    }
    if (i + 1 < cap) {
      buf[i++] = (char)c;
      putchar(c);
    }
  }
  buf[i] = '\0';
  return true;
}

bool terminal_executable_path(char *buf, size_t cap) {
  (void)buf, (void)cap;
  return false;
}

#include "terminal.h"
#include <stdio.h>

bool terminal_stdin_is_tty(void) { return true; }

int terminal_read_key(void) { return getchar(); }

bool terminal_executable_path(char *buf, size_t cap) {
  (void)buf;
  (void)cap;
  return false;
}

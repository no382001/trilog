#include "terminal.h"
#include <stdio.h>
#include <string.h>

bool terminal_stdin_is_tty(void) { return true; }

int terminal_read_key(void) { return getchar(); }

bool terminal_read_line(char *buf, size_t cap) {
  if (!fgets(buf, (int)cap, stdin))
    return false;
  buf[strcspn(buf, "\n")] = '\0';
  return true;
}

bool terminal_executable_path(char *buf, size_t cap) {
  (void)buf;
  (void)cap;
  return false;
}

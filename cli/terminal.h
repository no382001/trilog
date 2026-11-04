#pragma once
#include <stdbool.h>
#include <stddef.h>

bool terminal_stdin_is_tty(void);

int terminal_read_key(void);

// One line without its newline; false at end of input.
bool terminal_read_line(char *buf, size_t cap);

bool terminal_executable_path(char *buf, size_t cap);

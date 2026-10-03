#pragma once
#include <stdbool.h>
#include <stddef.h>

bool terminal_stdin_is_tty(void);

int terminal_read_key(void);

bool terminal_executable_path(char *buf, size_t cap);

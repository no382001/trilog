#pragma once
#include <stdbool.h>
#include <stddef.h>

bool terminal_stdin_is_tty(void);

int terminal_read_key(void);

// Raw input for a line editor: no echo and no line buffering, until switched
// off. False when the terminal cannot do it.
bool terminal_raw(bool on);

// One line without its newline; false at end of input.
bool terminal_read_line(char *buf, size_t cap);

bool terminal_executable_path(char *buf, size_t cap);

// Where the REPL keeps its history; false if there is no such place.
bool terminal_history_path(char *buf, size_t cap);

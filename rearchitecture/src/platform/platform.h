#pragma once
#include <stdbool.h>
#include <stddef.h>

long long platform_monotonic_ms(void);

size_t platform_address_space_limit(void);

long long platform_file_mtime(const char *path);

bool platform_stdin_is_tty(void);

int platform_read_key(void);

bool platform_executable_path(char *buf, size_t cap);

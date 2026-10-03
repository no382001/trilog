#pragma once
#include <stddef.h>

long long platform_monotonic_ms(void);

size_t platform_address_space_limit(void);

long long platform_file_mtime(const char *path);

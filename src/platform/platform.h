#pragma once
#include "trilog.h"
#include <stddef.h>

size_t platform_address_space_limit(void);

// The current directory, or false where there is none.
bool platform_cwd(char *buf, size_t cap);

void platform_register(trilog_t *t);

#pragma once
#include "trilog.h"
#include <stddef.h>

size_t platform_address_space_limit(void);

// The current directory, or false where there is none.
bool platform_cwd(char *buf, size_t cap);

void platform_register(trilog_t *t);

// Fill in the allocator or I/O used when the config gives none; false where
// the platform has none.
bool platform_default_alloc(trilog_config_t *c);
bool platform_default_io(trilog_io_t *io);

#pragma once
#include "trilog.h"
#include "trilog_platform.h"
#include <stddef.h>

size_t platform_address_space_limit(void);

bool platform_cwd(char *buf, size_t cap);

void platform_register(trilog_t *t);

bool platform_default_alloc(trilog_config_t *c);
bool platform_default_io(trilog_io_t *io);

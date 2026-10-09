#include "platform.h"

size_t platform_address_space_limit(void) { return 0; }

bool platform_cwd(char *buf, size_t cap) {
  (void)buf, (void)cap;
  return false;
}

void platform_register(trilog_t *t) { (void)t; }

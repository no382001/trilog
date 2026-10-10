#include "platform.h"

bool platform_default_alloc(trilog_config_t *c) {
  (void)c;
  return false;
}

bool platform_default_io(trilog_io_t *io) {
  (void)io;
  return false;
}

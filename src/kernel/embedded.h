#pragma once
#include <stddef.h>

typedef struct {
  const char *path; // as given to the generator, e.g. "lib/lists.pl"
  const char *data; // NUL-terminated
  size_t len;
} embedded_file;

extern const embedded_file embedded_files[];

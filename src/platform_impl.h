#ifndef ABCLOG_FREESTANDING
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "abclog.h"

#ifndef ABCLOG_FREESTANDING
#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

static inline long long abclog_file_mtime(const char *path) {
  struct stat st;
  return (stat(path, &st) == 0) ? (long long)st.st_mtime : -1LL;
}

#else // ABCLOG_FREESTANDING

// user may define abclog_file_mtime(path) -> long long before including this
// header; if not defined, make/0 treats every file as always-changed
#ifndef abclog_file_mtime
#define abclog_file_mtime(path) (-1LL)
#endif

#endif
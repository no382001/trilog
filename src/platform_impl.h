#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "trilog.h"

#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

static inline long long trilog_file_mtime(const char *path) {
  struct stat st;
  return (stat(path, &st) == 0) ? (long long)st.st_mtime : -1LL;
}
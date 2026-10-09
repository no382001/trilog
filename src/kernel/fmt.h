#pragma once
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

size_t fmt(char *buf, size_t cap, const char *f, ...);
size_t fmt_v(char *buf, size_t cap, const char *f, va_list ap);

bool parse_int(const char *s, const char **end, int64_t *out);

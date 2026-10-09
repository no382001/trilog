#pragma once
#include <stdbool.h>

static inline bool ascii_digit(int c) { return c >= '0' && c <= '9'; }
static inline bool ascii_lower(int c) { return c >= 'a' && c <= 'z'; }
static inline bool ascii_upper(int c) { return c >= 'A' && c <= 'Z'; }
static inline bool ascii_alnum(int c) {
  return ascii_digit(c) || ascii_lower(c) || ascii_upper(c);
}
static inline bool ascii_space(int c) {
  return c == ' ' || (c >= '\t' && c <= '\r');
}

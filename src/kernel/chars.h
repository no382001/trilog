#pragma once
#include <stdbool.h>
#include <string.h>

static inline bool ascii_digit(int c) { return c >= '0' && c <= '9'; }
static inline bool ascii_lower(int c) { return c >= 'a' && c <= 'z'; }
static inline bool ascii_upper(int c) { return c >= 'A' && c <= 'Z'; }
static inline bool ascii_alnum(int c) {
  return ascii_digit(c) || ascii_lower(c) || ascii_upper(c);
}
static inline bool ascii_symbol(int c) {
  return c != '\0' && strchr("+-*/\\^<>=~:.?@#&$", c) != NULL;
}
static inline bool ascii_space(int c) {
  return c == ' ' || (c >= '\t' && c <= '\r');
}

static const char control_escapes[] = "a\ab\bf\fn\nr\rt\tv\v";

static inline int escape_char(int letter) {
  for (const char *p = control_escapes; *p; p += 2)
    if (p[0] == letter)
      return (unsigned char)p[1];
  return -1;
}

static inline char escape_letter(int c) {
  for (const char *p = control_escapes; *p; p += 2)
    if (p[1] == c)
      return p[0];
  return 0;
}

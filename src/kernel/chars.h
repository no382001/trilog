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

// A character outside ASCII is a letter: it can start an atom and continue a
// name. TODO: in this way Unicode characters can never be Variable names
static inline bool name_start(int c) { return ascii_lower(c) || c >= 0x80; }
static inline bool name_char(int c) {
  return ascii_alnum(c) || c == '_' || c >= 0x80;
}

// The length of the UTF-8 sequence a lead byte starts; 1 for a byte that
// cannot start one.
static inline int utf8_len(int lead) {
  return lead >= 0xC2 && lead <= 0xDF   ? 2
         : lead >= 0xE0 && lead <= 0xEF ? 3
         : lead >= 0xF0 && lead <= 0xF4 ? 4
                                        : 1;
}

// The character at s, as a code, and the bytes it takes. A byte that does not
// start a well-formed sequence is one character, its own code.
static inline int utf8_decode(const char *s, int *code) {
  const unsigned char *u = (const unsigned char *)s;
  int n = utf8_len(u[0]);
  int c = n == 2 ? u[0] & 0x1F : n == 3 ? u[0] & 0x0F : u[0] & 0x07;
  for (int i = 1; i < n; i++) {
    if ((u[i] & 0xC0) != 0x80) {
      n = 1;
      break;
    }
    c = c << 6 | (u[i] & 0x3F);
  }
  if (n == 1 || (n == 3 && (c < 0x800 || (c >= 0xD800 && c <= 0xDFFF))) ||
      (n == 4 && (c < 0x10000 || c > 0x10FFFF))) {
    *code = u[0];
    return 1;
  }
  *code = c;
  return n;
}

// Writes c's UTF-8 bytes to out, which has room for 4; returns how many.
static inline int utf8_encode(int c, char *out) {
  if (c < 0x80) {
    out[0] = (char)c;
    return 1;
  }
  if (c < 0x800) {
    out[0] = (char)(0xC0 | c >> 6);
    out[1] = (char)(0x80 | (c & 0x3F));
    return 2;
  }
  if (c < 0x10000) {
    out[0] = (char)(0xE0 | c >> 12);
    out[1] = (char)(0x80 | (c >> 6 & 0x3F));
    out[2] = (char)(0x80 | (c & 0x3F));
    return 3;
  }
  out[0] = (char)(0xF0 | c >> 18);
  out[1] = (char)(0x80 | (c >> 12 & 0x3F));
  out[2] = (char)(0x80 | (c >> 6 & 0x3F));
  out[3] = (char)(0x80 | (c & 0x3F));
  return 4;
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

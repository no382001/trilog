#pragma once
// A LIBC=0 build leaves these two to the embedder and links memcpy, memmove,
// memset, strlen, strcmp, strncmp, strchr, strrchr, strncat, strpbrk, setjmp,
// longjmp, libm and, on 32-bit targets, libgcc.
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Float text as %g writes it and strtod reads it. trilog_format_float returns
// the full length, like snprintf; trilog_parse_float sets *end to s when there
// is no number.
size_t trilog_format_float(char *buf, size_t cap, double v);
double trilog_parse_float(const char *s, const char **end);

#ifdef __cplusplus
}
#endif

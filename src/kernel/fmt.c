#include "fmt.h"
#include "chars.h"
#include "platform.h"
#include <string.h>

typedef struct {
  char *buf;
  size_t cap, len;
} out_t;

static void put(out_t *o, char c) {
  if (o->len + 1 < o->cap)
    o->buf[o->len] = c;
  o->len++;
}

static void put_str(out_t *o, const char *s, size_t n) {
  for (size_t i = 0; i < n; i++)
    put(o, s[i]);
}

static void put_uint(out_t *o, uint64_t u, bool neg) {
  char digits[20];
  int n = 0;
  do {
    digits[n++] = (char)('0' + u % 10);
    u /= 10;
  } while (u);
  if (neg)
    put(o, '-');
  while (n)
    put(o, digits[--n]);
}

static void put_int(out_t *o, int64_t v) {
  put_uint(o, v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v, v < 0);
}

static size_t trim_zeros(char *s, size_t n) {
  size_t exp = 0;
  while (exp < n && s[exp] != 'e' && s[exp] != 'E')
    exp++;
  size_t dot = 0;
  while (dot < exp && s[dot] != '.')
    dot++;
  if (dot == exp)
    return n;
  size_t end = exp;
  while (end > dot + 1 && s[end - 1] == '0')
    end--;
  if (end == dot + 1)
    end = dot;
  memmove(s + end, s + exp, n - exp);
  return end + (n - exp);
}

size_t fmt_v(char *buf, size_t cap, const char *f, va_list ap) {
  out_t o = {buf, cap, 0};
  while (*f) {
    if (*f != '%') {
      put(&o, *f++);
      continue;
    }
    const char *spec = f++;
    size_t prec = (size_t)-1;
    if (*f == '.') {
      f++;
      if (*f == '*') {
        int p = va_arg(ap, int);
        prec = p < 0 ? (size_t)-1 : (size_t)p;
        f++;
      } else {
        prec = 0;
        while (ascii_digit(*f))
          prec = prec * 10 + (size_t)(*f++ - '0');
      }
    }
    int longs = 0;
    bool size = false;
    while (*f == 'l')
      longs++, f++;
    if (*f == 'z')
      size = true, f++;
    switch (*f) {
    case '%':
      put(&o, '%');
      break;
    case 'c':
      put(&o, (char)va_arg(ap, int));
      break;
    case 's': {
      const char *s = va_arg(ap, const char *);
      if (!s)
        s = "(null)";
      size_t n = strlen(s);
      put_str(&o, s, n < prec ? n : prec);
      break;
    }
    case 'd':
      if (size)
        put_int(&o, (int64_t)va_arg(ap, ptrdiff_t));
      else if (longs >= 2)
        put_int(&o, (int64_t)va_arg(ap, long long));
      else if (longs == 1)
        put_int(&o, (int64_t)va_arg(ap, long));
      else
        put_int(&o, va_arg(ap, int));
      break;
    case 'u':
      if (size)
        put_uint(&o, va_arg(ap, size_t), false);
      else if (longs >= 2)
        put_uint(&o, va_arg(ap, unsigned long long), false);
      else if (longs == 1)
        put_uint(&o, va_arg(ap, unsigned long), false);
      else
        put_uint(&o, va_arg(ap, unsigned), false);
      break;
    case 'g': {
      char tmp[32];
      size_t n = trilog_format_float(tmp, sizeof tmp, va_arg(ap, double));
      put_str(&o, tmp, trim_zeros(tmp, n < sizeof tmp ? n : sizeof tmp - 1));
      break;
    }
    default:
      put_str(&o, spec, (size_t)(f - spec) + (*f != '\0'));
      if (!*f)
        continue;
    }
    f++;
  }
  if (cap)
    buf[o.len < cap ? o.len : cap - 1] = '\0';
  return o.len;
}

size_t fmt(char *buf, size_t cap, const char *f, ...) {
  va_list ap;
  va_start(ap, f);
  size_t n = fmt_v(buf, cap, f, ap);
  va_end(ap);
  return n;
}

bool parse_int(const char *s, const char **end, int64_t *out) {
  const char *p = s;
  while (ascii_space(*p))
    p++;
  bool neg = *p == '-';
  if (*p == '-' || *p == '+')
    p++;
  if (!ascii_digit(*p)) {
    if (end)
      *end = s;
    *out = 0;
    return true;
  }
  uint64_t limit = neg ? (uint64_t)INT64_MAX + 1 : (uint64_t)INT64_MAX;
  uint64_t u = 0;
  bool fits = true;
  for (; ascii_digit(*p); p++) {
    unsigned d = (unsigned)(*p - '0');
    if (u > (limit - d) / 10)
      fits = false;
    else
      u = u * 10 + d;
  }
  if (end)
    *end = p;
  if (!fits)
    *out = neg ? INT64_MIN : INT64_MAX;
  else
    *out = !neg                           ? (int64_t)u
           : u == (uint64_t)INT64_MAX + 1 ? INT64_MIN
                                          : -(int64_t)u;
  return fits;
}

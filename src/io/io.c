#include "io.h"
#include "ctx.h"
#include "mem.h"
#include "platform.h"
#include <string.h>

bool io_cwd(trilog_t *T, char *buf, size_t cap) {
  return T->default_io && platform_cwd(buf, cap);
}

bool io_set(trilog_t *T, const trilog_io_t *io) {
  trilog_io_t h = io ? *io : (trilog_io_t){0};
  int given = !!h.open + !!h.read + !!h.write + !!h.close;
  if (given == 0) {
    if (!platform_default_io(&h))
      return false;
  } else if (given != 4) {
    return false;
  }
  T->hooks = h;
  T->default_io = given == 0;
  return true;
}

static void capture_append(trilog_t *T, const char *str) {
  size_t len = strlen(str);
  mem_reserve(T, (void **)&T->capture_buf, &T->capture_cap,
              T->capture_pos + len + 1);
  memcpy(T->capture_buf + T->capture_pos, str, len + 1);
  T->capture_pos += len;
}

static bool write_all(trilog_t *T, void *handle, const char *str) {
  size_t n = strlen(str);
  while (n > 0) {
    long k = T->hooks.write(T->hooks.userdata, handle, str, n);
    if (k <= 0)
      return false;
    str += k;
    n -= (size_t)k;
  }
  return true;
}

static void io_write(trilog_t *T, void *handle, const char *str) {
  write_all(T, handle, str);
}

void io_write_str(trilog_t *T, const char *str) {
  if (T->capture_sp > 0) {
    capture_append(T, str);
    return;
  }
  io_write(T, T->hooks.out, str);
}
void io_write_err(trilog_t *T, const char *str) {
  io_write(T, T->hooks.err, str);
}
void io_flush_target(trilog_t *T, void *handle) {
  if ((T->capture_sp > 0 && handle == T->hooks.out) || !T->hooks.flush)
    return;
  T->hooks.flush(T->hooks.userdata, handle);
}

// One byte at a time, so input meant for the host is never read ahead
// further than a peek asks.
int io_peek_at(trilog_t *T, int i) {
  while (T->in_ahead_len <= i) {
    char c;
    if (T->in_eof ||
        T->hooks.read(T->hooks.userdata, T->hooks.in, &c, 1) != 1) {
      T->in_eof = true;
      return -1;
    }
    T->in_ahead[T->in_ahead_len++] = (unsigned char)c;
  }
  return T->in_ahead[i];
}

int io_read_char(trilog_t *T) {
  int c = io_peek_at(T, 0);
  if (c < 0) {
    T->in_eof = false;
    return -1;
  }
  memmove(T->in_ahead, T->in_ahead + 1, (size_t)--T->in_ahead_len);
  return c;
}

int io_peek_char(trilog_t *T) { return io_peek_at(T, 0); }

char *io_read_line(trilog_t *T, char *buf, int size) {
  int n = 0;
  while (n < size - 1) {
    int c = io_read_char(T);
    if (c < 0)
      break;
    buf[n++] = (char)c;
    if (c == '\n')
      break;
  }
  buf[n] = '\0';
  return n > 0 ? buf : NULL;
}

void *io_file_open(trilog_t *T, const char *path, const char *mode) {
  return T->hooks.open(T->hooks.userdata, path, mode);
}
void io_file_close(trilog_t *T, void *handle) {
  if (handle)
    T->hooks.close(T->hooks.userdata, handle);
}
bool io_file_write(trilog_t *T, void *handle, const char *str) {
  return write_all(T, handle, str);
}

long io_file_read(trilog_t *T, void *handle, char *buf, size_t n) {
  return T->hooks.read(T->hooks.userdata, handle, buf, n);
}

int io_reader_peek_at(trilog_t *T, io_reader_t *r, int i) {
  if (r->pos + (size_t)i >= r->len) {
    memmove(r->buf, r->buf + r->pos, r->len - r->pos);
    r->len -= r->pos;
    r->pos = 0;
    while (r->len <= (size_t)i) {
      long got = T->hooks.read(T->hooks.userdata, r->handle, r->buf + r->len,
                               sizeof r->buf - r->len);
      if (got <= 0)
        return -1;
      r->len += (size_t)got;
    }
  }
  return (unsigned char)r->buf[r->pos + (size_t)i];
}

int io_reader_byte(trilog_t *T, io_reader_t *r, bool peek) {
  if (r->pos == r->len) {
    long got =
        T->hooks.read(T->hooks.userdata, r->handle, r->buf, sizeof r->buf);
    if (got <= 0)
      return -1;
    r->pos = 0;
    r->len = (size_t)got;
  }
  unsigned char c = (unsigned char)r->buf[r->pos];
  if (!peek)
    r->pos++;
  return c;
}

char *io_reader_line(trilog_t *T, io_reader_t *r, char *buf, int size) {
  int n = 0;
  while (n < size - 1) {
    int c = io_reader_byte(T, r, false);
    if (c < 0)
      break;
    buf[n++] = (char)c;
    if (c == '\n')
      break;
  }
  buf[n] = '\0';
  return n > 0 ? buf : NULL;
}

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

static void io_write(trilog_t *T, void *handle, const char *str) {
  size_t n = strlen(str);
  if (n > 0)
    T->hooks.write(T->hooks.userdata, handle, str, n);
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
void io_flush(trilog_t *T) {
  if (T->capture_sp > 0 || !T->hooks.flush)
    return;
  T->hooks.flush(T->hooks.userdata, T->hooks.out);
}

// One byte at a time, so input meant for the host is never read ahead.
int io_read_char(trilog_t *T) {
  char c;
  return T->hooks.read(T->hooks.userdata, T->hooks.in, &c, 1) == 1
             ? (unsigned char)c
             : -1;
}

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
  size_t n = strlen(str);
  return T->hooks.write(T->hooks.userdata, handle, str, n) == (long)n;
}

long io_file_read(trilog_t *T, void *handle, char *buf, size_t n) {
  return T->hooks.read(T->hooks.userdata, handle, buf, n);
}

char *io_reader_line(trilog_t *T, io_reader_t *r, char *buf, int size) {
  int n = 0;
  while (n < size - 1) {
    if (r->pos == r->len) {
      long got =
          T->hooks.read(T->hooks.userdata, r->handle, r->buf, sizeof r->buf);
      if (got <= 0)
        break;
      r->pos = 0;
      r->len = (size_t)got;
    }
    char c = r->buf[r->pos++];
    buf[n++] = c;
    if (c == '\n')
      break;
  }
  buf[n] = '\0';
  return n > 0 ? buf : NULL;
}

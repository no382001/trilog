#include "io.h"
#include "ctx.h"
#include "platform.h"
#include <stdio.h>
#include <string.h>

static void default_write_str(void *ud, const char *str) {
  (void)ud;
  fputs(str, stdout);
}
static void default_write_err(void *ud, const char *str) {
  (void)ud;
  fputs(str, stderr);
}
static void default_flush(void *ud) {
  (void)ud;
  fflush(stdout);
}
static int default_read_char(void *ud) {
  (void)ud;
  return getchar();
}
static char *default_read_line(void *ud, char *buf, int size) {
  (void)ud;
  return fgets(buf, size, stdin);
}
static void *default_file_open(void *ud, const char *path, const char *mode) {
  (void)ud;
  return fopen(path, mode);
}
static void default_file_close(void *ud, void *handle) {
  (void)ud;
  if (handle)
    fclose(handle);
}
static char *default_file_read_line(void *ud, void *handle, char *buf,
                                    int size) {
  (void)ud;
  return fgets(buf, size, handle);
}
static bool default_file_write(void *ud, void *handle, const char *str) {
  (void)ud;
  return fputs(str, handle) >= 0;
}
static bool default_file_exists(void *ud, const char *path) {
  (void)ud;
  FILE *f = fopen(path, "rb");
  if (f)
    fclose(f);
  return f != NULL;
}
static long long default_file_mtime(void *ud, const char *path) {
  (void)ud;
  return platform_file_mtime(path);
}

void io_set(trilog_t *T, const trilog_io_t *io) {
  trilog_io_t h = io ? *io : (trilog_io_t){0};
  if (!h.write_str)
    h.write_str = default_write_str;
  if (!h.write_err)
    h.write_err = default_write_err;
  if (!h.flush)
    h.flush = default_flush;
  if (!h.read_char)
    h.read_char = default_read_char;
  if (!h.read_line)
    h.read_line = default_read_line;
  if (!h.file_open)
    h.file_open = default_file_open;
  if (!h.file_close)
    h.file_close = default_file_close;
  if (!h.file_read_line)
    h.file_read_line = default_file_read_line;
  if (!h.file_write)
    h.file_write = default_file_write;
  if (!h.file_exists)
    h.file_exists = default_file_exists;
  if (!h.file_mtime)
    h.file_mtime = default_file_mtime;
  T->hooks = h;
}

static void capture_append(trilog_t *T, const char *str) {
  int len = (int)strlen(str);
  int rem = CAPTURE_BUF_SIZE - T->capture_pos - 1;
  if (len > rem)
    len = rem;
  if (len > 0) {
    memcpy(T->capture_buf + T->capture_pos, str, (size_t)len);
    T->capture_pos += len;
    T->capture_buf[T->capture_pos] = '\0';
  }
}

void io_write_str(trilog_t *T, const char *str) {
  if (T->capture_sp > 0) {
    capture_append(T, str);
    return;
  }
  T->hooks.write_str(T->hooks.userdata, str);
}
void io_write_err(trilog_t *T, const char *str) {
  T->hooks.write_err(T->hooks.userdata, str);
}
void io_flush(trilog_t *T) {
  if (T->capture_sp > 0)
    return;
  T->hooks.flush(T->hooks.userdata);
}
int io_read_char(trilog_t *T) { return T->hooks.read_char(T->hooks.userdata); }
char *io_read_line(trilog_t *T, char *buf, int size) {
  return T->hooks.read_line(T->hooks.userdata, buf, size);
}
void *io_file_open(trilog_t *T, const char *path, const char *mode) {
  return T->hooks.file_open(T->hooks.userdata, path, mode);
}
void io_file_close(trilog_t *T, void *handle) {
  T->hooks.file_close(T->hooks.userdata, handle);
}
char *io_file_read_line(trilog_t *T, void *handle, char *buf, int size) {
  return T->hooks.file_read_line(T->hooks.userdata, handle, buf, size);
}
bool io_file_write(trilog_t *T, void *handle, const char *str) {
  return T->hooks.file_write(T->hooks.userdata, handle, str);
}
bool io_file_exists(trilog_t *T, const char *path) {
  return T->hooks.file_exists(T->hooks.userdata, path);
}
long long io_file_mtime(trilog_t *T, const char *path) {
  return T->hooks.file_mtime(T->hooks.userdata, path);
}

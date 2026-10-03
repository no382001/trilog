#include "io.h"
#include "ctx.h"
#include "platform.h"
#include <stdio.h>
#include <string.h>

static void default_write_str(const char *str, void *ud) {
  (void)ud;
  fputs(str, stdout);
}
static void default_write_err(const char *str, void *ud) {
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
static char *default_read_line(char *buf, int size, void *ud) {
  (void)ud;
  return fgets(buf, size, stdin);
}
static void *default_file_open(const char *path, const char *mode, void *ud) {
  (void)ud;
  return fopen(path, mode);
}
static void default_file_close(void *handle, void *ud) {
  (void)ud;
  if (handle)
    fclose(handle);
}
static char *default_file_read_line(void *handle, char *buf, int size,
                                    void *ud) {
  (void)ud;
  return fgets(buf, size, handle);
}
static bool default_file_write(void *handle, const char *str, void *ud) {
  (void)ud;
  return fputs(str, handle) >= 0;
}
static bool default_file_exists(const char *path, void *ud) {
  (void)ud;
  FILE *f = fopen(path, "rb");
  if (f)
    fclose(f);
  return f != NULL;
}
static long long default_file_mtime(const char *path, void *ud) {
  (void)ud;
  return platform_file_mtime(path);
}

void io_hooks_init_default(trilog_t *T) {
  T->hooks = (io_hooks_t){
      .write_str = default_write_str,
      .write_err = default_write_err,
      .flush = default_flush,
      .read_char = default_read_char,
      .read_line = default_read_line,
      .file_open = default_file_open,
      .file_close = default_file_close,
      .file_read_line = default_file_read_line,
      .file_write = default_file_write,
      .file_exists = default_file_exists,
      .file_mtime = default_file_mtime,
      .userdata = NULL,
  };
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
  if (T->hooks.write_str)
    T->hooks.write_str(str, T->hooks.userdata);
}
void io_write_err(trilog_t *T, const char *str) {
  if (T->hooks.write_err)
    T->hooks.write_err(str, T->hooks.userdata);
}
void io_flush(trilog_t *T) {
  if (T->capture_sp > 0)
    return;
  if (T->hooks.flush)
    T->hooks.flush(T->hooks.userdata);
}
int io_read_char(trilog_t *T) {
  return T->hooks.read_char ? T->hooks.read_char(T->hooks.userdata) : -1;
}
char *io_read_line(trilog_t *T, char *buf, int size) {
  return T->hooks.read_line ? T->hooks.read_line(buf, size, T->hooks.userdata)
                            : NULL;
}
void *io_file_open(trilog_t *T, const char *path, const char *mode) {
  return T->hooks.file_open ? T->hooks.file_open(path, mode, T->hooks.userdata)
                            : NULL;
}
void io_file_close(trilog_t *T, void *handle) {
  if (T->hooks.file_close)
    T->hooks.file_close(handle, T->hooks.userdata);
}
char *io_file_read_line(trilog_t *T, void *handle, char *buf, int size) {
  return T->hooks.file_read_line
             ? T->hooks.file_read_line(handle, buf, size, T->hooks.userdata)
             : NULL;
}
bool io_file_write(trilog_t *T, void *handle, const char *str) {
  return T->hooks.file_write
             ? T->hooks.file_write(handle, str, T->hooks.userdata)
             : false;
}
bool io_file_exists(trilog_t *T, const char *path) {
  return T->hooks.file_exists ? T->hooks.file_exists(path, T->hooks.userdata)
                              : false;
}
long long io_file_mtime(trilog_t *T, const char *path) {
  return T->hooks.file_mtime ? T->hooks.file_mtime(path, T->hooks.userdata)
                             : -1LL;
}

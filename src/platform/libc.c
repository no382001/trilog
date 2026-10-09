#include "platform.h"
#include <stdio.h>
#include <stdlib.h>

static void *libc_realloc(void *ud, void *p, size_t n) {
  (void)ud;
  return realloc(p, n);
}

static void libc_free(void *ud, void *p) {
  (void)ud;
  free(p);
}

static void *libc_open(void *ud, const char *path, const char *mode) {
  (void)ud;
  return fopen(path, mode);
}

static long libc_read(void *ud, void *handle, char *buf, size_t n) {
  (void)ud;
  return (long)fread(buf, 1, n, handle);
}

static long libc_write(void *ud, void *handle, const char *buf, size_t n) {
  (void)ud;
  return (long)fwrite(buf, 1, n, handle);
}

static void libc_close(void *ud, void *handle) {
  (void)ud;
  fclose(handle);
}

static void libc_flush(void *ud, void *handle) {
  (void)ud;
  fflush(handle);
}

bool platform_default_alloc(trilog_config_t *c) {
  c->realloc = libc_realloc;
  c->free = libc_free;
  return true;
}

bool platform_default_io(trilog_io_t *io) {
  io->open = libc_open;
  io->read = libc_read;
  io->write = libc_write;
  io->close = libc_close;
  io->in = stdin;
  io->out = stdout;
  io->err = stderr;
  if (!io->flush)
    io->flush = libc_flush;
  return true;
}

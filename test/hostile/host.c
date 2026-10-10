#include "host.h"
#include "trilog_platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  size_t size;
  max_align_t align;
} header_t;

static void *hostile_realloc(void *ud, void *p, size_t n) {
  (void)ud;
  header_t *old = p ? (header_t *)p - 1 : NULL;
  header_t *h = malloc(sizeof *h + n);
  if (!h)
    return NULL;
  h->size = n;
  memset(h + 1, 0xAA, n);
  if (old) {
    memcpy(h + 1, old + 1, old->size < n ? old->size : n);
    free(old);
  }
  return h + 1;
}

static void hostile_free(void *ud, void *p) {
  (void)ud;
  if (p)
    free((header_t *)p - 1);
}

static void *hostile_open(void *ud, const char *path, const char *mode) {
  (void)ud;
  return fopen(path, mode);
}

static long hostile_read(void *ud, void *h, char *buf, size_t n) {
  (void)ud;
  return (long)fread(buf, 1, n < 1 ? n : 1, h);
}

static long hostile_write(void *ud, void *h, const char *buf, size_t n) {
  (void)ud;
  return (long)fwrite(buf, 1, n < 7 ? n : 7, h);
}

static void hostile_close(void *ud, void *h) {
  (void)ud;
  fclose(h);
}

static void hostile_flush(void *ud, void *h) {
  (void)ud;
  fflush(h);
}

static trilog_io_t io = {.open = hostile_open,
                         .read = hostile_read,
                         .write = hostile_write,
                         .close = hostile_close,
                         .flush = hostile_flush};

void host_config(trilog_config_t *c) {
  io.in = stdin;
  io.out = stdout;
  io.err = stderr;
  c->realloc = hostile_realloc;
  c->free = hostile_free;
  c->io = &io;
}

size_t trilog_format_float(char *buf, size_t cap, double v) {
  int n = snprintf(buf, cap, "%#g", v);
  return n < 0 ? 0 : (size_t)n;
}

double trilog_parse_float(const char *s, const char **end) {
  char *e;
  double v = strtod(s, &e);
  if (end)
    *end = e;
  return v;
}

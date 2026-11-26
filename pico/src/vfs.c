#include "vfs.h"
#include "../src/kernel/embedded.h"
#include "tcp.h"
#include <string.h>

extern const char *const prolog_files[][2];

static const embedded_file *file_at(int64_t i) {
  int64_t n = 0;
  while (embedded_files[n].path)
    n++;
  if (i < 0)
    return NULL;
  if (i < n)
    return &embedded_files[i];
  for (int64_t j = 0; prolog_files[j][0]; j++) {
    if (n + j == i) {
      static embedded_file f;
      f = (embedded_file){prolog_files[j][0], prolog_files[j][1],
                          strlen(prolog_files[j][1])};
      return &f;
    }
  }
  return NULL;
}

static bool vfs_file(trilog_t *t, void *ud, const trilog_value_t *in,
                     trilog_value_t *out) {
  (void)t, (void)ud;
  const embedded_file *f = file_at(in[0].i);
  out[0].a = f ? f->path : NULL;
  return f != NULL;
}

static bool vfs_send(trilog_t *t, void *ud, const trilog_value_t *in,
                     trilog_value_t *out) {
  (void)ud, (void)out;
  const embedded_file *f = file_at(in[1].i);
  if (!f)
    return trilog_error(t, "domain_error(vfs_index, %d)", (int)in[1].i);
  return tcp_send(in[0].a, f->data, f->len);
}

typedef struct {
  const char *data;
  size_t len, pos;
  bool used;
} reader_t;

static reader_t readers[4];
static const char *slice_data;
static size_t slice_len;

static const embedded_file *file_named(const char *path) {
  for (int64_t i = 0;; i++) {
    const embedded_file *f = file_at(i);
    if (!f || strcmp(f->path, path) == 0)
      return f;
  }
}

static bool vfs_slice(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)ud, (void)out;
  const embedded_file *f = file_named(in[0].a);
  if (!f || in[1].i < 0 || in[2].i < 0 || (size_t)(in[1].i + in[2].i) > f->len)
    return trilog_error(t, "domain_error(vfs_slice, %s)", in[0].a);
  slice_data = f->data + in[1].i;
  slice_len = (size_t)in[2].i;
  return true;
}

void *vfs_stream_open(const char *path, const char *mode) {
  if (mode[0] != 'r')
    return NULL;
  const char *data;
  size_t len;
  if (strcmp(path, "vfs:slice") == 0 && slice_data) {
    data = slice_data;
    len = slice_len;
    slice_data = NULL;
  } else {
    const embedded_file *f = file_named(path);
    if (!f)
      return NULL;
    data = f->data;
    len = f->len;
  }
  for (int i = 0; i < 4; i++)
    if (!readers[i].used) {
      readers[i] = (reader_t){data, len, 0, true};
      return &readers[i];
    }
  return NULL;
}

bool vfs_stream(void *h) {
  return h >= (void *)readers && h < (void *)(readers + 4);
}

long vfs_stream_read(void *h, char *buf, size_t n) {
  reader_t *r = h;
  size_t k = r->len - r->pos < n ? r->len - r->pos : n;
  memcpy(buf, r->data + r->pos, k);
  r->pos += k;
  return (long)k;
}

void vfs_stream_close(void *h) { ((reader_t *)h)->used = false; }

void vfs_register(trilog_t *t) {
  trilog_register(t, "vfs_file", "i>a", vfs_file, NULL);
  trilog_register(t, "vfs_send", "ai", vfs_send, NULL);
  trilog_register(t, "vfs_slice", "aii", vfs_slice, NULL);
}

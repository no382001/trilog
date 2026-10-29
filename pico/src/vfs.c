#include "vfs.h"
#include "../src/kernel/embedded.h"
#include "tcp.h"
#include <string.h>

extern const char server_pl[];

static const embedded_file *file_at(int64_t i) {
  int64_t n = 0;
  while (embedded_files[n].path)
    n++;
  if (i < 0 || i > n)
    return NULL;
  if (i < n)
    return &embedded_files[i];
  static embedded_file server;
  server = (embedded_file){"pico/prolog/server.pl", server_pl, strlen(server_pl)};
  return &server;
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

void vfs_register(trilog_t *t) {
  trilog_register(t, "vfs_file", "i>a", vfs_file, NULL);
  trilog_register(t, "vfs_send", "ai", vfs_send, NULL);
}

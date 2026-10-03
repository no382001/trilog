#include "streams.h"
#include "ctx.h"
#include "io.h"
#include <stddef.h>

int stream_open(trilog_t *T, const char *path, const char *mode) {
  void *h = io_file_open(T, path, mode);
  if (!h)
    return -1;
  for (int i = 0; i < MAX_OPEN_STREAMS; i++) {
    if (!T->open_streams[i]) {
      T->open_streams[i] = h;
      return i;
    }
  }
  io_file_close(T, h);
  return -1;
}

void stream_close(trilog_t *T, int id) {
  if (id < 0 || id >= MAX_OPEN_STREAMS || !T->open_streams[id])
    return;
  io_file_close(T, T->open_streams[id]);
  T->open_streams[id] = NULL;
}

void *stream_handle(trilog_t *T, int id) {
  if (id < 0 || id >= MAX_OPEN_STREAMS)
    return NULL;
  return T->open_streams[id];
}

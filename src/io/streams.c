#include "streams.h"
#include "ctx.h"
#include "io.h"
#include <stddef.h>

int stream_open(trilog_t *T, const char *path, const char *mode) {
  void *h = io_file_open(T, path, mode);
  if (!h)
    return -1;
  for (int i = 0; i < MAX_OPEN_STREAMS; i++) {
    if (!T->streams[i].handle) {
      T->streams[i] = (io_reader_t){.handle = h};
      return i;
    }
  }
  io_file_close(T, h);
  return -1;
}

void stream_close(trilog_t *T, int id) {
  if (id < 0 || id >= MAX_OPEN_STREAMS || !T->streams[id].handle)
    return;
  io_file_close(T, T->streams[id].handle);
  T->streams[id].handle = NULL;
}

void *stream_handle(trilog_t *T, int id) {
  if (id < 0 || id >= MAX_OPEN_STREAMS)
    return NULL;
  return T->streams[id].handle;
}

char *stream_read_line(trilog_t *T, int id, char *buf, int size) {
  if (!stream_handle(T, id))
    return NULL;
  return io_reader_line(T, &T->streams[id], buf, size);
}

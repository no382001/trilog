#include "streams.h"
#include "io.h"
#include <stddef.h>

static void *open_streams[MAX_OPEN_STREAMS];

int stream_open(const char *path, const char *mode) {
  void *h = io_file_open(path, mode);
  if (!h)
    return -1;
  for (int i = 0; i < MAX_OPEN_STREAMS; i++) {
    if (!open_streams[i]) {
      open_streams[i] = h;
      return i;
    }
  }
  io_file_close(h);
  return -1;
}

void stream_close(int id) {
  if (id < 0 || id >= MAX_OPEN_STREAMS || !open_streams[id])
    return;
  io_file_close(open_streams[id]);
  open_streams[id] = NULL;
}

void *stream_handle(int id) {
  if (id < 0 || id >= MAX_OPEN_STREAMS)
    return NULL;
  return open_streams[id];
}

#include "streams.h"
#include "ctx.h"
#include "io.h"
#include "mem.h"
#include <stddef.h>

int stream_open(trilog_t *T, const char *path, const char *mode) {
  int i = 0;
  while (i < MAX_OPEN_STREAMS && T->streams[i])
    i++;
  if (i == MAX_OPEN_STREAMS)
    return -1;
  io_reader_t *r = mem_grow_n(T, NULL, 1, sizeof *r);
  void *h = io_file_open(T, path, mode);
  if (!h) {
    mem_free(T, r);
    return -1;
  }
  *r = (io_reader_t){.handle = h, .output = mode[0] != 'r'};
  T->streams[i] = r;
  return i;
}

void stream_close(trilog_t *T, int id) {
  if (id < 0 || id >= MAX_OPEN_STREAMS || !T->streams[id])
    return;
  io_file_close(T, T->streams[id]->handle);
  mem_free(T, T->streams[id]);
  T->streams[id] = NULL;
}

void *stream_handle(trilog_t *T, int id) {
  if (id < 0 || id >= MAX_OPEN_STREAMS || !T->streams[id])
    return NULL;
  return T->streams[id]->handle;
}

char *stream_read_line(trilog_t *T, int id, char *buf, int size) {
  if (!stream_handle(T, id))
    return NULL;
  return io_reader_line(T, T->streams[id], buf, size);
}

int stream_byte(trilog_t *T, int id, bool peek) {
  if (!stream_handle(T, id))
    return -2;
  if (T->streams[id]->output)
    return -3;
  return io_reader_byte(T, T->streams[id], peek);
}

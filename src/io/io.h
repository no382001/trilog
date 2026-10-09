#pragma once
#include "trilog.h"
#include <stdbool.h>
#include <stddef.h>

typedef struct {
  void *handle;
  size_t pos, len;
  char buf[512];
} io_reader_t;

bool io_set(trilog_t *T, const trilog_io_t *io);

void io_write_str(trilog_t *T, const char *str);
void io_write_err(trilog_t *T, const char *str);
void io_flush(trilog_t *T);
int io_read_char(trilog_t *T);
char *io_read_line(trilog_t *T, char *buf, int size);
void *io_file_open(trilog_t *T, const char *path, const char *mode);
// The current directory of the file system the I/O hooks open from; false
// for embedder hooks, whose paths are taken as given.
bool io_cwd(trilog_t *T, char *buf, size_t cap);
void io_file_close(trilog_t *T, void *handle);
bool io_file_write(trilog_t *T, void *handle, const char *str);
long io_file_read(trilog_t *T, void *handle, char *buf, size_t n);
char *io_reader_line(trilog_t *T, io_reader_t *r, char *buf, int size);

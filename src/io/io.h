#pragma once
#include "trilog.h"
#include <stdbool.h>

void io_set(trilog_t *T, const trilog_io_t *io);

void io_write_str(trilog_t *T, const char *str);
void io_write_err(trilog_t *T, const char *str);
void io_flush(trilog_t *T);
int io_read_char(trilog_t *T);
char *io_read_line(trilog_t *T, char *buf, int size);
void *io_file_open(trilog_t *T, const char *path, const char *mode);
void io_file_close(trilog_t *T, void *handle);
char *io_file_read_line(trilog_t *T, void *handle, char *buf, int size);
bool io_file_write(trilog_t *T, void *handle, const char *str);
bool io_file_exists(trilog_t *T, const char *path);
long long io_file_mtime(trilog_t *T, const char *path);

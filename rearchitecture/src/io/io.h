#pragma once
#include "trilog.h"
#include <stdbool.h>

typedef struct {
  void (*write_str)(const char *str, void *ud);
  void (*write_err)(const char *str, void *ud);
  void (*flush)(void *ud);
  int (*read_char)(void *ud);
  char *(*read_line)(char *buf, int size, void *ud);
  void *(*file_open)(const char *path, const char *mode, void *ud);
  void (*file_close)(void *handle, void *ud);
  char *(*file_read_line)(void *handle, char *buf, int size, void *ud);
  bool (*file_write)(void *handle, const char *str, void *ud);
  bool (*file_exists)(const char *path, void *ud);
  long long (*file_mtime)(const char *path, void *ud);
  void *userdata;
} io_hooks_t;

void io_hooks_init_default(trilog_t *T);

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

#pragma once
#include "trilog.h"
#include <stdbool.h>

#define MAX_OPEN_STREAMS 16

// A stream id, -1 if the file cannot be opened, -2 if every stream is in use.
int stream_open(trilog_t *T, const char *path, const char *mode);
void stream_close(trilog_t *T, int id);
void *stream_handle(trilog_t *T, int id);
char *stream_read_line(trilog_t *T, int id, char *buf, int size);
int stream_byte(trilog_t *T, int id, bool peek);

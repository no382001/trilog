#pragma once
#include "trilog.h"

#define MAX_OPEN_STREAMS 16

int stream_open(trilog_t *T, const char *path, const char *mode);
void stream_close(trilog_t *T, int id);
void *stream_handle(trilog_t *T, int id);

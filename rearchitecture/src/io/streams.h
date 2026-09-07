#pragma once

#define MAX_OPEN_STREAMS 16

int stream_open(const char *path, const char *mode);
void stream_close(int id);
void *stream_handle(int id);

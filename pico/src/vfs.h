#pragma once
#include "trilog.h"

void vfs_register(trilog_t *t);

// Read streams on the files in flash: a file by its path, or "vfs:slice" for
// the part of one the last vfs_slice/3 named.
void *vfs_stream_open(const char *path, const char *mode);
bool vfs_stream(void *h);
long vfs_stream_read(void *h, char *buf, size_t n);
void vfs_stream_close(void *h);

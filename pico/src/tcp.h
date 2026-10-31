#pragma once
#include "trilog.h"

// tcp_listen(+Port) and tcp_accept(-Path); open(Path, read|write, S) gives
// streams on the accepted connection which ends when both are closed.
void tcp_register(trilog_t *t);

// Writes all of buf to the connection a tcp_accept/1 path names.
bool tcp_send(const char *path, const char *buf, size_t n);

// Stream hooks for a tcp:N path; tcp_stream_open returns NULL for anything
// else.
void *tcp_stream_open(const char *path);
long tcp_stream_read(void *h, char *buf, size_t n);
long tcp_stream_write(void *h, const char *buf, size_t n);
void tcp_stream_close(void *h);

void tcp_fail_all(const char *reason);
void tcp_drop_all(void);

unsigned tcp_accept_count(void);

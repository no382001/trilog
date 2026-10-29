#pragma once
#include "trilog.h"

// tcp_listen(+Port) and tcp_accept(-Path); open(Path, read|write, S) gives
// streams on the accepted connection which ends when both are closed.
void tcp_register(trilog_t *t);

// Writes all of buf to the connection a tcp_accept/1 path names.
bool tcp_send(const char *path, const char *buf, size_t n);

// stdio for the user streams, plus the tcp:N paths tcp_accept returns.
extern const trilog_io_t tcp_io;

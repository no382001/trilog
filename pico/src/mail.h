#pragma once
#include "trilog.h"
#include <stdbool.h>
#include <stddef.h>

void mail_register(trilog_t *t);

void *mail_stream_open(const char *path);
bool mail_stream(void *h);
long mail_stream_write(void *h, const char *buf, size_t n);

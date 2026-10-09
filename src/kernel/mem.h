#pragma once
#include "trilog.h"
#include <stddef.h>

void *mem_realloc(trilog_t *T, void *p, size_t n);
void *mem_grow_n(trilog_t *T, void *p, size_t count, size_t size);
void mem_free(trilog_t *T, void *p);
// Grows *buf to hold at least need bytes, doubling; *cap tracks its size.
void mem_reserve(trilog_t *T, void **buf, size_t *cap, size_t need);
_Noreturn void mem_fail(trilog_t *T);
_Noreturn void engine_halt(trilog_t *T, int code);
_Noreturn void engine_abort(trilog_t *T);

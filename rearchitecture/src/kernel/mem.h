#pragma once
#include "trilog.h"
#include <stddef.h>

void *mem_realloc(trilog_t *T, void *p, size_t n);
void *mem_grow_n(trilog_t *T, void *p, size_t count, size_t size);
void mem_free(trilog_t *T, void *p);
_Noreturn void mem_fail(trilog_t *T);
_Noreturn void engine_halt(trilog_t *T, int code);

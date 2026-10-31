#pragma once
#include "trilog.h"
#include <stddef.h>

struct chunk;

// Chunked bump allocator: backing pool must never move on growth,
// since clause templates point directly at each other.
void *arena_alloc(trilog_t *T, size_t n);
void arena_free(trilog_t *T);
size_t arena_bytes(trilog_t *T);
char *arena_strdup(trilog_t *T, const char *s);
void arena_temp_reset(trilog_t *T);
void arena_free_chunks(trilog_t *T, struct chunk *c);

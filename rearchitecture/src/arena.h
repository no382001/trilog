#pragma once
#include <stddef.h>

// Chunked bump allocator: backing pool must never move on growth,
// since clause templates point directly at each other.
void *arena_alloc(size_t n);
char *arena_strdup(const char *s);

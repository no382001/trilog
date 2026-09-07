#define _POSIX_C_SOURCE 200809L
#include "arena.h"
#include <stdlib.h>
#include <string.h>

#define CHUNK_SIZE (1 << 20)

typedef struct chunk {
    struct chunk *next;
    size_t used, cap;
    char data[];
} chunk_t;

static chunk_t *current = NULL;

static chunk_t *new_chunk(size_t at_least) {
    size_t cap = at_least > CHUNK_SIZE ? at_least : CHUNK_SIZE;
    chunk_t *c = malloc(sizeof(chunk_t) + cap);
    c->next = current;
    c->used = 0;
    c->cap = cap;
    return c;
}

void *arena_alloc(size_t n) {
    n = (n + 7u) & ~(size_t)7u; // align to 8 bytes for mixed-size allocations
    if (!current || current->used + n > current->cap) current = new_chunk(n);
    void *p = current->data + current->used;
    current->used += n;
    return p;
}

char *arena_strdup(const char *s) {
    size_t n = strlen(s) + 1;
    char *p = arena_alloc(n);
    memcpy(p, s, n);
    return p;
}

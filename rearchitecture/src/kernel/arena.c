#include "arena.h"
#include "ctx.h"
#include "io.h"
#include "mem.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define CHUNK_SIZE (1 << 20)

typedef struct chunk {
  struct chunk *next;
  size_t used, cap;
  char data[];
} chunk_t;

static chunk_t *new_chunk(trilog_t *T, size_t at_least) {
  size_t cap = at_least > CHUNK_SIZE ? at_least : CHUNK_SIZE;
  if (cap > SIZE_MAX - sizeof(chunk_t))
    mem_fail(T);
  chunk_t *c = mem_grow_n(T, NULL, 1, sizeof(chunk_t) + cap);
  c->next = T->arena_current;
  c->used = 0;
  c->cap = cap;
  return c;
}

void *arena_alloc(trilog_t *T, size_t n) {
  n = (n + 7u) & ~(size_t)7u; // align to 8 bytes for mixed-size allocations
  if (!T->arena_current || T->arena_current->used + n > T->arena_current->cap)
    T->arena_current = new_chunk(T, n);
  void *p = T->arena_current->data + T->arena_current->used;
  T->arena_current->used += n;
  return p;
}

char *arena_strdup(trilog_t *T, const char *s) {
  size_t n = strlen(s) + 1;
  char *p = arena_alloc(T, n);
  memcpy(p, s, n);
  return p;
}

size_t arena_bytes(trilog_t *T) {
  size_t n = 0;
  for (chunk_t *c = T->arena_current; c; c = c->next)
    n += c->cap;
  return n;
}

void arena_free(trilog_t *T) {
  while (T->arena_current) {
    chunk_t *next = T->arena_current->next;
    mem_free(T, T->arena_current);
    T->arena_current = next;
  }
}

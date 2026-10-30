#include "arena.h"
#include "ctx.h"
#include "io.h"
#include "mem.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifndef ARENA_CHUNK_SIZE
#define ARENA_CHUNK_SIZE (1 << 20)
#endif

typedef struct chunk {
  struct chunk *next;
  size_t used, cap;
  char data[];
} chunk_t;

static chunk_t *new_chunk(trilog_t *T, chunk_t *next, size_t at_least) {
  size_t cap = at_least > ARENA_CHUNK_SIZE ? at_least : ARENA_CHUNK_SIZE;
  if (cap > SIZE_MAX - sizeof(chunk_t))
    mem_fail(T);
  chunk_t *c = mem_grow_n(T, NULL, 1, sizeof(chunk_t) + cap);
  c->next = next;
  c->used = 0;
  c->cap = cap;
  return c;
}

static void *alloc_in(trilog_t *T, chunk_t **head, size_t n) {
  n = (n + 7u) & ~(size_t)7u; // align to 8 bytes for mixed-size allocations
  if (!*head || (*head)->used + n > (*head)->cap)
    *head = new_chunk(T, *head, n);
  void *p = (*head)->data + (*head)->used;
  (*head)->used += n;
  return p;
}

void *arena_alloc(trilog_t *T, size_t n) {
  return alloc_in(T, T->arena_use_temp ? &T->arena_temp : &T->arena_current, n);
}

// Atom names outlive any one parse, so they never go to the scratch arena.
char *arena_strdup(trilog_t *T, const char *s) {
  size_t n = strlen(s) + 1;
  char *p = alloc_in(T, &T->arena_current, n);
  memcpy(p, s, n);
  return p;
}

static size_t chunk_bytes(chunk_t *c) {
  size_t n = 0;
  for (; c; c = c->next)
    n += c->cap;
  return n;
}

size_t arena_bytes(trilog_t *T) {
  return chunk_bytes(T->arena_current) + chunk_bytes(T->arena_temp);
}

static void free_chunks(trilog_t *T, chunk_t *c) {
  while (c) {
    chunk_t *next = c->next;
    mem_free(T, c);
    c = next;
  }
}

void arena_temp_reset(trilog_t *T) {
  if (!T->arena_temp)
    return;
  free_chunks(T, T->arena_temp->next);
  T->arena_temp->next = NULL;
  T->arena_temp->used = 0;
}

void arena_free(trilog_t *T) {
  free_chunks(T, T->arena_current);
  free_chunks(T, T->arena_temp);
  T->arena_current = T->arena_temp = NULL;
}

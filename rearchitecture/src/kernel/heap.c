#include "heap.h"
#include "arena.h"
#include "atoms.h"
#include "ctx.h"
#include "io.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

static void *heap_realloc_or_die(trilog_t *T, void *p, size_t n) {
  void *r = realloc(p, n);
  if (!r && n != 0) {
    io_write_err(T, "out of memory\n");
    exit(1);
  }
  return r;
}

void heap_init(trilog_t *T) {
  T->heap_cap = 1024;
  T->heap = heap_realloc_or_die(T, NULL, T->heap_cap * sizeof(cell_t));
  T->heap_top = 0;

  T->trail_cap = 256;
  T->trail = heap_realloc_or_die(T, NULL, T->trail_cap * sizeof(size_t));
  T->trail_top = 0;

  T->atom_cap = 64;
  T->atoms = heap_realloc_or_die(T, NULL, T->atom_cap * sizeof(char *));
  T->atom_count = 0;
#define X(name, text) atom_intern(T, text);
  WELL_KNOWN_ATOMS(X)
#undef X
  assert(T->atom_count == WELL_KNOWN_ATOM_COUNT);
}

size_t heap_alloc(trilog_t *T, size_t n) {
  if (T->heap_top + n > T->heap_cap) {
    while (T->heap_top + n > T->heap_cap)
      T->heap_cap *= 2;
    T->heap = heap_realloc_or_die(T, T->heap, T->heap_cap * sizeof(cell_t));
  }
  size_t base = T->heap_top;
  T->heap_top += n;
  if (T->heap_top > T->heap_peak)
    T->heap_peak = T->heap_top;
  return base;
}

// high-water mark in cells, independent of heap_top (which drops on
// backtracking and GC compaction).
size_t heap_peak_size(trilog_t *T) { return T->heap_peak; }

size_t heap_new_var(trilog_t *T) {
  size_t i = heap_alloc(T, 1);
  T->heap[i].tag = TAG_REF;
  T->heap[i].as.ref = i;
  return i;
}

size_t heap_new_atom(trilog_t *T, int32_t atom_id) {
  size_t i = heap_alloc(T, 1);
  T->heap[i].tag = TAG_ATOM;
  T->heap[i].as.atom_id = atom_id;
  return i;
}

size_t heap_new_int(trilog_t *T, int64_t v) {
  size_t i = heap_alloc(T, 1);
  T->heap[i].tag = TAG_INT;
  T->heap[i].as.ival = v;
  return i;
}

size_t heap_new_flt(trilog_t *T, double v) {
  size_t i = heap_alloc(T, 1);
  T->heap[i].tag = TAG_FLT;
  T->heap[i].as.fval = v;
  return i;
}

size_t heap_new_struct(trilog_t *T, int32_t functor_id, int32_t arity,
                       size_t *arg_idx) {
  size_t base = heap_alloc(T, (size_t)(1 + arity));
  T->heap[base].tag = TAG_FUNCTOR;
  T->heap[base].as.func.atom_id = functor_id;
  T->heap[base].as.func.arity = arity;
  for (int32_t i = 0; i < arity; i++) {
    T->heap[base + 1 + i].tag = TAG_REF;
    T->heap[base + 1 + i].as.ref = arg_idx[i];
  }
  size_t str = heap_alloc(T, 1);
  T->heap[str].tag = TAG_STR;
  T->heap[str].as.ptr = base;
  return str;
}

size_t heap_deref(trilog_t *T, size_t r) {
  while (T->heap[r].tag == TAG_REF && T->heap[r].as.ref != r)
    r = T->heap[r].as.ref;
  return r;
}

size_t heap_mark(trilog_t *T) { return T->heap_top; }
void heap_release(trilog_t *T, size_t mark) { T->heap_top = mark; }

void heap_bind(trilog_t *T, size_t var, size_t target) {
  T->heap[var].as.ref = target;
  if (T->trail_top >= T->trail_cap) {
    T->trail_cap *= 2;
    T->trail = heap_realloc_or_die(T, T->trail, T->trail_cap * sizeof(size_t));
  }
  T->trail[T->trail_top++] = var;
}

size_t trail_mark(trilog_t *T) { return T->trail_top; }

void trail_release(trilog_t *T, size_t mark) {
  while (T->trail_top > mark) {
    size_t v = T->trail[--T->trail_top];
    T->heap[v].as.ref = v;
  }
}

int32_t atom_intern(trilog_t *T, const char *name) {
  for (int32_t i = 0; i < T->atom_count; i++)
    if (strcmp(T->atoms[i], name) == 0)
      return i;
  if (T->atom_count >= T->atom_cap) {
    T->atom_cap *= 2;
    T->atoms = heap_realloc_or_die(T, T->atoms, T->atom_cap * sizeof(char *));
  }
  T->atoms[T->atom_count] = arena_strdup(T, name);
  return T->atom_count++;
}

const char *atom_name(trilog_t *T, int32_t atom_id) {
  return T->atoms[atom_id];
}

size_t heap_size(trilog_t *T) { return T->heap_top; }
void heap_set_size(trilog_t *T, size_t n) { T->heap_top = n; }
size_t *trail_array(trilog_t *T) { return T->trail; }
size_t trail_size(trilog_t *T) { return T->trail_top; }
void trail_set_size(trilog_t *T, size_t n) { T->trail_top = n; }

void heap_set_capacity(trilog_t *T, size_t n) {
  if (n < T->heap_top)
    n = T->heap_top; // never shrink below live data
  if (n < 64)
    n = 64;
  if (n == T->heap_cap)
    return;
  T->heap_cap = n;
  T->heap = heap_realloc_or_die(T, T->heap, T->heap_cap * sizeof(cell_t));
}

size_t heap_capacity(trilog_t *T) { return T->heap_cap; }

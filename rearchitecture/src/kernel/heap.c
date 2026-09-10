#define _POSIX_C_SOURCE 200809L
#include "heap.h"
#include "arena.h"
#include "io.h"
#include <stdlib.h>
#include <string.h>

// A failed realloc used to go unchecked, corrupting on the NULL it
// produced instead of reporting the OOM.
static void *heap_realloc_or_die(void *p, size_t n) {
  void *r = realloc(p, n);
  if (!r && n != 0) {
    io_write_err("out of memory\n");
    exit(1);
  }
  return r;
}

cell_t *heap = NULL;
static size_t heap_cap = 0, heap_top = 0;

static size_t *trail = NULL;
static size_t trail_cap = 0, trail_top = 0;

static char **atoms = NULL;
static int32_t atom_count = 0, atom_cap = 0;

void heap_init(void) {
  heap_cap = 1024;
  heap = malloc(heap_cap * sizeof(cell_t));
  heap_top = 0;

  trail_cap = 256;
  trail = malloc(trail_cap * sizeof(size_t));
  trail_top = 0;

  atom_cap = 64;
  atoms = malloc(atom_cap * sizeof(char *));
  atom_count = 0;
}

size_t heap_alloc(size_t n) {
  if (heap_top + n > heap_cap) {
    while (heap_top + n > heap_cap)
      heap_cap *= 2;
    heap = heap_realloc_or_die(heap, heap_cap * sizeof(cell_t));
  }
  size_t base = heap_top;
  heap_top += n;
  return base;
}

size_t heap_new_var(void) {
  size_t i = heap_alloc(1);
  heap[i].tag = TAG_REF;
  heap[i].as.ref = i;
  return i;
}

size_t heap_new_atom(int32_t atom_id) {
  size_t i = heap_alloc(1);
  heap[i].tag = TAG_ATOM;
  heap[i].as.atom_id = atom_id;
  return i;
}

size_t heap_new_int(int64_t v) {
  size_t i = heap_alloc(1);
  heap[i].tag = TAG_INT;
  heap[i].as.ival = v;
  return i;
}

size_t heap_new_flt(double v) {
  size_t i = heap_alloc(1);
  heap[i].tag = TAG_FLT;
  heap[i].as.fval = v;
  return i;
}

size_t heap_new_struct(int32_t functor_id, int32_t arity, size_t *arg_idx) {
  size_t base = heap_alloc((size_t)(1 + arity));
  heap[base].tag = TAG_FUNCTOR;
  heap[base].as.func.atom_id = functor_id;
  heap[base].as.func.arity = arity;
  for (int32_t i = 0; i < arity; i++) {
    heap[base + 1 + i].tag = TAG_REF;
    heap[base + 1 + i].as.ref = arg_idx[i];
  }
  size_t str = heap_alloc(1);
  heap[str].tag = TAG_STR;
  heap[str].as.ptr = base;
  return str;
}

size_t heap_deref(size_t r) {
  while (heap[r].tag == TAG_REF && heap[r].as.ref != r)
    r = heap[r].as.ref;
  return r;
}

size_t heap_mark(void) { return heap_top; }
void heap_release(size_t mark) { heap_top = mark; }

void heap_bind(size_t var, size_t target) {
  heap[var].as.ref = target;
  if (trail_top >= trail_cap) {
    trail_cap *= 2;
    trail = heap_realloc_or_die(trail, trail_cap * sizeof(size_t));
  }
  trail[trail_top++] = var;
}

size_t trail_mark(void) { return trail_top; }

void trail_release(size_t mark) {
  while (trail_top > mark) {
    size_t v = trail[--trail_top];
    heap[v].as.ref = v;
  }
}

int32_t atom_intern(const char *name) {
  for (int32_t i = 0; i < atom_count; i++)
    if (strcmp(atoms[i], name) == 0)
      return i;
  if (atom_count >= atom_cap) {
    atom_cap *= 2;
    atoms = heap_realloc_or_die(atoms, atom_cap * sizeof(char *));
  }
  atoms[atom_count] = arena_strdup(name);
  return atom_count++;
}

const char *atom_name(int32_t atom_id) { return atoms[atom_id]; }

size_t heap_size(void) { return heap_top; }
void heap_set_size(size_t n) { heap_top = n; }
size_t *trail_array(void) { return trail; }
size_t trail_size(void) { return trail_top; }
void trail_set_size(size_t n) { trail_top = n; }

void heap_set_capacity(size_t n) {
  if (n < heap_top)
    n = heap_top; // never shrink below live data
  if (n < 64)
    n = 64;
  if (n == heap_cap)
    return;
  heap_cap = n;
  heap = heap_realloc_or_die(heap, heap_cap * sizeof(cell_t));
}

size_t heap_capacity(void) { return heap_cap; }

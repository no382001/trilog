#include "heap.h"
#include "arena.h"
#include "atoms.h"
#include "ctx.h"
#include "io.h"
#include "mem.h"
#include <stdlib.h>
#include <string.h>

void heap_init(trilog_t *T) {
  T->heap = mem_grow_n(T, NULL, 1024, sizeof(cell_t));
  T->heap_cap = 1024;
  T->heap_top = 0;

  T->trail = mem_grow_n(T, NULL, 256, sizeof(size_t));
  T->trail_cap = 256;
  T->trail_top = 0;

  T->atoms = mem_grow_n(T, NULL, 64, sizeof(char *));
  T->atom_cap = 64;
  T->atom_count = 0;
#define X(name, text) atom_intern(T, text);
  WELL_KNOWN_ATOMS(X)
#undef X
  if (T->atom_count != WELL_KNOWN_ATOM_COUNT)
    engine_fatal(T, "duplicate well-known atom\n");
}

void heap_grow(trilog_t *T, size_t n) {
  size_t cap = T->heap_cap;
  while (T->heap_top + n > cap)
    cap = mem_grow_by(T, cap, T->heap_grow_percent);
  T->heap = mem_grow_n(T, T->heap, cap, sizeof(cell_t));
  T->heap_cap = cap;
}

// high-water mark in cells, independent of heap_top (which drops on
// backtracking and GC compaction).
size_t heap_peak_size(trilog_t *T) { return T->heap_peak; }

size_t heap_mark(trilog_t *T) { return T->heap_top; }
void heap_release(trilog_t *T, size_t mark) {
  T->heap_top = mark;
  if (mark < T->gc_old_top)
    T->gc_old_top = mark;
}

void heap_bind(trilog_t *T, size_t var, size_t target) {
  T->heap[var].as.ref = target;
  if (T->trail_top >= T->trail_cap) {
    T->trail = mem_grow_n(T, T->trail, T->trail_cap * 2, sizeof(size_t));
    T->trail_cap *= 2;
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

static uint32_t atom_hash(const char *s) {
  uint32_t h = 2166136261u;
  for (; *s; s++)
    h = (h ^ (unsigned char)*s) * 16777619u;
  return h;
}

static uint32_t atom_slot(trilog_t *T, const char *name) {
  uint32_t mask = T->atom_slots_cap - 1;
  uint32_t i = atom_hash(name) & mask;
  while (T->atom_slots[i] >= 0 && strcmp(T->atoms[T->atom_slots[i]], name))
    i = (i + 1) & mask;
  return i;
}

static void atom_slots_grow(trilog_t *T) {
  uint32_t cap = T->atom_slots_cap ? T->atom_slots_cap * 2 : 256;
  atom_slot_t *slots = mem_grow_n(T, NULL, cap, sizeof *slots);
  for (uint32_t i = 0; i < cap; i++)
    slots[i] = -1;
  mem_free(T, T->atom_slots);
  T->atom_slots = slots;
  T->atom_slots_cap = cap;
  for (int32_t id = 0; id < T->atom_count; id++)
    T->atom_slots[atom_slot(T, T->atoms[id])] = (atom_slot_t)id;
}

static int32_t atom_add(trilog_t *T, const char *name, bool copy) {
  if ((uint32_t)(T->atom_count + 1) * 2 > T->atom_slots_cap)
    atom_slots_grow(T);
  uint32_t slot = atom_slot(T, name);
  if (T->atom_slots[slot] >= 0)
    return T->atom_slots[slot];
  if (T->atom_count >= ATOM_SLOT_MAX)
    mem_fail(T);
  if (T->atom_count >= T->atom_cap) {
    T->atoms = mem_grow_n(T, T->atoms, (size_t)T->atom_cap * 2, sizeof(char *));
    T->atom_cap *= 2;
  }
  T->atoms[T->atom_count] = copy ? arena_strdup(T, name) : (char *)name;
  T->atom_slots[slot] = (atom_slot_t)T->atom_count;
  return T->atom_count++;
}

int32_t atom_find(trilog_t *T, const char *name) {
  return T->atom_slots_cap ? T->atom_slots[atom_slot(T, name)] : -1;
}

int32_t atom_intern(trilog_t *T, const char *name) {
  return atom_add(T, name, true);
}

int32_t atom_intern_static(trilog_t *T, const char *name) {
  return atom_add(T, name, false);
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
  cell_t *resized = mem_realloc(T, T->heap, n * sizeof(cell_t));
  if (!resized)
    return;
  T->heap = resized;
  T->heap_cap = n;
}

size_t heap_capacity(trilog_t *T) { return T->heap_cap; }

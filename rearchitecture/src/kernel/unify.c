#include "unify.h"
#include "heap.h"
#include "io.h"
#include <stdint.h>
#include <stdlib.h>

#define PAIR_VISITS_THRESHOLD 4096

void pair_visits_reset(pair_visits *v) {
  v->steps = 0;
  if (v->len == 0)
    return;
  for (size_t i = 0; i < v->cap; i++)
    v->a[i] = SIZE_MAX;
  v->len = 0;
}

static size_t pair_slot(size_t fa, size_t fb, size_t cap) {
  uint64_t h =
      (uint64_t)fa * 0x9E3779B97F4A7C15u ^ (uint64_t)fb * 0xC2B2AE3D27D4EB4Fu;
  return (size_t)(h ^ (h >> 32)) & (cap - 1);
}

static void pair_visits_grow(pair_visits *v) {
  size_t cap = v->cap ? v->cap * 2 : 1024;
  size_t *na = malloc(cap * sizeof *na), *nb = malloc(cap * sizeof *nb);
  if (!na || !nb) {
    io_write_err("out of memory\n");
    exit(1);
  }
  for (size_t i = 0; i < cap; i++)
    na[i] = SIZE_MAX;
  for (size_t i = 0; i < v->cap; i++) {
    if (v->a[i] == SIZE_MAX)
      continue;
    size_t j = pair_slot(v->a[i], v->b[i], cap);
    while (na[j] != SIZE_MAX)
      j = (j + 1) & (cap - 1);
    na[j] = v->a[i];
    nb[j] = v->b[i];
  }
  free(v->a);
  free(v->b);
  v->a = na;
  v->b = nb;
  v->cap = cap;
}

int pair_visits_seen(pair_visits *v, size_t fa, size_t fb) {
  if (++v->steps <= PAIR_VISITS_THRESHOLD)
    return 0;
  if (2 * (v->len + 1) > v->cap)
    pair_visits_grow(v);
  size_t i = pair_slot(fa, fb, v->cap);
  for (; v->a[i] != SIZE_MAX; i = (i + 1) & (v->cap - 1))
    if (v->a[i] == fa && v->b[i] == fb)
      return 1;
  v->a[i] = fa;
  v->b[i] = fb;
  v->len++;
  return 0;
}

static pair_visits unify_visits, occurs_check_visits;

static size_t *occurs_marks = NULL;
static size_t occurs_len = 0, occurs_cap = 0;

static void occurs_mark(size_t f) {
  if (occurs_len == occurs_cap) {
    size_t cap = occurs_cap ? occurs_cap * 2 : 64;
    size_t *grown = realloc(occurs_marks, cap * sizeof *grown);
    if (!grown) {
      io_write_err("out of memory\n");
      exit(1);
    }
    occurs_marks = grown;
    occurs_cap = cap;
  }
  heap[f].as.func.arity = -1 - heap[f].as.func.arity;
  occurs_marks[occurs_len++] = f;
}

// Same arity-flip path marking as heap_to_template, so a cyclic t terminates.
static int occurs(size_t v, size_t t) {
  size_t base = occurs_len;
  int found = 0;
  for (;;) {
    t = heap_deref(t);
    if (t == v) {
      found = 1;
      break;
    }
    if (heap[t].tag != TAG_STR)
      break;
    size_t f = heap[t].as.ptr;
    int32_t arity = heap[f].as.func.arity;
    if (arity < 0)
      break; // already on the path: a cycle
    occurs_mark(f);
    for (int32_t i = 0; i < arity - 1 && !found; i++)
      found = occurs(v, f + 1 + (size_t)i);
    if (found)
      break;
    t = f + (size_t)arity;
  }
  while (occurs_len > base) {
    size_t f = occurs_marks[--occurs_len];
    heap[f].as.func.arity = -1 - heap[f].as.func.arity;
  }
  return found;
}

static int unify_oc_rec(size_t a, size_t b) {
  for (;;) {
    a = heap_deref(a);
    b = heap_deref(b);
    if (a == b)
      return 1;
    if (heap[a].tag == TAG_REF) {
      if (occurs(a, b))
        return 0;
      heap_bind(a, b);
      return 1;
    }
    if (heap[b].tag == TAG_REF) {
      if (occurs(b, a))
        return 0;
      heap_bind(b, a);
      return 1;
    }
    if (heap[a].tag != TAG_STR || heap[b].tag != TAG_STR)
      return unify(a, b);
    size_t fa = heap[a].as.ptr, fb = heap[b].as.ptr;
    int32_t arity = heap[fa].as.func.arity;
    if (heap[fa].as.func.atom_id != heap[fb].as.func.atom_id ||
        arity != heap[fb].as.func.arity)
      return 0;
    if (pair_visits_seen(&occurs_check_visits, fa, fb))
      return 1;
    for (int32_t i = 0; i < arity - 1; i++)
      if (!unify_oc_rec(fa + 1 + (size_t)i, fb + 1 + (size_t)i))
        return 0;
    a = fa + (size_t)arity; // loop on the last argument, as unify() does
    b = fb + (size_t)arity;
  }
}

static int unify_rec(size_t a, size_t b) {
  for (;;) {
    a = heap_deref(a);
    b = heap_deref(b);
    if (a == b)
      return 1;
    if (heap[a].tag == TAG_REF) {
      heap_bind(a, b);
      return 1;
    }
    if (heap[b].tag == TAG_REF) {
      heap_bind(b, a);
      return 1;
    }
    if (heap[a].tag != heap[b].tag)
      return 0;
    switch (heap[a].tag) {
    case TAG_ATOM:
      return heap[a].as.atom_id == heap[b].as.atom_id;
    case TAG_INT:
      return heap[a].as.ival == heap[b].as.ival;
    case TAG_FLT:
      return heap[a].as.fval == heap[b].as.fval;
    case TAG_STR:
      break;
    default:
      return 0; // FUNCTOR cells are never unified directly
    }
    size_t fa = heap[a].as.ptr, fb = heap[b].as.ptr;
    int32_t arity = heap[fa].as.func.arity;
    if (heap[fa].as.func.atom_id != heap[fb].as.func.atom_id ||
        arity != heap[fb].as.func.arity)
      return 0;
    if (pair_visits_seen(&unify_visits, fa, fb))
      return 1;
    for (int32_t i = 0; i < arity - 1; i++)
      if (!unify_rec(fa + 1 + (size_t)i, fb + 1 + (size_t)i))
        return 0;
    a = fa + (size_t)arity;
    b = fb + (size_t)arity;
  }
}

int unify(size_t a, size_t b) {
  pair_visits_reset(&unify_visits);
  return unify_rec(a, b);
}

int unify_with_occurs_check(size_t a, size_t b) {
  pair_visits_reset(&occurs_check_visits);
  return unify_oc_rec(a, b);
}

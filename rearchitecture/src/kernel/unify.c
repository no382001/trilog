#include "unify.h"
#include "heap.h"
#include <stdint.h>

// Same arity-flip path marking as heap_to_template, so a cyclic t terminates.
static int occurs(size_t v, size_t t) {
  t = heap_deref(t);
  if (t == v)
    return 1;
  if (heap[t].tag != TAG_STR)
    return 0;
  size_t f = heap[t].as.ptr;
  int32_t arity = heap[f].as.func.arity;
  if (arity < 0)
    return 0;
  heap[f].as.func.arity = -1 - arity;
  int found = 0;
  for (int32_t i = 0; i < arity && !found; i++)
    found = occurs(v, f + 1 + i);
  heap[f].as.func.arity = arity;
  return found;
}

int unify_with_occurs_check(size_t a, size_t b) {
  a = heap_deref(a);
  b = heap_deref(b);
  if (a == b)
    return 1;

  cell_t *ca = &heap[a], *cb = &heap[b];

  if (ca->tag == TAG_REF) {
    if (occurs(a, b))
      return 0;
    heap_bind(a, b);
    return 1;
  }
  if (cb->tag == TAG_REF) {
    if (occurs(b, a))
      return 0;
    heap_bind(b, a);
    return 1;
  }
  if (ca->tag != TAG_STR || cb->tag != TAG_STR)
    return unify(a, b);
  cell_t *fa = &heap[ca->as.ptr], *fb = &heap[cb->as.ptr];
  if (fa->as.func.atom_id != fb->as.func.atom_id ||
      fa->as.func.arity != fb->as.func.arity)
    return 0;
  for (int32_t i = 0; i < fa->as.func.arity; i++)
    if (!unify_with_occurs_check(ca->as.ptr + 1 + i, cb->as.ptr + 1 + i))
      return 0;
  return 1;
}

int unify(size_t a, size_t b) {
  a = heap_deref(a);
  b = heap_deref(b);
  if (a == b)
    return 1;

  cell_t *ca = &heap[a], *cb = &heap[b];

  if (ca->tag == TAG_REF) {
    heap_bind(a, b);
    return 1;
  }
  if (cb->tag == TAG_REF) {
    heap_bind(b, a);
    return 1;
  }
  if (ca->tag != cb->tag)
    return 0;

  switch (ca->tag) {
  case TAG_ATOM:
    return ca->as.atom_id == cb->as.atom_id;
  case TAG_INT:
    return ca->as.ival == cb->as.ival;
  case TAG_FLT:
    return ca->as.fval == cb->as.fval;
  case TAG_STR: {
    cell_t *fa = &heap[ca->as.ptr], *fb = &heap[cb->as.ptr];
    if (fa->as.func.atom_id != fb->as.func.atom_id)
      return 0;
    if (fa->as.func.arity != fb->as.func.arity)
      return 0;
    for (int32_t i = 0; i < fa->as.func.arity; i++)
      if (!unify(ca->as.ptr + 1 + i, cb->as.ptr + 1 + i))
        return 0;
    return 1;
  }
  default:
    return 0; // FUNCTOR cells are never unified directly
  }
}

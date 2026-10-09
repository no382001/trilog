#include "unify.h"
#include "ctx.h"
#include "heap.h"
#include "io.h"
#include "mem.h"
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

static void pair_visits_grow(trilog_t *T, pair_visits *v) {
  size_t cap = v->cap ? v->cap * 2 : 1024;
  size_t *na = mem_grow_n(T, NULL, cap, sizeof *na);
  size_t *nb = mem_realloc(T, NULL, cap * sizeof *nb);
  if (!nb) {
    mem_free(T, na);
    mem_fail(T);
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
  mem_free(T, v->a);
  mem_free(T, v->b);
  v->a = na;
  v->b = nb;
  v->cap = cap;
}

void pair_visits_free(trilog_t *T, pair_visits *v) {
  mem_free(T, v->a);
  mem_free(T, v->b);
}

int pair_visits_seen(trilog_t *T, pair_visits *v, size_t fa, size_t fb) {
  if (++v->steps <= PAIR_VISITS_THRESHOLD)
    return 0;
  if (2 * (v->len + 1) > v->cap)
    pair_visits_grow(T, v);
  size_t i = pair_slot(fa, fb, v->cap);
  for (; v->a[i] != SIZE_MAX; i = (i + 1) & (v->cap - 1))
    if (v->a[i] == fa && v->b[i] == fb)
      return 1;
  v->a[i] = fa;
  v->b[i] = fb;
  v->len++;
  return 0;
}

static void occurs_mark(trilog_t *T, size_t f) {
  if (T->occurs_len == T->occurs_cap) {
    size_t cap = T->occurs_cap ? T->occurs_cap * 2 : 64;
    T->occurs_marks = mem_grow_n(T, T->occurs_marks, cap, sizeof(size_t));
    T->occurs_cap = cap;
  }
  T->heap[f].as.func.arity = -1 - T->heap[f].as.func.arity;
  T->occurs_marks[T->occurs_len++] = f;
}

// Visited marks: each functor walked once.
static int occurs(trilog_t *T, size_t v, size_t t) {
  size_t base = T->occurs_len, wbase = T->wsp;
  int found = 0;
  for (;;) {
    t = heap_deref(T, t);
    if (t == v) {
      found = 1;
      break;
    }
    if (T->heap[t].tag == TAG_STR) {
      size_t f = T->heap[t].as.ptr;
      int32_t arity = T->heap[f].as.func.arity;
      if (arity > 0) {
        occurs_mark(T, f);
        for (int32_t i = 1; i < arity; i++)
          wstack_push(T, f + (size_t)i);
        t = f + (size_t)arity;
        continue;
      }
    }
    if (T->wsp == wbase)
      break;
    t = T->wstack[--T->wsp];
  }
  T->wsp = wbase;
  while (T->occurs_len > base) {
    size_t f = T->occurs_marks[--T->occurs_len];
    T->heap[f].as.func.arity = -1 - T->heap[f].as.func.arity;
  }
  return found;
}

// Last argument in place: lists need no stack.
static int next_pair(trilog_t *T, size_t wbase, size_t *a, size_t *b) {
  if (T->wsp == wbase)
    return 0;
  *b = T->wstack[--T->wsp];
  *a = T->wstack[--T->wsp];
  return 1;
}

static void push_arg_pairs(trilog_t *T, size_t fa, size_t fb, int32_t arity) {
  for (int32_t i = arity - 1; i >= 1; i--) {
    wstack_push(T, fa + (size_t)i);
    wstack_push(T, fb + (size_t)i);
  }
}

static int unify_oc_rec(trilog_t *T, size_t a, size_t b) {
  size_t wbase = T->wsp;
  for (;;) {
    a = heap_deref(T, a);
    b = heap_deref(T, b);
    int ok = 1;
    if (a == b) {
    } else if (T->heap[a].tag == TAG_REF) {
      if ((ok = !occurs(T, a, b)))
        heap_bind(T, a, b);
    } else if (T->heap[b].tag == TAG_REF) {
      if ((ok = !occurs(T, b, a)))
        heap_bind(T, b, a);
    } else if (T->heap[a].tag != TAG_STR || T->heap[b].tag != TAG_STR) {
      ok = unify(T, a, b);
    } else {
      size_t fa = T->heap[a].as.ptr, fb = T->heap[b].as.ptr;
      int32_t arity = T->heap[fa].as.func.arity;
      if (T->heap[fa].as.func.atom_id != T->heap[fb].as.func.atom_id ||
          arity != T->heap[fb].as.func.arity) {
        ok = 0;
      } else if (!pair_visits_seen(T, &T->occurs_check_visits, fa, fb)) {
        push_arg_pairs(T, fa, fb, arity);
        a = fa + (size_t)arity;
        b = fb + (size_t)arity;
        continue;
      }
    }
    if (!ok) {
      T->wsp = wbase;
      return 0;
    }
    if (!next_pair(T, wbase, &a, &b))
      return 1;
  }
}

static int unify_rec(trilog_t *T, size_t a, size_t b) {
  size_t wbase = T->wsp;
  for (;;) {
    a = heap_deref(T, a);
    b = heap_deref(T, b);
    int ok = 1;
    if (a == b) {
    } else if (T->heap[a].tag == TAG_REF) {
      heap_bind(T, a, b);
    } else if (T->heap[b].tag == TAG_REF) {
      heap_bind(T, b, a);
    } else if (T->heap[a].tag != T->heap[b].tag) {
      ok = 0;
    } else {
      switch (T->heap[a].tag) {
      case TAG_ATOM:
        ok = T->heap[a].as.atom_id == T->heap[b].as.atom_id;
        break;
      case TAG_INT:
        ok = T->heap[a].as.ival == T->heap[b].as.ival;
        break;
      case TAG_FLT:
        ok = T->heap[a].as.fval == T->heap[b].as.fval;
        break;
      case TAG_STR: {
        size_t fa = T->heap[a].as.ptr, fb = T->heap[b].as.ptr;
        int32_t arity = T->heap[fa].as.func.arity;
        if (T->heap[fa].as.func.atom_id != T->heap[fb].as.func.atom_id ||
            arity != T->heap[fb].as.func.arity) {
          ok = 0;
        } else if (!pair_visits_seen(T, &T->unify_visits, fa, fb)) {
          push_arg_pairs(T, fa, fb, arity);
          a = fa + (size_t)arity;
          b = fb + (size_t)arity;
          continue;
        }
        break;
      }
      default:
        ok = 0;
      }
    }
    if (!ok) {
      T->wsp = wbase;
      return 0;
    }
    if (!next_pair(T, wbase, &a, &b))
      return 1;
  }
}

int unify(trilog_t *T, size_t a, size_t b) {
  pair_visits_reset(&T->unify_visits);
  return unify_rec(T, a, b);
}

int unify_with_occurs_check(trilog_t *T, size_t a, size_t b) {
  pair_visits_reset(&T->occurs_check_visits);
  return unify_oc_rec(T, a, b);
}

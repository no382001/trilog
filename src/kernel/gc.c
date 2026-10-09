#include "gc.h"
#include "ctx.h"
#include "fmt.h"
#include "heap.h"
#include "io.h"
#include "mem.h"
#include "platform.h"
#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void *gc_realloc_or_die(trilog_t *T, void *p, size_t n) {
  void *r = mem_realloc(T, p, n);
  if (!r && n != 0)
    longjmp(T->gc_oom, 1);
  return r;
}

// Shrinking runs after compaction, so a failure keeps the bigger buffer.
static void *gc_shrink(trilog_t *T, void *p, size_t n) {
  void *r = mem_realloc(T, p, n);
  return r ? r : p;
}

// ---- mark phase: DFS via pointer reversal (O(1) space), marking
// everything reachable from a root; unmarked cells get deleted.

static void ensure_marked_cap(trilog_t *T, size_t n) {
  if (n <= T->marked_cap)
    return;
  size_t new_cap = T->marked_cap ? T->marked_cap : 1024;
  while (new_cap < n)
    new_cap *= 2;
  T->marked = gc_realloc_or_die(T, T->marked, new_cap);
  memset(T->marked + T->marked_cap, 0, new_cap - T->marked_cap);
  T->marked_cap = new_cap;
}

#define NIL ((size_t)-1)

static void mark_from(trilog_t *T, size_t root) {
  size_t t = root, p = NIL;

  for (;;) {
    T->mark_visit_count++;
    if (!T->marked[t]) {
      T->marked[t] = 1;
      switch (T->heap[t].tag) {
      case TAG_ATOM:
      case TAG_INT:
      case TAG_FLT:
        goto climb; // they don't point to anything
      case TAG_REF: {
        if (T->heap[t].as.ref == t)
          goto climb; // unbound variable
        size_t next = T->heap[t].as.ref;
        T->heap[t].as.ref = p; // reverse: park the return link here
        p = t;
        t = next;
        continue;
      }
      case TAG_STR: {
        size_t base = T->heap[t].as.ptr;
        int32_t arity = T->heap[base].as.func.arity;
        T->marked[base] = 1;
        if (arity == 0)
          goto climb; // no children to descend into
        // layout: FUNCTOR at base, then `arity` children, then the STR.
        size_t bound = base + 1 + (size_t)arity;
        T->heap[base].as.func.arity = (int32_t)bound;
        T->heap[t].as.ptr = p;
        p = base;
        t = base + 1;
        continue;
      }
      case TAG_FUNCTOR:
        goto climb; // never treat a root or a child value directly
      }
    } else {
    climb:
      if (p == NIL)
        return;
      if (T->heap[p].tag == TAG_REF) {
        size_t grandp = T->heap[p].as.ref;
        T->heap[p].as.ref =
            t; // restore: points at the now-fully-marked subtree
        t = p;
        p = grandp;
        goto climb_check;
      } else { // it can only be TAG_FUNCTOR
        size_t base = p;
        size_t bound = (size_t)T->heap[base].as.func.arity;
        size_t next_child = t + 1;
        if (next_child < bound) {
          t = next_child;
          continue; // re-enters via the "not marked" check above
        }
        // all children done: restore arity, climb via the owning STR cell.
        T->heap[base].as.func.arity = (int32_t)(bound - base - 1);
        size_t str_idx = bound;
        size_t outer = T->heap[str_idx].as.ptr;
        T->heap[str_idx].as.ptr = base; // restore STR's true pointer
        t = str_idx;
        p = outer;
        goto climb_check;
      }
    climb_check:
      if (p == NIL)
        return;
      goto climb;
    }
  }
}

// ---- slide phase: compute each live cell's new index, fix up
// REF.ref/STR.ptr, then slide cells left.

static void ensure_index_cap(trilog_t *T, size_t n) {
  if (n <= T->new_index_cap)
    return;
  size_t new_cap = T->new_index_cap ? T->new_index_cap : 1024;
  while (new_cap < n)
    new_cap *= 2;
  T->new_index = gc_realloc_or_die(T, T->new_index, new_cap * sizeof(size_t));
  T->new_index_cap = new_cap;
}

// scratch arrays only grow; unlike heap_cap, shrinking them here is free.
static void shrink_scratch_to(trilog_t *T, size_t n) {
  if (n < 1024)
    n = 1024;
  if (T->marked_cap > n) {
    T->marked = gc_shrink(T, T->marked, n);
    T->marked_cap = n;
  }
  if (T->new_index_cap > n) {
    T->new_index = gc_shrink(T, T->new_index, n * sizeof(size_t));
    T->new_index_cap = n;
  }
  if (T->trail_new_index_cap > n) {
    T->trail_new_index = gc_shrink(T, T->trail_new_index, n * sizeof(size_t));
    T->trail_new_index_cap = n;
  }
}

static size_t compact_heap(trilog_t *T, size_t old_top) {
  size_t next_free = 0;
  for (size_t i = 0; i < old_top; i++) {
    T->new_index[i] = next_free;
    if (T->marked[i])
      next_free++;
  }
  // One-past-end sentinel: a mark can sit exactly at old_top (a clause
  // that bound no variables).
  T->new_index[old_top] = next_free;
  for (size_t i = 0; i < old_top; i++) {
    if (!T->marked[i])
      continue;
    if (T->heap[i].tag == TAG_REF)
      T->heap[i].as.ref = T->new_index[T->heap[i].as.ref];
    else if (T->heap[i].tag == TAG_STR)
      T->heap[i].as.ptr = T->new_index[T->heap[i].as.ptr];
  }
  size_t write_ptr = 0;
  for (size_t i = 0; i < old_top; i++) {
    if (!T->marked[i])
      continue;
    if (write_ptr != i)
      T->heap[write_ptr] = T->heap[i];
    write_ptr++;
  }
  return write_ptr;
}

// trail entries whose target var didn't survive marking are safe to drop
static size_t compact_trail(trilog_t *T, size_t old_trail_top) {
  size_t *trail = trail_array(T);
  size_t write_ptr = 0;
  for (size_t i = 0; i < old_trail_top; i++) {
    size_t v = trail[i];
    if (v < T->marked_cap && T->marked[v])
      trail[write_ptr++] = T->new_index[v];
  }
  return write_ptr;
}

#ifndef GC_MIN_CELLS
#define GC_MIN_CELLS 16384
#endif

// GC_SHRINK=0 keeps the heap and GC scratch at their largest size, so a small
// target's allocator never sees them move.
#ifndef GC_SHRINK
#define GC_SHRINK 1
#endif

// live cells allowed after a collection before the solver throws
#ifndef GC_MAX_LIVE_CELLS
#define GC_MAX_LIVE_CELLS ((size_t)64 << 20)
#endif

size_t gc_max_live(trilog_t *T) {
  if (T->gc_max == 0) {
    T->gc_max = GC_MAX_LIVE_CELLS;
    size_t limit = platform_address_space_limit();
    if (limit != 0 && limit / 128 < T->gc_max)
      T->gc_max = limit / 128;
  }
  return T->gc_max;
}

int gc_heap_exhausted(trilog_t *T) {
  int e = T->heap_exhausted;
  T->heap_exhausted = 0;
  return e;
}

static size_t gc_get_threshold(trilog_t *T) {
  if (T->gc_threshold != 0)
    return T->gc_threshold;
  T->gc_threshold = T->gc_fixed ? T->gc_fixed : GC_MIN_CELLS;
  return T->gc_threshold;
}

static void ensure_catch_live_cap(trilog_t *T, size_t n) {
  if (n <= T->catch_live_cap)
    return;
  size_t new_cap = T->catch_live_cap ? T->catch_live_cap : 64;
  while (new_cap < n)
    new_cap *= 2;
  T->catch_live = gc_realloc_or_die(T, T->catch_live, new_cap);
  memset(T->catch_live + T->catch_live_cap, 0, new_cap - T->catch_live_cap);
  T->catch_live_cap = new_cap;
}

static void mark_catch_chain(trilog_t *T, size_t idx, catch_frame_t *catches) {
  while (idx != NIL && !T->catch_live[idx]) {
    T->catch_live[idx] = 1;
    mark_from(T, catches[idx].catcher);
    mark_from(T, catches[idx].recovery);
    mark_from(T, catches[idx].continuation);
    idx = catches[idx].outer_active_catch;
  }
}

static void ensure_new_catch_index_cap(trilog_t *T, size_t n) {
  if (n <= T->new_catch_index_cap)
    return;
  size_t new_cap = T->new_catch_index_cap ? T->new_catch_index_cap : 64;
  while (new_cap < n)
    new_cap *= 2;
  T->new_catch_index =
      gc_realloc_or_die(T, T->new_catch_index, new_cap * sizeof(size_t));
  T->new_catch_index_cap = new_cap;
}

static size_t compact_catches(trilog_t *T, catch_frame_t *catches,
                              size_t old_ncatches) {
  size_t next_free = 0;
  for (size_t i = 0; i < old_ncatches; i++) {
    T->new_catch_index[i] = next_free;
    if (T->catch_live[i])
      next_free++;
  }
  for (size_t i = 0; i < old_ncatches; i++) {
    if (!T->catch_live[i])
      continue;
    if (catches[i].outer_active_catch != NIL)
      catches[i].outer_active_catch =
          T->new_catch_index[catches[i].outer_active_catch];
  }
  size_t write_ptr = 0;
  for (size_t i = 0; i < old_ncatches; i++) {
    if (!T->catch_live[i])
      continue;
    if (write_ptr != i)
      catches[write_ptr] = catches[i];
    write_ptr++;
  }
  return write_ptr;
}

void gc_maybe_run(trilog_t *T, size_t *cn, frame_t *frames, size_t nframes,
                  size_t *rename, int32_t nvars, size_t *active_catch) {
  size_t old_top = heap_size(T);
  if (old_top < gc_get_threshold(T))
    return;
  if (setjmp(T->gc_oom)) {
    T->heap_exhausted = 1;
    return;
  }

  size_t old_trail_top = trail_size(T);
  ensure_marked_cap(T, old_top);
  memset(T->marked, 0, old_top);
  ensure_index_cap(T, old_top + 1); // +1 for the one-past-end sentinel

  catch_frame_t *catches = catch_stack_array(T);
  size_t ncatches = catch_stack_size(T);
  ensure_catch_live_cap(T, ncatches);
  // catch_live can still be NULL if nothing has ever pushed a catch/3
  // frame yet.
  if (ncatches)
    memset(T->catch_live, 0, ncatches);
  ensure_new_catch_index_cap(T, ncatches);

  T->mark_visit_count = 0;
  mark_from(T, *cn);
  for (size_t i = 0; i < nframes; i++)
    mark_from(T, frames[i].goals);
  for (int32_t i = 0; i < nvars; i++)
    if (rename[i] != NIL)
      mark_from(T, rename[i]);

  mark_catch_chain(T, *active_catch, catches);
  for (size_t i = 0; i < nframes; i++)
    mark_catch_chain(T, frames[i].active_catch, catches);

  // trail_new_index must be computed from the trail's ORIGINAL contents,
  // before compact_trail() mutates it in place
  if (old_trail_top + 1 > T->trail_new_index_cap) {
    T->trail_new_index = gc_realloc_or_die(
        T, T->trail_new_index, (old_trail_top + 1) * sizeof(size_t));
    T->trail_new_index_cap = old_trail_top + 1;
  }
  {
    size_t *trail = trail_array(T);
    size_t next_free = 0;
    for (size_t i = 0; i < old_trail_top; i++) {
      T->trail_new_index[i] = next_free;
      if (trail[i] < T->marked_cap && T->marked[trail[i]])
        next_free++;
    }
    T->trail_new_index[old_trail_top] = next_free;
  }

  size_t new_top = compact_heap(T, old_top);
  if (new_top > gc_max_live(T))
    T->heap_exhausted = 1;
  size_t new_trail_top = compact_trail(T, old_trail_top);

  *cn = T->new_index[*cn];
  for (size_t i = 0; i < nframes; i++) {
    frames[i].goals = T->new_index[frames[i].goals];
    frames[i].heap_mark = T->new_index[frames[i].heap_mark];
  }
  for (int32_t i = 0; i < nvars; i++)
    if (rename[i] != NIL)
      rename[i] = T->new_index[rename[i]];
  // only entries mark_catch_chain reached are safe to touch - a dead
  // entry's fields can hold indices from before an earlier compaction.
  for (size_t i = 0; i < ncatches; i++) {
    if (!T->catch_live[i])
      continue;
    catches[i].catcher = T->new_index[catches[i].catcher];
    catches[i].recovery = T->new_index[catches[i].recovery];
    catches[i].continuation = T->new_index[catches[i].continuation];
    catches[i].heap_mark = T->new_index[catches[i].heap_mark];
  }

  for (size_t i = 0; i < nframes; i++)
    frames[i].trail_mark = T->trail_new_index[frames[i].trail_mark];
  for (size_t i = 0; i < ncatches; i++)
    if (T->catch_live[i])
      catches[i].trail_mark = T->trail_new_index[catches[i].trail_mark];

  // slide live catch_stack entries down and remap every reference to a
  // catch_stack index (not a heap/trail one) accordingly.
  size_t new_ncatches = compact_catches(T, catches, ncatches);
  if (*active_catch != NIL)
    *active_catch = T->new_catch_index[*active_catch];
  for (size_t i = 0; i < nframes; i++)
    if (frames[i].active_catch != NIL)
      frames[i].active_catch = T->new_catch_index[frames[i].active_catch];
  catch_stack_set_size(T, new_ncatches);

  heap_set_size(T, new_top);
  trail_set_size(T, new_trail_top);

  if (!T->gc_fixed)
    T->gc_threshold = new_top * 2 > GC_MIN_CELLS ? new_top * 2 : GC_MIN_CELLS;

  // tie capacity to gc_threshold so it can shrink after a big collection.
  if (GC_SHRINK || T->gc_threshold > heap_capacity(T))
    heap_set_capacity(T, T->gc_threshold);
  if (GC_SHRINK)
    shrink_scratch_to(T, new_top + 1);

  if (T->gc_debug) {
    char msg[300];
    fmt(msg, sizeof msg,
        "gc: heap %zu -> %zu, trail %zu -> %zu, nframes=%zu, "
        "mark_visits=%zu, threshold=%zu, "
        "heap_cap=%zu, new_index_cap=%zu\n",
        old_top, new_top, old_trail_top, new_trail_top, nframes,
        T->mark_visit_count, T->gc_threshold, heap_capacity(T),
        T->new_index_cap);
    io_write_err(T, msg);
  }
}

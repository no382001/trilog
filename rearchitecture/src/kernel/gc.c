#include "gc.h"
#include "heap.h"
#include "io.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *gc_realloc_or_die(void *p, size_t n) {
  void *r = realloc(p, n);
  if (!r && n != 0) {
    io_write_err("out of memory during garbage collection\n");
    exit(1);
  }
  return r;
}

// ---- mark phase: DFS via pointer reversal (O(1) space), marking
// everything reachable from a root; unmarked cells get deleted.

static uint8_t *marked = NULL;
static size_t marked_cap = 0;

static void ensure_marked_cap(size_t n) {
  if (n <= marked_cap)
    return;
  size_t new_cap = marked_cap ? marked_cap : 1024;
  while (new_cap < n)
    new_cap *= 2;
  marked = gc_realloc_or_die(marked, new_cap);
  memset(marked + marked_cap, 0, new_cap - marked_cap);
  marked_cap = new_cap;
}

#define NIL ((size_t)-1)

static size_t mark_visit_count = 0; // diagnostic only, read by TRILOG_GC_DEBUG

static void mark_from(size_t root) {
  size_t t = root, p = NIL;

  for (;;) {
    mark_visit_count++;
    if (!marked[t]) {
      marked[t] = 1;
      switch (heap[t].tag) {
      case TAG_ATOM:
      case TAG_INT:
      case TAG_FLT:
        goto climb; // they don't point to anything
      case TAG_REF: {
        if (heap[t].as.ref == t)
          goto climb; // unbound variable
        size_t next = heap[t].as.ref;
        heap[t].as.ref = p; // reverse: park the return link here
        p = t;
        t = next;
        continue;
      }
      case TAG_STR: {
        size_t base = heap[t].as.ptr;
        int32_t arity = heap[base].as.func.arity;
        marked[base] = 1;
        if (arity == 0)
          goto climb; // no children to descend into
        // layout: FUNCTOR at base, then `arity` children, then the STR.
        size_t bound = base + 1 + (size_t)arity;
        heap[base].as.func.arity = (int32_t)bound;
        heap[t].as.ptr = p;
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
      if (heap[p].tag == TAG_REF) {
        size_t grandp = heap[p].as.ref;
        heap[p].as.ref = t; // restore: points at the now-fully-marked subtree
        t = p;
        p = grandp;
        goto climb_check;
      } else { // it can only be TAG_FUNCTOR
        size_t base = p;
        size_t bound = (size_t)heap[base].as.func.arity;
        size_t next_child = t + 1;
        if (next_child < bound) {
          t = next_child;
          continue; // re-enters via the "not marked" check above
        }
        // all children done: restore arity, climb via the owning STR cell.
        heap[base].as.func.arity = (int32_t)(bound - base - 1);
        size_t str_idx = bound;
        size_t outer = heap[str_idx].as.ptr;
        heap[str_idx].as.ptr = base; // restore STR's true pointer
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

static size_t *new_index = NULL;
static size_t new_index_cap = 0;

static void ensure_index_cap(size_t n) {
  if (n <= new_index_cap)
    return;
  size_t new_cap = new_index_cap ? new_index_cap : 1024;
  while (new_cap < n)
    new_cap *= 2;
  new_index = gc_realloc_or_die(new_index, new_cap * sizeof(size_t));
  new_index_cap = new_cap;
}

static size_t *trail_new_index = NULL;
static size_t trail_new_index_cap = 0;

// scratch arrays only grow; unlike heap_cap, shrinking them here is free.
static void shrink_scratch_to(size_t n) {
  if (n < 1024)
    n = 1024;
  if (marked_cap > n) {
    marked = gc_realloc_or_die(marked, n);
    marked_cap = n;
  }
  if (new_index_cap > n) {
    new_index = gc_realloc_or_die(new_index, n * sizeof(size_t));
    new_index_cap = n;
  }
  if (trail_new_index_cap > n) {
    trail_new_index = gc_realloc_or_die(trail_new_index, n * sizeof(size_t));
    trail_new_index_cap = n;
  }
}

static size_t compact_heap(size_t old_top) {
  size_t next_free = 0;
  for (size_t i = 0; i < old_top; i++) {
    new_index[i] = next_free;
    if (marked[i])
      next_free++;
  }
  // One-past-end sentinel: a mark can sit exactly at old_top (a clause
  // that bound no variables).
  new_index[old_top] = next_free;
  for (size_t i = 0; i < old_top; i++) {
    if (!marked[i])
      continue;
    if (heap[i].tag == TAG_REF)
      heap[i].as.ref = new_index[heap[i].as.ref];
    else if (heap[i].tag == TAG_STR)
      heap[i].as.ptr = new_index[heap[i].as.ptr];
  }
  size_t write_ptr = 0;
  for (size_t i = 0; i < old_top; i++) {
    if (!marked[i])
      continue;
    if (write_ptr != i)
      heap[write_ptr] = heap[i];
    write_ptr++;
  }
  return write_ptr;
}

// trail entries whose target var didn't survive marking are safe to drop
static size_t compact_trail(size_t old_trail_top) {
  size_t *trail = trail_array();
  size_t write_ptr = 0;
  for (size_t i = 0; i < old_trail_top; i++) {
    size_t v = trail[i];
    if (v < marked_cap && marked[v])
      trail[write_ptr++] = new_index[v];
  }
  return write_ptr;
}

static size_t gc_threshold = 0; // 0 = uninitialized

static size_t gc_get_threshold(void) {
  if (gc_threshold != 0)
    return gc_threshold;
  const char *env = getenv("TRILOG_GC_THRESHOLD");
  gc_threshold = env ? (size_t)strtoul(env, NULL, 10) : 4096;
  if (gc_threshold == 0)
    gc_threshold = 4096; // reject a nonsense override
  return gc_threshold;
}

// catch_stack is append-only, so a dead entry can hold a stale heap index -
// `catch_live` marks which indices mark_catch_chain actually reached.
static uint8_t *catch_live = NULL;
static size_t catch_live_cap = 0;

static void ensure_catch_live_cap(size_t n) {
  if (n <= catch_live_cap)
    return;
  size_t new_cap = catch_live_cap ? catch_live_cap : 64;
  while (new_cap < n)
    new_cap *= 2;
  catch_live = gc_realloc_or_die(catch_live, new_cap);
  memset(catch_live + catch_live_cap, 0, new_cap - catch_live_cap);
  catch_live_cap = new_cap;
}

static void mark_catch_chain(size_t idx, catch_frame_t *catches) {
  while (idx != NIL && !catch_live[idx]) {
    catch_live[idx] = 1;
    mark_from(catches[idx].catcher);
    mark_from(catches[idx].recovery);
    mark_from(catches[idx].continuation);
    idx = catches[idx].outer_active_catch;
  }
}

// Marking alone isn't enough: catch_sp keeps growing, so every GC pass
// would still pay O(catch_sp) to skip the dead majority - slide live
// entries down, same as the heap.
static size_t *new_catch_index = NULL;
static size_t new_catch_index_cap = 0;

static void ensure_new_catch_index_cap(size_t n) {
  if (n <= new_catch_index_cap)
    return;
  size_t new_cap = new_catch_index_cap ? new_catch_index_cap : 64;
  while (new_cap < n)
    new_cap *= 2;
  new_catch_index =
      gc_realloc_or_die(new_catch_index, new_cap * sizeof(size_t));
  new_catch_index_cap = new_cap;
}

static size_t compact_catches(catch_frame_t *catches, size_t old_ncatches) {
  size_t next_free = 0;
  for (size_t i = 0; i < old_ncatches; i++) {
    new_catch_index[i] = next_free;
    if (catch_live[i])
      next_free++;
  }
  for (size_t i = 0; i < old_ncatches; i++) {
    if (!catch_live[i])
      continue;
    if (catches[i].outer_active_catch != NIL)
      catches[i].outer_active_catch =
          new_catch_index[catches[i].outer_active_catch];
  }
  size_t write_ptr = 0;
  for (size_t i = 0; i < old_ncatches; i++) {
    if (!catch_live[i])
      continue;
    if (write_ptr != i)
      catches[write_ptr] = catches[i];
    write_ptr++;
  }
  return write_ptr;
}

void gc_maybe_run(size_t *cn, frame_t *frames, size_t nframes, size_t *rename,
                  int32_t nvars, size_t *active_catch) {
  size_t old_top = heap_size();
  if (old_top < gc_get_threshold())
    return;

  size_t old_trail_top = trail_size();
  ensure_marked_cap(old_top);
  memset(marked, 0, old_top);
  ensure_index_cap(old_top + 1); // +1 for the one-past-end sentinel

  catch_frame_t *catches = catch_stack_array();
  size_t ncatches = catch_stack_size();
  ensure_catch_live_cap(ncatches);
  // catch_live can still be NULL if nothing has ever pushed a catch/3
  // frame yet.
  if (ncatches)
    memset(catch_live, 0, ncatches);
  ensure_new_catch_index_cap(ncatches);

  mark_visit_count = 0;
  mark_from(*cn);
  for (size_t i = 0; i < nframes; i++)
    mark_from(frames[i].goals);
  for (int32_t i = 0; i < nvars; i++)
    if (rename[i] != NIL)
      mark_from(rename[i]);

  mark_catch_chain(*active_catch, catches);
  for (size_t i = 0; i < nframes; i++)
    mark_catch_chain(frames[i].active_catch, catches);

  // trail_new_index must be computed from the trail's ORIGINAL contents,
  // before compact_trail() mutates it in place
  if (old_trail_top + 1 > trail_new_index_cap) {
    trail_new_index_cap = old_trail_top + 1;
    trail_new_index = gc_realloc_or_die(trail_new_index,
                                        trail_new_index_cap * sizeof(size_t));
  }
  {
    size_t *trail = trail_array();
    size_t next_free = 0;
    for (size_t i = 0; i < old_trail_top; i++) {
      trail_new_index[i] = next_free;
      if (trail[i] < marked_cap && marked[trail[i]])
        next_free++;
    }
    trail_new_index[old_trail_top] = next_free;
  }

  size_t new_top = compact_heap(old_top);
  size_t new_trail_top = compact_trail(old_trail_top);

  *cn = new_index[*cn];
  for (size_t i = 0; i < nframes; i++) {
    frames[i].goals = new_index[frames[i].goals];
    frames[i].heap_mark = new_index[frames[i].heap_mark];
  }
  for (int32_t i = 0; i < nvars; i++)
    if (rename[i] != NIL)
      rename[i] = new_index[rename[i]];
  // only entries mark_catch_chain reached are safe to touch - a dead
  // entry's fields can hold indices from before an earlier compaction.
  for (size_t i = 0; i < ncatches; i++) {
    if (!catch_live[i])
      continue;
    catches[i].catcher = new_index[catches[i].catcher];
    catches[i].recovery = new_index[catches[i].recovery];
    catches[i].continuation = new_index[catches[i].continuation];
    catches[i].heap_mark = new_index[catches[i].heap_mark];
  }

  for (size_t i = 0; i < nframes; i++)
    frames[i].trail_mark = trail_new_index[frames[i].trail_mark];
  for (size_t i = 0; i < ncatches; i++)
    if (catch_live[i])
      catches[i].trail_mark = trail_new_index[catches[i].trail_mark];

  // slide live catch_stack entries down and remap every reference to a
  // catch_stack index (not a heap/trail one) accordingly.
  size_t new_ncatches = compact_catches(catches, ncatches);
  if (*active_catch != NIL)
    *active_catch = new_catch_index[*active_catch];
  for (size_t i = 0; i < nframes; i++)
    if (frames[i].active_catch != NIL)
      frames[i].active_catch = new_catch_index[frames[i].active_catch];
  catch_stack_set_size(new_ncatches);

  heap_set_size(new_top);
  trail_set_size(new_trail_top);

  // grow the threshold with live data, unless a test forces GC every
  // safepoint via TRILOG_GC_THRESHOLD.
  if (!getenv("TRILOG_GC_THRESHOLD"))
    gc_threshold = new_top * 2 > 4096 ? new_top * 2 : 4096;

  // tie capacity to gc_threshold so it can shrink after a big collection.
  heap_set_capacity(gc_threshold);
  shrink_scratch_to(new_top + 1);

  if (getenv("TRILOG_GC_DEBUG")) {
    char msg[300];
    snprintf(msg, sizeof msg,
             "gc: heap %zu -> %zu, trail %zu -> %zu, nframes=%zu, "
             "mark_visits=%zu, threshold=%zu, "
             "heap_cap=%zu, new_index_cap=%zu\n",
             old_top, new_top, old_trail_top, new_trail_top, nframes,
             mark_visit_count, gc_threshold, heap_capacity(), new_index_cap);
    io_write_err(msg);
  }
}

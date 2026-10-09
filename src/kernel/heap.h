#pragma once
#include "trilog.h"
#include <stddef.h>
#include <stdint.h>

// STR points at a FUNCTOR cell, followed by `arity` arg cells.
// FUNCTOR cells are metadata only, never deref'd as a value.
typedef enum {
  TAG_REF,
  TAG_ATOM,
  TAG_INT,
  TAG_FLT,
  TAG_STR,
  TAG_FUNCTOR
} tag_t;

typedef struct {
  tag_t tag;
  union {
    size_t ref;      // REF: heap index (self = unbound)
    int32_t atom_id; // ATOM
    int64_t ival;    // INT
    double fval;     // FLT
    size_t ptr;      // STR: heap index of the FUNCTOR cell it points to
    struct {
      int32_t atom_id;
      int32_t arity;
    } func; // FUNCTOR
  } as;
} cell_t;

void heap_init(trilog_t *T);

size_t heap_alloc(trilog_t *T, size_t n);

size_t heap_new_var(trilog_t *T);
size_t heap_new_atom(trilog_t *T, int32_t atom_id);
size_t heap_new_int(trilog_t *T, int64_t v);
size_t heap_new_flt(trilog_t *T, double v);
// NULL arg_idx: unbound arguments.
size_t heap_new_struct(trilog_t *T, int32_t functor_id, int32_t arity,
                       size_t *arg_idx);

size_t heap_deref(trilog_t *T, size_t r);

size_t heap_mark(trilog_t *T);
void heap_release(trilog_t *T, size_t mark);
size_t heap_peak_size(trilog_t *T);

void heap_bind(trilog_t *T, size_t var, size_t target);
size_t trail_mark(trilog_t *T);
void trail_release(trilog_t *T, size_t mark);

int32_t atom_intern(trilog_t *T, const char *name);
const char *atom_name(trilog_t *T, int32_t atom_id);

size_t heap_size(trilog_t *T);
void heap_set_size(trilog_t *T, size_t n);
size_t *trail_array(trilog_t *T);
size_t trail_size(trilog_t *T);
void trail_set_size(trilog_t *T, size_t n);

void heap_set_capacity(trilog_t *T, size_t n);
size_t heap_capacity(trilog_t *T); // diagnostic only, read by TRILOG_GC_DEBUG

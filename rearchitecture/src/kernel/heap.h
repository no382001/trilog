#pragma once
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

void heap_init(void);

size_t heap_alloc(size_t n);

size_t heap_new_var(void);
size_t heap_new_atom(int32_t atom_id);
size_t heap_new_int(int64_t v);
size_t heap_new_flt(double v);
size_t heap_new_struct(int32_t functor_id, int32_t arity, size_t *arg_idx);

size_t heap_deref(size_t r);

size_t heap_mark(void);
void heap_release(size_t mark);
size_t heap_peak_size(void);

void heap_bind(size_t var, size_t target);
size_t trail_mark(void);
void trail_release(size_t mark);

int32_t atom_intern(const char *name);
const char *atom_name(int32_t atom_id);

extern cell_t *heap;

size_t heap_size(void);
void heap_set_size(size_t n);
size_t *trail_array(void);
size_t trail_size(void);
void trail_set_size(size_t n);

void heap_set_capacity(size_t n);
size_t heap_capacity(void); // diagnostic only, read by TRILOG_GC_DEBUG

#pragma once
#include <stddef.h>
#include <stdint.h>

// STR points at a FUNCTOR cell, followed by `arity` arg cells.
// FUNCTOR cells are metadata only, never deref'd as a value.
typedef enum { TAG_REF, TAG_ATOM, TAG_INT, TAG_FLT, TAG_STR, TAG_FUNCTOR } tag_t;

typedef struct {
    tag_t tag;
    union {
        size_t ref;      // REF: heap index (self = unbound)
        int32_t atom_id; // ATOM
        int64_t ival;    // INT
        double fval;     // FLT
        size_t ptr;      // STR: heap index of the FUNCTOR cell it points to
        struct { int32_t atom_id; int32_t arity; } func; // FUNCTOR
    } as;
} cell_t;

void heap_init(void);

size_t heap_alloc(size_t n);

size_t heap_new_var(void);
size_t heap_new_atom(int32_t atom_id);
size_t heap_new_int(int64_t v);
size_t heap_new_flt(double v);
// arg_idx[i] is the already-built heap index for argument i; each slot
// becomes a REF indirection to it, so callers never worry about its shape.
size_t heap_new_struct(int32_t functor_id, int32_t arity, size_t *arg_idx);

size_t heap_deref(size_t r);

// Choice-point marks pair heap+trail; anything allocated past a mark is
// scratch that backtracking discards for free - bump allocation never fragments.
size_t heap_mark(void);
void heap_release(size_t mark);

// binds an unbound REF cell at `var` to point at `target`, recording it on
// the trail so backtracking can undo exactly this and nothing else.
void heap_bind(size_t var, size_t target);
size_t trail_mark(void);
void trail_release(size_t mark);

// interned atom table: same string in, same small integer id out.
int32_t atom_intern(const char *name);
const char *atom_name(int32_t atom_id);

extern cell_t *heap;

// Raw access to the bump pointer/trail, for gc.c only - everyday code wants
// heap_mark/heap_release and trail_mark/trail_release instead.
size_t heap_size(void);
void heap_set_size(size_t n);
size_t *trail_array(void);
size_t trail_size(void);
void trail_set_size(size_t n);

// Resizes the buffer to at least `n` cells - can shrink, unlike heap_alloc's
// own growth - so GC's chosen threshold becomes the buffer's real capacity.
void heap_set_capacity(size_t n);
size_t heap_capacity(void); // diagnostic only, read by TRILOG_GC_DEBUG

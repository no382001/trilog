#pragma once
#include "heap.h"
#include "io.h"
#include "mem.h"
#include "solve.h"
#include "streams.h"
#include "trilog.h"
#include "unify.h"
#include <setjmp.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define CAPTURE_STACK_MAX 32

struct chunk;

typedef struct {
  size_t ref;
  const char *name; // NULL: fresh, printed as _A, _B, ...
  int fresh;
} answer_var_t;

typedef struct {
  struct tterm *t;
  int32_t nvars;
} bag_item_t;

typedef struct {
  struct chunk *chunks;
  bag_item_t *items;
  size_t len, cap;
} bag_t;

// ATOM_SLOTS_16 halves the atom hash for builds that never hold more than
// 32767 atoms.
#ifdef ATOM_SLOTS_16
typedef int16_t atom_slot_t;
#define ATOM_SLOT_MAX INT16_MAX
#else
typedef int32_t atom_slot_t;
#define ATOM_SLOT_MAX INT32_MAX
#endif

struct trilog {
  void *(*alloc_realloc)(void *ud, void *p, size_t n);
  void (*alloc_free)(void *ud, void *p);
  void *alloc_ud;
  jmp_buf fatal_jmp;
  bool halted;
  int halt_code;
  bool aborted;
  trilog_yield_fn yield_fn;
  void *yield_ud;
  unsigned yield_every, yield_count;

  struct chunk *arena_current;
  struct chunk *arena_temp;
  bool arena_use_temp;
  struct chunk **arena_into;   // when set, arena_alloc allocates there
  struct chunk *arena_pending; // a copy being built, freed if it is cut short
  bag_t *bags;                 // a stack: findalls nest
  int32_t bag_count, bag_cap;

  cell_t *heap;
  size_t heap_cap, heap_top, heap_peak;
  size_t *trail;
  size_t trail_cap, trail_top;
  char **atoms;
  int32_t atom_count, atom_cap;
  atom_slot_t *atom_slots; // open addressing over atom ids, -1 is empty
  uint32_t atom_slots_cap;

  trilog_io_t hooks;
  bool default_io;
  size_t gc_fixed;
  bool gc_debug;
  unsigned heap_grow_percent, gc_grow_percent;
  io_reader_t *streams[MAX_OPEN_STREAMS];

  pair_visits unify_visits, occurs_check_visits;
  size_t *occurs_marks;
  size_t occurs_len, occurs_cap;

  int template_cyclic;
  size_t *template_marks;
  size_t template_marks_len, template_marks_cap;

  jmp_buf gc_oom;
  uint8_t *marked;
  size_t marked_cap;
  size_t mark_visit_count; // diagnostic only, read by gc_debug
  size_t *new_index;
  size_t new_index_cap;
  size_t *trail_new_index;
  size_t trail_new_index_cap;
  int heap_exhausted;
  size_t gc_threshold; // 0 = uninitialized
  size_t gc_old_top, gc_old_at_major;
  size_t gc_max;
  // catch_stack is append-only, so a dead entry can hold a stale heap index -
  // `catch_live` marks which indices mark_catch_chain actually reached.
  uint8_t *catch_live;
  size_t catch_live_cap;
  // catch_sp keeps growing, so every GC pass
  // would still pay O(catch_sp) so slide live
  // entries down
  size_t *new_catch_index;
  size_t new_catch_index_cap;

  const char *P;
  jmp_buf err_jmp;
  char err_msg[256];
  char fatal_trace[256];
  size_t *query_cn;   // into run_query_body's C frame; NULL outside a query
  int32_t *var_names; // atom ids
  int32_t var_count;
  size_t var_names_cap;
  char *tok; // parser token, valid until the next token is read
  size_t tok_cap;
  struct tterm **pstack; // parser scratch for arguments and list elements
  size_t psp, pstack_cap;
  char *path_buf, *path_tmp; // consult path scratch, PATH_CAP bytes each
  void *scratch;             // builtin scratch; builtins do not nest
  size_t scratch_cap;
  size_t *wstack;
  size_t wsp, wstack_cap; // cap in bytes
  // one rename table and goal list per query nesting level
  struct query_buf {
    size_t *p;
    size_t cap;
  } *query_bufs;
  int query_bufs_len;
  size_t *rename_tmp, *goals_tmp; // short-lived, never nested
  size_t rename_tmp_cap, goals_tmp_cap;
  const char *consulting; // path of the file being consulted
  int32_t consulting_atom;
  // -1 when the file being consulted declared no module.
  int32_t module_id;
  pred_decl_t *module_exports, *module_private;
  int32_t module_nexports, module_nprivate, module_private_cap;
  // A directive's error(_, load/1) for '$$consult'; (size_t)-1 if none.
  size_t load_error_ball;
  size_t directive_errors; // directives that raised an uncaught error
  // Rebuilt from the '$$op' clauses whenever op_gen has moved; sized by the
  // operators, not by every atom.
  struct atom_ops {
    int32_t atom;   // -1: empty
    int16_t pri[3]; // by OP_CLASS_*, 0 when there is none
    int8_t assoc[3];
  } *ops;
  int32_t ops_len; // a power of two
  uint32_t op_gen, ops_gen;
  // Variables of the clause being patched that hold a caller's goal.
  int32_t *module_meta_vars;
  int32_t module_nmeta_vars, module_meta_vars_cap;
  bool module_final; // the end-of-file pass, when every head is known
  // Kept here, not on the C stack, so an unwind cannot lose it.
  struct module_state {
    int32_t id, nexports, nprivate, private_cap;
    pred_decl_t *exports, *private_decls;
  } *module_saved;
  int32_t module_saved_len, module_saved_cap;
  char *qualified_buf; // scratch for 'Module:Name' text
  size_t qualified_buf_cap;

  clause_t *db;
  int32_t db_count, db_cap, db_dead;
  uint32_t db_gen;    // bumped by every assert and retract
  int32_t db_pending; // retracted clauses a frame may still see
  pred_bucket_t *pred_hash[PRED_HASH_SIZE];
  // "static" = clause came from literal source text (assemble_clause's own
  // db_add/db_add_front calls, mark_static=1)
  pred_decl_t *consulted_decls;
  int32_t consulted_count, consulted_cap;
  // boot/core.pl declares fail/0 and false/0 this way
  dyn_decl_t *dynamic_decls;
  int32_t dynamic_count, dynamic_cap;
  foreign_t *foreign;
  int32_t foreign_count, foreign_cap;
  const foreign_t *foreign_current;
  size_t foreign_error;
  frame_t *stack;
  size_t stack_cap, sp;
  catch_frame_t *catch_stack;
  size_t catch_sp, catch_cap;
  size_t pending_error_ball;
  int32_t error_pi_name, error_pi_arity;
  size_t uncaught_ball;
  size_t *solution_rename;
  size_t query_sp_base;
  // GC in a nested query neither moves nor frees what is below these.
  size_t query_heap_base, query_catch_base;
  int query_depth;
  pair_visits compare_visits;
  void *file_target;
  char *capture_buf; // a slice per nesting
  size_t capture_cap, capture_pos;
  size_t capture_starts[CAPTURE_STACK_MAX];
  int capture_sp;
  size_t tta_pos; // in scratch
  // Bytes peeked on user_input but not read; in_eof once a peek hit the end.
  unsigned char in_ahead[4];
  int in_ahead_len;
  bool in_eof;
  char *read_buf; // the text of the term read/1 is reading
  size_t read_buf_cap;

  bool in_query;
  bool in_callback;
  int32_t nvars;
  const char **varnames;
  trilog_term_t error;
  char *format_buf;
  size_t format_cap, format_len;
  answer_var_t *answer_vars;
  size_t answer_vars_cap, answer_len;
  uint32_t *answer_index; // open addressing over answer_vars, 0 is empty
  size_t answer_index_cap, answer_slots;
  int answer_fresh;
  bool answer_naming;
  bool answer_plain; // an unnamed variable prints as _G<n>, not a fresh _A
  bool parse_repr;   // the last parse error is a representation_error
  // The flags set_prolog_flag/2 changes, as atoms.
  int32_t flag_double_quotes, flag_unknown, flag_char_conversion, flag_debug;
  int print_last;    // the last char the printer wrote, 0 at the start
  bool print_prefix; // a prefix operator was just written
};

static inline void wstack_push(trilog_t *T, size_t x) {
  if ((T->wsp + 1) * sizeof(size_t) > T->wstack_cap)
    mem_reserve(T, (void **)&T->wstack, &T->wstack_cap,
                (T->wsp + 1) * sizeof(size_t));
  T->wstack[T->wsp++] = x;
}

static inline size_t heap_deref(trilog_t *T, size_t r) {
  while (T->heap[r].tag == TAG_REF && T->heap[r].as.ref != r)
    r = T->heap[r].as.ref;
  return r;
}

static inline size_t heap_alloc(trilog_t *T, size_t n) {
  if (T->heap_top + n > T->heap_cap)
    heap_grow(T, n);
  size_t base = T->heap_top;
  T->heap_top += n;
  if (T->heap_top > T->heap_peak)
    T->heap_peak = T->heap_top;
  return base;
}

static inline size_t heap_new_var(trilog_t *T) {
  size_t i = heap_alloc(T, 1);
  T->heap[i].tag = TAG_REF;
  T->heap[i].as.ref = i;
  return i;
}

static inline size_t heap_new_atom(trilog_t *T, int32_t atom_id) {
  size_t i = heap_alloc(T, 1);
  T->heap[i].tag = TAG_ATOM;
  T->heap[i].as.atom_id = atom_id;
  return i;
}

static inline size_t heap_new_int(trilog_t *T, int64_t v) {
  size_t i = heap_alloc(T, 1);
  T->heap[i].tag = TAG_INT;
  T->heap[i].as.ival = v;
  return i;
}

static inline size_t heap_new_flt(trilog_t *T, double v) {
  if (v == 0.0) // -0.0 too: 13211-1 has no negative zero
    v = 0.0;
  size_t i = heap_alloc(T, 1);
  T->heap[i].tag = TAG_FLT;
  T->heap[i].as.fval = v;
  return i;
}

// NULL arg_idx: unbound arguments.
static inline size_t heap_new_struct(trilog_t *T, int32_t functor_id,
                                     int32_t arity, size_t *arg_idx) {
  size_t base = heap_alloc(T, (size_t)(1 + arity));
  T->heap[base].tag = TAG_FUNCTOR;
  T->heap[base].as.func.atom_id = functor_id;
  T->heap[base].as.func.arity = arity;
  for (int32_t i = 0; i < arity; i++) {
    T->heap[base + 1 + i].tag = TAG_REF;
    T->heap[base + 1 + i].as.ref = arg_idx ? arg_idx[i] : base + 1 + (size_t)i;
  }
  size_t str = heap_alloc(T, 1);
  T->heap[str].tag = TAG_STR;
  T->heap[str].as.ptr = base;
  return str;
}

#pragma once
#include "heap.h"
#include "io.h"
#include "solve.h"
#include "streams.h"
#include "trilog.h"
#include "unify.h"
#include <setjmp.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define CAPTURE_BUF_SIZE 4096
#define CAPTURE_STACK_MAX 32
#define MAX_CVARS 512
#define MAX_VARNAME 256

struct chunk;

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

  cell_t *heap;
  size_t heap_cap, heap_top, heap_peak;
  size_t *trail;
  size_t trail_cap, trail_top;
  char **atoms;
  int32_t atom_count, atom_cap;

  trilog_io_t hooks;
  void *open_streams[MAX_OPEN_STREAMS];

  pair_visits unify_visits, occurs_check_visits;
  size_t *occurs_marks;
  size_t occurs_len, occurs_cap;

  int print_depth;
  int template_cyclic;
  size_t *template_marks;
  size_t template_marks_len, template_marks_cap;

  jmp_buf gc_oom;
  uint8_t *marked;
  size_t marked_cap;
  size_t mark_visit_count; // diagnostic only, read by TRILOG_GC_DEBUG
  size_t *new_index;
  size_t new_index_cap;
  size_t *trail_new_index;
  size_t trail_new_index_cap;
  int heap_exhausted;
  size_t gc_threshold; // 0 = uninitialized
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
  char var_names[MAX_CVARS][MAX_VARNAME];
  int32_t var_count;
  const char *consulting; // path of the file being consulted

  clause_t *db;
  int32_t db_count, db_cap, db_dead;
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
  frame_t *stack;
  size_t stack_cap, sp;
  catch_frame_t *catch_stack;
  size_t catch_sp, catch_cap;
  size_t pending_error_ball;
  size_t uncaught_ball;
  size_t *solution_rename;
  size_t query_sp_base;
  int query_depth;
  pair_visits compare_visits;
  void *file_target;
  char capture_buf[CAPTURE_BUF_SIZE];
  int capture_pos;
  int capture_starts[CAPTURE_STACK_MAX];
  int capture_sp;
  char tta_buf[CAPTURE_BUF_SIZE];
  int tta_pos;
  long long epoch_ms;

  bool in_query;
  bool in_callback;
  int32_t nvars;
  const char **varnames;
  trilog_term_t error;
  char *format_buf;
  size_t format_cap, format_len;
};

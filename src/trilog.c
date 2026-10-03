#include "trilog.h"
#include "arena.h"
#include "ctx.h"
#include "heap.h"
#include "io.h"
#include "mem.h"
#include "parse.h"
#include "solve.h"
#include "term.h"
#include "version.h"
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>

static const trilog_term_t invalid_term = {(size_t)-1};

static void *libc_realloc(void *ud, void *p, size_t n) {
  (void)ud;
  return realloc(p, n);
}

static void libc_free(void *ud, void *p) {
  (void)ud;
  free(p);
}

static trilog_status_t unwound(trilog_t *t) {
  t->heap_top = 0;
  t->trail_top = 0;
  t->occurs_len = 0;
  t->template_marks_len = 0;
  t->template_cyclic = 0;
  t->sp = 0;
  t->query_sp_base = 0;
  t->query_depth = 0;
  t->catch_sp = 0;
  t->capture_sp = 0;
  t->capture_pos = 0;
  t->tta_pos = 0;
  t->print_depth = 0;
  t->solution_rename = NULL;
  t->pending_error_ball = (size_t)-1;
  t->uncaught_ball = (size_t)-1;
  t->P = NULL;
  t->consulting = NULL;
  t->in_query = false;
  t->in_callback = false;
  t->error = invalid_term;
  if (t->halted) {
    t->halted = false;
    return TRILOG_HALT;
  }
  if (t->aborted) {
    t->aborted = false;
    return TRILOG_ABORTED;
  }
  return TRILOG_ERROR;
}

trilog_t *trilog_new(const trilog_config_t *config) {
  trilog_config_t c = config ? *config : (trilog_config_t){0};
  if (!c.realloc != !c.free)
    return NULL;
  if (!c.realloc) {
    c.realloc = libc_realloc;
    c.free = libc_free;
  }
  trilog_t *t = c.realloc(c.alloc_ud, NULL, sizeof *t);
  if (!t)
    return NULL;
  memset(t, 0, sizeof *t);
  t->alloc_realloc = c.realloc;
  t->alloc_free = c.free;
  t->alloc_ud = c.alloc_ud;
  t->error = invalid_term;
  t->pending_error_ball = (size_t)-1;
  t->uncaught_ball = (size_t)-1;
  t->epoch_ms = -1;
  io_set(t, c.io);
  if (setjmp(t->fatal_jmp)) {
    trilog_free(t);
    return NULL;
  }
  heap_init(t);
  if (!consult_file(t, c.boot_path ? c.boot_path : "embedded:boot/core.pl")) {
    trilog_free(t);
    return NULL;
  }
  return t;
}

void trilog_free(trilog_t *t) {
  if (!t)
    return;
  for (int i = 0; i < MAX_OPEN_STREAMS; i++)
    stream_close(t, i);
  for (int i = 0; i < PRED_HASH_SIZE; i++)
    while (t->pred_hash[i]) {
      pred_bucket_t *next = t->pred_hash[i]->next;
      mem_free(t, t->pred_hash[i]->indices);
      mem_free(t, t->pred_hash[i]);
      t->pred_hash[i] = next;
    }
  mem_free(t, t->db);
  mem_free(t, t->consulted_decls);
  mem_free(t, t->dynamic_decls);
  mem_free(t, t->foreign);
  mem_free(t, t->stack);
  mem_free(t, t->catch_stack);
  pair_visits_free(t, &t->compare_visits);
  pair_visits_free(t, &t->unify_visits);
  pair_visits_free(t, &t->occurs_check_visits);
  mem_free(t, t->occurs_marks);
  mem_free(t, t->template_marks);
  mem_free(t, t->marked);
  mem_free(t, t->new_index);
  mem_free(t, t->trail_new_index);
  mem_free(t, t->catch_live);
  mem_free(t, t->new_catch_index);
  mem_free(t, t->heap);
  mem_free(t, t->trail);
  mem_free(t, t->atoms);
  arena_free(t);
  t->alloc_free(t->alloc_ud, t);
}

static trilog_status_t load(trilog_t *t, const char *path, const char *text) {
  if (t->in_query)
    return TRILOG_ERROR;
  t->in_query = true;
  if (setjmp(t->fatal_jmp))
    return unwound(t);
  bool ok = path ? consult_file(t, path) : consult_string(t, text);
  t->in_query = false;
  return ok ? TRILOG_TRUE : TRILOG_ERROR;
}

trilog_status_t trilog_load_file(trilog_t *t, const char *path) {
  return load(t, path, NULL);
}

trilog_status_t trilog_load_string(trilog_t *t, const char *text) {
  return load(t, NULL, text);
}

int trilog_halt_code(trilog_t *t) { return t->halt_code; }

const char *trilog_version(void) { return TRILOG_BUILD_VERSION; }

static bool register_parsed(trilog_t *t, const char *name, const char *types,
                            int32_t nin, int32_t nout, trilog_fn fn, void *ud) {
  if (setjmp(t->fatal_jmp)) {
    unwound(t);
    return false;
  }
  return foreign_register(t, name, types, nin, nout, fn, ud);
}

bool trilog_register(trilog_t *t, const char *name, const char *sig,
                     trilog_fn fn, void *ud) {
  if (!name || !sig || !fn || t->in_query)
    return false;
  char types[TRILOG_MAX_FOREIGN_ARGS + 1];
  int32_t n = 0, nin = -1;
  for (const char *p = sig; *p; p++) {
    if (*p == '>' && nin < 0) {
      nin = n;
      continue;
    }
    if ((*p != 'i' && *p != 'f' && *p != 'a') || n == TRILOG_MAX_FOREIGN_ARGS)
      return false;
    types[n++] = *p;
  }
  types[n] = '\0';
  if (nin < 0)
    nin = n;
  return register_parsed(t, name, types, nin, n - nin, fn, ud);
}

void trilog_set_io(trilog_t *t, const trilog_io_t *io) { io_set(t, io); }

void trilog_set_yield(trilog_t *t, trilog_yield_fn fn, unsigned every,
                      void *ud) {
  t->yield_fn = fn;
  t->yield_ud = ud;
  t->yield_every = every > 0 ? every : 1;
  t->yield_count = 0;
}

typedef struct {
  trilog_t *t;
  trilog_solution_fn on_solution;
  void *ud;
} solution_ctx;

static int forward_solution(void *ud, int has_more) {
  solution_ctx *c = ud;
  c->t->in_callback = true;
  bool more = c->on_solution(c->t, c->ud, has_more != 0);
  c->t->in_callback = false;
  return more;
}

trilog_status_t trilog_query(trilog_t *t, const char *goal,
                             trilog_solution_fn on_solution, void *ud) {
  t->error = invalid_term;
  if (t->in_query)
    return TRILOG_ERROR;
  t->in_query = true;
  if (setjmp(t->fatal_jmp))
    return unwound(t);
  tterm_t **goals;
  int32_t ngoals, nvars;
  const char **names;
  if (!parse_query(t, goal, &goals, &ngoals, &nvars, &names)) {
    t->in_query = false;
    return TRILOG_ERROR;
  }
  t->nvars = nvars;
  t->varnames = names;
  solution_ctx c = {t, on_solution, ud};
  query_result_t r = run_query(t, goals, ngoals, nvars, forward_solution, &c);
  t->in_query = false;
  switch (r) {
  case QUERY_TRUE:
    return TRILOG_TRUE;
  case QUERY_FALSE:
    return TRILOG_FALSE;
  case QUERY_ERROR:
    break;
  }
  t->error = (trilog_term_t){query_error_ball(t)};
  return TRILOG_ERROR;
}

static int32_t binding_slot(trilog_t *t, int i) {
  if (!t->in_callback || i < 0)
    return -1;
  for (int32_t v = 0; v < t->nvars; v++)
    if (query_binding(t, v) != (size_t)-1 && i-- == 0)
      return v;
  return -1;
}

int trilog_binding_count(trilog_t *t) {
  if (!t->in_callback)
    return 0;
  int n = 0;
  for (int32_t v = 0; v < t->nvars; v++)
    if (query_binding(t, v) != (size_t)-1)
      n++;
  return n;
}

const char *trilog_binding_name(trilog_t *t, int i) {
  int32_t v = binding_slot(t, i);
  return v < 0 ? NULL : t->varnames[v];
}

trilog_term_t trilog_binding_value(trilog_t *t, int i) {
  int32_t v = binding_slot(t, i);
  return v < 0 ? invalid_term : (trilog_term_t){query_binding(t, v)};
}

trilog_term_t trilog_error_term(trilog_t *t) { return t->error; }

static size_t resolve(trilog_t *t, trilog_term_t term) {
  if (term.ref >= heap_size(t))
    return (size_t)-1;
  return heap_deref(t, term.ref);
}

trilog_type_t trilog_term_type(trilog_t *t, trilog_term_t term) {
  size_t r = resolve(t, term);
  if (r == (size_t)-1)
    return TRILOG_INVALID;
  switch (t->heap[r].tag) {
  case TAG_REF:
    return TRILOG_VAR;
  case TAG_ATOM:
    return TRILOG_ATOM;
  case TAG_INT:
    return TRILOG_INT;
  case TAG_FLT:
    return TRILOG_FLOAT;
  case TAG_STR:
    return TRILOG_COMPOUND;
  case TAG_FUNCTOR:
    break;
  }
  return TRILOG_INVALID;
}

bool trilog_get_int(trilog_t *t, trilog_term_t term, int64_t *out) {
  if (trilog_term_type(t, term) != TRILOG_INT)
    return false;
  *out = t->heap[resolve(t, term)].as.ival;
  return true;
}

bool trilog_get_float(trilog_t *t, trilog_term_t term, double *out) {
  if (trilog_term_type(t, term) != TRILOG_FLOAT)
    return false;
  *out = t->heap[resolve(t, term)].as.fval;
  return true;
}

const char *trilog_get_atom(trilog_t *t, trilog_term_t term) {
  if (trilog_term_type(t, term) != TRILOG_ATOM)
    return NULL;
  return atom_name(t, t->heap[resolve(t, term)].as.atom_id);
}

bool trilog_get_functor(trilog_t *t, trilog_term_t term, const char **name,
                        int *arity) {
  if (trilog_term_type(t, term) != TRILOG_COMPOUND)
    return false;
  size_t f = t->heap[resolve(t, term)].as.ptr;
  *name = atom_name(t, t->heap[f].as.func.atom_id);
  *arity = t->heap[f].as.func.arity;
  return true;
}

bool trilog_get_arg(trilog_t *t, trilog_term_t term, int i,
                    trilog_term_t *out) {
  const char *name;
  int arity;
  if (!trilog_get_functor(t, term, &name, &arity) || i < 1 || i > arity)
    return false;
  *out = (trilog_term_t){t->heap[resolve(t, term)].as.ptr + (size_t)i};
  return true;
}

static void format_emit(trilog_t *t, const char *s) {
  size_t n = strlen(s);
  if (t->format_len < t->format_cap) {
    size_t room = t->format_cap - t->format_len;
    size_t copy = n < room ? n : room;
    memcpy(t->format_buf + t->format_len, s, copy);
  }
  t->format_len += n;
}

size_t trilog_format(trilog_t *t, trilog_term_t term, int flags, char *buf,
                     size_t cap) {
  size_t r = resolve(t, term);
  if (r == (size_t)-1) {
    if (cap > 0)
      buf[0] = '\0';
    return 0;
  }
  t->format_buf = buf;
  t->format_cap = cap;
  t->format_len = 0;
  print_term_via(t, r, (flags & TRILOG_FORMAT_QUOTED) != 0, format_emit);
  if (cap > 0)
    buf[t->format_len < cap ? t->format_len : cap - 1] = '\0';
  return t->format_len;
}

void trilog_usage(trilog_t *t, trilog_usage_t *out) {
  *out = (trilog_usage_t){
      .heap_cells = t->heap_top,
      .heap_capacity_cells = t->heap_cap,
      .heap_peak_cells = t->heap_peak,
      .heap_peak_bytes = t->heap_peak * sizeof(cell_t),
      .trail_entries = t->trail_top,
      .choicepoints = t->sp,
      .clauses = (size_t)(t->db_count - t->db_dead),
      .atoms = (size_t)t->atom_count,
      .arena_bytes = arena_bytes(t),
  };
}

#include "trilog.h"
#include "arena.h"
#include "ctx.h"
#include "heap.h"
#include "io.h"
#include "parse.h"
#include "solve.h"
#include "term.h"
#include <stdlib.h>
#include <string.h>

static const trilog_term_t invalid_term = {(size_t)-1};

trilog_t *trilog_new(const trilog_config_t *config) {
  trilog_t *t = calloc(1, sizeof *t);
  if (!t)
    return NULL;
  t->error = invalid_term;
  t->pending_error_ball = (size_t)-1;
  t->uncaught_ball = (size_t)-1;
  t->epoch_ms = -1;
  io_hooks_init_default(t);
  heap_init(t);
  const char *boot =
      config && config->boot_path ? config->boot_path : "embedded:boot/core.pl";
  if (!consult_file(t, boot)) {
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
      free(t->pred_hash[i]->indices);
      free(t->pred_hash[i]);
      t->pred_hash[i] = next;
    }
  free(t->db);
  free(t->consulted_decls);
  free(t->dynamic_decls);
  free(t->stack);
  free(t->catch_stack);
  pair_visits_free(&t->compare_visits);
  pair_visits_free(&t->unify_visits);
  pair_visits_free(&t->occurs_check_visits);
  free(t->occurs_marks);
  free(t->template_marks);
  free(t->marked);
  free(t->new_index);
  free(t->trail_new_index);
  free(t->catch_live);
  free(t->new_catch_index);
  free(t->heap);
  free(t->trail);
  free(t->atoms);
  arena_free(t);
  free(t);
}

bool trilog_load_file(trilog_t *t, const char *path) {
  if (t->in_query)
    return false;
  t->in_query = true;
  bool ok = consult_file(t, path);
  t->in_query = false;
  return ok;
}

bool trilog_load_string(trilog_t *t, const char *text) {
  if (t->in_query)
    return false;
  t->in_query = true;
  bool ok = consult_string(t, text);
  t->in_query = false;
  return ok;
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
  tterm_t **goals;
  int32_t ngoals, nvars;
  const char **names;
  if (!parse_query(t, goal, &goals, &ngoals, &nvars, &names))
    return TRILOG_ERROR;
  t->in_query = true;
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
  out->heap_peak_cells = heap_peak_size(t);
  out->heap_peak_bytes = heap_peak_size(t) * sizeof(cell_t);
}

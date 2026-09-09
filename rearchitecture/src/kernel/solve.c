#include "solve.h"
#include "arena.h"
#include "gc.h"
#include "heap.h"
#include "io.h"
#include "parse.h"
#include "streams.h"
#include "unify.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static clause_t *db = NULL;
static int32_t db_count = 0, db_cap = 0;

#define PRED_HASH_SIZE 1024
typedef struct pred_bucket {
  int32_t pred_id, pred_arity;
  int32_t *indices;
  int32_t count, cap;
  struct pred_bucket *next;
} pred_bucket_t;
static pred_bucket_t *pred_hash[PRED_HASH_SIZE];

static uint32_t pred_hash_slot(int32_t pred_id, int32_t pred_arity) {
  uint32_t h = (uint32_t)pred_id * 2654435761u + (uint32_t)pred_arity * 40503u;
  return h % PRED_HASH_SIZE;
}

static pred_bucket_t *pred_bucket_find(int32_t pred_id, int32_t pred_arity) {
  for (pred_bucket_t *b = pred_hash[pred_hash_slot(pred_id, pred_arity)]; b;
       b = b->next)
    if (b->pred_id == pred_id && b->pred_arity == pred_arity)
      return b;
  return NULL;
}

static pred_bucket_t *pred_bucket_find_or_create(int32_t pred_id,
                                                 int32_t pred_arity) {
  pred_bucket_t *b = pred_bucket_find(pred_id, pred_arity);
  if (b)
    return b;
  b = calloc(1, sizeof(pred_bucket_t));
  b->pred_id = pred_id;
  b->pred_arity = pred_arity;
  uint32_t slot = pred_hash_slot(pred_id, pred_arity);
  b->next = pred_hash[slot];
  pred_hash[slot] = b;
  return b;
}

static void pred_bucket_grow_if_needed(pred_bucket_t *b) {
  if (b->count < b->cap)
    return;
  b->cap = b->cap ? b->cap * 2 : 4;
  b->indices = realloc(b->indices, (size_t)b->cap * sizeof(int32_t));
}

static void pred_bucket_add_index(int32_t pred_id, int32_t pred_arity,
                                  int32_t idx) {
  pred_bucket_t *b = pred_bucket_find_or_create(pred_id, pred_arity);
  pred_bucket_grow_if_needed(b);
  b->indices[b->count++] = idx;
}

static void pred_bucket_add_index_front(int32_t pred_id, int32_t pred_arity,
                                        int32_t idx) {
  pred_bucket_t *b = pred_bucket_find_or_create(pred_id, pred_arity);
  pred_bucket_grow_if_needed(b);
  memmove(&b->indices[1], &b->indices[0], (size_t)b->count * sizeof(int32_t));
  b->indices[0] = idx;
  b->count++;
}

static void pred_bucket_remove_index(int32_t pred_id, int32_t pred_arity,
                                     int32_t idx) {
  pred_bucket_t *b = pred_bucket_find(pred_id, pred_arity);
  if (!b)
    return;
  for (int32_t i = 0; i < b->count; i++)
    if (b->indices[i] == idx) {
      memmove(&b->indices[i], &b->indices[i + 1],
              (size_t)(b->count - i - 1) * sizeof(int32_t));
      b->count--;
      return;
    }
}

static void pred_index_fixup_insert_at(int32_t at) {
  for (int i = 0; i < PRED_HASH_SIZE; i++)
    for (pred_bucket_t *b = pred_hash[i]; b; b = b->next)
      for (int32_t j = 0; j < b->count; j++)
        if (b->indices[j] >= at)
          b->indices[j]++;
}
static void pred_index_fixup_remove_at(int32_t at) {
  for (int i = 0; i < PRED_HASH_SIZE; i++)
    for (pred_bucket_t *b = pred_hash[i]; b; b = b->next)
      for (int32_t j = 0; j < b->count; j++)
        if (b->indices[j] > at)
          b->indices[j]--;
}

static frame_t *stack = NULL;
static size_t stack_cap = 0, sp = 0;

static catch_frame_t *catch_stack = NULL;
static size_t catch_sp = 0, catch_cap = 0;

catch_frame_t *catch_stack_array(void) { return catch_stack; }
size_t catch_stack_size(void) { return catch_sp; }

static size_t catch_stack_push(catch_frame_t f) {
  if (catch_sp >= catch_cap) {
    catch_cap = catch_cap ? catch_cap * 2 : 16;
    catch_stack = realloc(catch_stack, catch_cap * sizeof(catch_frame_t));
  }
  catch_stack[catch_sp] = f;
  return catch_sp++;
}

static int32_t atom_true, atom_comma, atom_dot, atom_nil;
// Interned once here, not per call site - atom_intern is a linear scan.
static int32_t atom_ruleop, atom_slash, atom_error, atom_instantiation_error,
    atom_type_error, atom_existence_error, atom_stream, atom_uncatch, atom_cut,
    atom_catch, atom_throw, atom_assertz, atom_assert, atom_asserta,
    atom_retract, atom_call;
// eval_arith operator names.
static int32_t atom_plus, atom_minus, atom_star, atom_intdiv, atom_mod,
    atom_min, atom_max, atom_abs, atom_sign, atom_floor, atom_ceiling,
    atom_round, atom_truncate;
// op_lookup_infix/prefix names
static int32_t atom_op_pred, atom_optype_xfx, atom_optype_xfy, atom_optype_yfx,
    atom_optype_fx, atom_optype_fy;
// dispatch_builtin names.
static int32_t atom_is, atom_unify_op, atom_lt, atom_gt, atom_put_code,
    atom_get_code, atom_write_raw, atom_open, atom_close, atom_consult,
    atom_dynamic, atom_capture_start, atom_capture_stop, atom_var, atom_kw_atom,
    atom_integer, atom_kw_float, atom_compound, atom_functor, atom_arg,
    atom_univ, atom_atom_codes, atom_number_codes, atom_mode_read,
    atom_mode_write, atom_mode_append, atom_copy_term, atom_term_to_atom,
    atom_atom_to_term, atom_clause_candidates, atom_choice_mark, atom_cut_to,
    atom_arith_le, atom_arith_ge, atom_arith_eq, atom_arith_ne, atom_term_eq,
    atom_term_ne, atom_term_lt, atom_term_gt, atom_term_le, atom_term_ge,
    atom_var_addr, atom_fail, atom_false, atom_halt, atom_flush_output;

static size_t pending_error_ball = (size_t)-1;

static size_t make_error(size_t formal) {
  size_t args[2] = {formal, heap_new_var()};
  return heap_new_struct(atom_error, 2, args);
}
static size_t make_instantiation_error(void) {
  return make_error(heap_new_atom(atom_instantiation_error));
}
static size_t make_type_error(const char *type, size_t culprit) {
  size_t args[2] = {heap_new_atom(atom_intern(type)), culprit};
  return make_error(heap_new_struct(atom_type_error, 2, args));
}
static size_t make_existence_error_term(const char *obj_type, size_t culprit) {
  size_t args[2] = {heap_new_atom(atom_intern(obj_type)), culprit};
  return make_error(heap_new_struct(atom_existence_error, 2, args));
}
static size_t make_existence_error(const char *obj_type, int32_t pred_id,
                                   int32_t pred_arity) {
  size_t pi_args[2] = {heap_new_atom(pred_id), heap_new_int(pred_arity)};
  return make_existence_error_term(obj_type,
                                   heap_new_struct(atom_slash, 2, pi_args));
}
void solve_init(void) {
  atom_true = atom_intern("true");
  atom_comma = atom_intern(",");
  atom_dot = atom_intern(".");
  atom_nil = atom_intern("[]");
  atom_ruleop = atom_intern(":-");
  atom_slash = atom_intern("/");
  atom_error = atom_intern("error");
  atom_instantiation_error = atom_intern("instantiation_error");
  atom_type_error = atom_intern("type_error");
  atom_existence_error = atom_intern("existence_error");
  atom_stream = atom_intern("$stream");
  atom_uncatch = atom_intern("$$uncatch");
  atom_cut = atom_intern("$$cut");
  atom_catch = atom_intern("catch");
  atom_throw = atom_intern("throw");
  atom_assertz = atom_intern("assertz");
  atom_assert = atom_intern("assert");
  atom_asserta = atom_intern("asserta");
  atom_retract = atom_intern("retract");
  atom_call = atom_intern("call");
  atom_plus = atom_intern("+");
  atom_minus = atom_intern("-");
  atom_star = atom_intern("*");
  atom_intdiv = atom_intern("//");
  atom_mod = atom_intern("mod");
  atom_min = atom_intern("min");
  atom_max = atom_intern("max");
  atom_abs = atom_intern("abs");
  atom_sign = atom_intern("sign");
  atom_floor = atom_intern("floor");
  atom_ceiling = atom_intern("ceiling");
  atom_round = atom_intern("round");
  atom_truncate = atom_intern("truncate");
  atom_op_pred = atom_intern("$$op");
  atom_optype_xfx = atom_intern("xfx");
  atom_optype_xfy = atom_intern("xfy");
  atom_optype_yfx = atom_intern("yfx");
  atom_optype_fx = atom_intern("fx");
  atom_optype_fy = atom_intern("fy");
  atom_is = atom_intern("is");
  atom_unify_op = atom_intern("=");
  atom_lt = atom_intern("<");
  atom_gt = atom_intern(">");
  atom_put_code = atom_intern("put_code");
  atom_get_code = atom_intern("get_code");
  atom_write_raw = atom_intern("$$write_raw");
  atom_open = atom_intern("open");
  atom_close = atom_intern("close");
  atom_consult = atom_intern("consult");
  atom_dynamic = atom_intern("dynamic");
  atom_capture_start = atom_intern("$$capture_start");
  atom_capture_stop = atom_intern("$$capture_stop");
  atom_fail = atom_intern("fail");
  atom_false = atom_intern("false");
  atom_halt = atom_intern("halt");
  atom_flush_output = atom_intern("flush_output");
  atom_var = atom_intern("var");
  atom_kw_atom = atom_intern("atom");
  atom_integer = atom_intern("integer");
  atom_kw_float = atom_intern("float");
  atom_compound = atom_intern("compound");
  atom_functor = atom_intern("functor");
  atom_arg = atom_intern("arg");
  atom_univ = atom_intern("=..");
  atom_var_addr = atom_intern("$$var_addr");
  atom_atom_codes = atom_intern("atom_codes");
  atom_number_codes = atom_intern("number_codes");
  atom_mode_read = atom_intern("read");
  atom_mode_write = atom_intern("write");
  atom_mode_append = atom_intern("append");
  atom_copy_term = atom_intern("copy_term");
  atom_term_to_atom = atom_intern("term_to_atom");
  atom_atom_to_term = atom_intern("atom_to_term");
  atom_clause_candidates = atom_intern("$$clause_candidates");
  atom_choice_mark = atom_intern("$$choice_mark");
  atom_cut_to = atom_intern("$$cut_to");
  atom_arith_le = atom_intern("=<");
  atom_arith_ge = atom_intern(">=");
  atom_arith_eq = atom_intern("=:=");
  atom_arith_ne = atom_intern("=\\=");
  atom_term_eq = atom_intern("==");
  atom_term_ne = atom_intern("\\==");
  atom_term_lt = atom_intern("@<");
  atom_term_gt = atom_intern("@>");
  atom_term_le = atom_intern("@=<");
  atom_term_ge = atom_intern("@>=");
}

static idx_key_t key_of_template(tterm_t *head) {
  idx_key_t k = {.pred_id = -1, .pred_arity = 0, .kind = IDX_ANY};
  if (head->tag == T_ATOM) {
    k.pred_id = head->as.atom_id;
    return k;
  }
  if (head->tag != T_STR)
    return k;
  k.pred_id = head->as.str.atom_id;
  k.pred_arity = head->as.str.arity;
  tterm_t *a0 = head->as.str.args[0];
  switch (a0->tag) {
  case T_VAR:
  case T_FLT:
    return k;
  case T_ATOM:
    k.kind = IDX_ATOM;
    k.atom_id = a0->as.atom_id;
    return k;
  case T_INT:
    k.kind = IDX_INT;
    k.ival = a0->as.ival;
    return k;
  case T_STR:
    k.kind = IDX_STRUCT;
    k.atom_id = a0->as.str.atom_id;
    k.arity = a0->as.str.arity;
    return k;
  }
  return k;
}

static idx_key_t key_of_goal(size_t goal) {
  idx_key_t k = {.pred_id = -1, .pred_arity = 0, .kind = IDX_ANY};
  size_t g = heap_deref(goal);
  if (heap[g].tag == TAG_ATOM) {
    k.pred_id = heap[g].as.atom_id;
    return k;
  }
  if (heap[g].tag != TAG_STR)
    return k;
  size_t f = heap[g].as.ptr;
  k.pred_id = heap[f].as.func.atom_id;
  k.pred_arity = heap[f].as.func.arity;
  size_t a0 = heap_deref(f + 1);
  switch (heap[a0].tag) {
  case TAG_REF:
  case TAG_FLT:
    return k;
  case TAG_ATOM:
    k.kind = IDX_ATOM;
    k.atom_id = heap[a0].as.atom_id;
    return k;
  case TAG_INT:
    k.kind = IDX_INT;
    k.ival = heap[a0].as.ival;
    return k;
  case TAG_STR: {
    size_t af = heap[a0].as.ptr;
    k.kind = IDX_STRUCT;
    k.atom_id = heap[af].as.func.atom_id;
    k.arity = heap[af].as.func.arity;
    return k;
  }
  case TAG_FUNCTOR:
    return k;
  }
  return k;
}

static int keys_conflict(idx_key_t a, idx_key_t b) {
  if (a.pred_id != b.pred_id || a.pred_arity != b.pred_arity)
    return 1;
  if (a.kind == IDX_ANY || b.kind == IDX_ANY)
    return 0;
  if (a.kind != b.kind)
    return 1;
  switch (a.kind) {
  case IDX_ATOM:
    return a.atom_id != b.atom_id;
  case IDX_INT:
    return a.ival != b.ival;
  case IDX_STRUCT:
    return a.atom_id != b.atom_id || a.arity != b.arity;
  default:
    return 0;
  }
}

static int no_more_candidates(int32_t from_idx, idx_key_t caller_key) {
  for (int32_t k = from_idx; k < db_count; k++)
    if (!keys_conflict(caller_key, db[k].key))
      return 0;
  return 1;
}

static void db_ensure_cap(void) {
  if (db_count < db_cap)
    return;
  db_cap = db_cap ? db_cap * 2 : 8;
  db = realloc(db, (size_t)db_cap * sizeof(clause_t));
}

void db_add(tterm_t *head, tterm_t **body, int32_t nbody, int32_t nvars) {
  db_ensure_cap();
  idx_key_t key = key_of_template(head);
  int32_t idx = db_count++;
  db[idx] = (clause_t){
      .head = head, .body = body, .nbody = nbody, .nvars = nvars, .key = key};
  pred_bucket_add_index(key.pred_id, key.pred_arity, idx);
}

static void db_fixup_choice_points_insert_at(int32_t at) {
  for (size_t i = 0; i < sp; i++)
    if (stack[i].clause_idx >= at)
      stack[i].clause_idx++;
}
static void db_fixup_choice_points_remove_at(int32_t at) {
  for (size_t i = 0; i < sp; i++)
    if (stack[i].clause_idx > at)
      stack[i].clause_idx--;
}

static void db_add_front(tterm_t *head, tterm_t **body, int32_t nbody,
                         int32_t nvars) {
  db_ensure_cap();
  memmove(&db[1], &db[0], (size_t)db_count * sizeof(clause_t));
  db_count++;
  idx_key_t key = key_of_template(head);
  db[0] = (clause_t){
      .head = head, .body = body, .nbody = nbody, .nvars = nvars, .key = key};
  db_fixup_choice_points_insert_at(0);
  pred_index_fixup_insert_at(0);
  pred_bucket_add_index_front(key.pred_id, key.pred_arity, 0);
}

static void db_remove_at(int32_t idx) {
  pred_bucket_remove_index(db[idx].key.pred_id, db[idx].key.pred_arity, idx);
  memmove(&db[idx], &db[idx + 1],
          (size_t)(db_count - idx - 1) * sizeof(clause_t));
  db_count--;
  db_fixup_choice_points_remove_at(idx);
  pred_index_fixup_remove_at(idx);
}

// boot/core.pl declares fail/0 and false/0 this way
typedef struct {
  int32_t pred_id;
  int32_t pred_arity;
} dyn_decl_t;
static dyn_decl_t *dynamic_decls = NULL;
static int32_t dynamic_count = 0, dynamic_cap = 0;

static void dynamic_declare(int32_t pred_id, int32_t pred_arity) {
  if (dynamic_count >= dynamic_cap) {
    dynamic_cap = dynamic_cap ? dynamic_cap * 2 : 8;
    dynamic_decls =
        realloc(dynamic_decls, (size_t)dynamic_cap * sizeof(dyn_decl_t));
  }
  dynamic_decls[dynamic_count++] = (dyn_decl_t){pred_id, pred_arity};
}

static int is_dynamic(int32_t pred_id, int32_t pred_arity) {
  for (int32_t i = 0; i < dynamic_count; i++)
    if (dynamic_decls[i].pred_id == pred_id &&
        dynamic_decls[i].pred_arity == pred_arity)
      return 1;
  return 0;
}

static void stack_push(frame_t f) {
  if (sp >= stack_cap) {
    stack_cap = stack_cap ? stack_cap * 2 : 64;
    stack = realloc(stack, stack_cap * sizeof(frame_t));
  }
  stack[sp++] = f;
}

static size_t build_conj_tail(size_t *goals, int32_t n, size_t tail) {
  size_t acc = tail;
  for (int32_t i = n - 1; i >= 0; i--) {
    size_t args[2] = {goals[i], acc};
    acc = heap_new_struct(atom_comma, 2, args);
  }
  return acc;
}

static size_t body_as_term(size_t *goals, int32_t n) {
  if (n == 0)
    return heap_new_atom(atom_true);
  if (n == 1)
    return goals[0];
  return build_conj_tail(goals, n - 1, goals[n - 1]);
}

static void rename_init(size_t *rename, int32_t n);

static size_t fresh_copy_term(tterm_t *t, int32_t nvars) {
  size_t rn[nvars > 0 ? nvars : 1];
  rename_init(rn, nvars);
  return heap_copy(t, rn, 0);
}

static void fresh_copy_clause(clause_t *c, size_t *head_out, size_t *body_out) {
  size_t rn[c->nvars > 0 ? c->nvars : 1];
  rename_init(rn, c->nvars);
  *head_out = heap_copy(c->head, rn, 0);
  size_t bodies[c->nbody > 0 ? c->nbody : 1];
  for (int32_t j = 0; j < c->nbody; j++)
    bodies[j] = heap_copy(c->body[j], rn, 0);
  *body_out = body_as_term(bodies, c->nbody);
}

static void decompose(size_t cn, size_t *first, size_t *rest) {
  size_t d = heap_deref(cn);
  if (heap[d].tag == TAG_STR) {
    size_t f = heap[d].as.ptr;
    if (heap[f].as.func.atom_id == atom_comma && heap[f].as.func.arity == 2) {
      // deref, or rest re-wraps in one more indirection every call, forever
      *first = heap_deref(f + 1);
      *rest = heap_deref(f + 2);
      return;
    }
  }
  *first = d;
  *rest = heap_new_atom(atom_true);
}

static int32_t heap_flatten_conj(size_t t, size_t *out, int32_t max) {
  int32_t n = 0;
  size_t d = heap_deref(t);
  while (n < max - 1) {
    if (heap[d].tag != TAG_STR)
      break;
    size_t f = heap[d].as.ptr;
    if (heap[f].as.func.atom_id != atom_comma || heap[f].as.func.arity != 2)
      break;
    out[n++] = heap_deref(f + 1);
    d = heap_deref(f + 2);
  }
  out[n++] = d;
  return n;
}

#define MAX_ASSERT_GOALS 64

static void split_clause(size_t clause, size_t *head_out, size_t *body_out,
                         int32_t *nbody_out) {
  size_t d = heap_deref(clause);
  if (heap[d].tag == TAG_STR) {
    size_t f = heap[d].as.ptr;
    if (heap[f].as.func.atom_id == atom_ruleop && heap[f].as.func.arity == 2) {
      *head_out = heap_deref(f + 1);
      *nbody_out =
          heap_flatten_conj(heap_deref(f + 2), body_out, MAX_ASSERT_GOALS);
      return;
    }
  }
  *head_out = d;
  *nbody_out = 0;
}

static void split_clause_whole(size_t clause, size_t *head_out,
                               size_t *body_out) {
  size_t d = heap_deref(clause);
  if (heap[d].tag == TAG_STR) {
    size_t f = heap[d].as.ptr;
    if (heap[f].as.func.atom_id == atom_ruleop && heap[f].as.func.arity == 2) {
      *head_out = heap_deref(f + 1);
      *body_out = heap_deref(f + 2);
      return;
    }
  }
  *head_out = d;
  *body_out = heap_new_atom(atom_true);
}

static int64_t eval_arith(size_t r, int *ok) {
  r = heap_deref(r);
  if (heap[r].tag == TAG_REF) {
    pending_error_ball = make_instantiation_error();
    *ok = 0;
    return 0;
  }
  if (heap[r].tag == TAG_INT)
    return heap[r].as.ival;
  if (heap[r].tag == TAG_STR) {
    size_t f = heap[r].as.ptr;
    int32_t arity = heap[f].as.func.arity;
    int32_t id = heap[f].as.func.atom_id;
    if (arity == 2) {
      int64_t a = eval_arith(f + 1, ok);
      int64_t b = *ok ? eval_arith(f + 2, ok) : 0;
      if (!*ok)
        return 0;
      if (id == atom_plus)
        return a + b;
      if (id == atom_minus)
        return a - b;
      if (id == atom_star)
        return a * b;
      if (id == atom_slash || id == atom_intdiv || id == atom_mod) {
        if (b == 0) {
          *ok = 0;
          return 0;
        } // would be a C-level SIGFPE otherwise
        if (id == atom_mod)
          return ((a % b) + b) % b; // ISO: result takes the sign of the divisor
        return a / b;
      }
      if (id == atom_min)
        return a < b ? a : b;
      if (id == atom_max)
        return a > b ? a : b;
    } else if (arity == 1) {
      int64_t a = eval_arith(f + 1, ok);
      if (!*ok)
        return 0;
      if (id == atom_minus)
        return -a;
      if (id == atom_plus)
        return a;
      if (id == atom_abs)
        return a < 0 ? -a : a;
      if (id == atom_sign)
        return (a > 0) - (a < 0);
      if (id == atom_floor || id == atom_ceiling || id == atom_round ||
          id == atom_truncate)
        return a;
    }
    pending_error_ball = make_type_error(
        "evaluable",
        heap_new_struct(atom_slash, 2,
                        (size_t[2]){heap_new_atom(heap[f].as.func.atom_id),
                                    heap_new_int(arity)}));
    *ok = 0;
    return 0;
  }
  if (heap[r].tag == TAG_ATOM) {
    pending_error_ball = make_type_error(
        "evaluable",
        heap_new_struct(
            atom_slash, 2,
            (size_t[2]){heap_new_atom(heap[r].as.atom_id), heap_new_int(0)}));
    *ok = 0;
    return 0;
  }
  *ok = 0;
  return 0;
}

static size_t codes_from_cstr(const char *s) {
  size_t acc = heap_new_atom(atom_nil);
  size_t n = strlen(s);
  for (size_t i = n; i-- > 0;) {
    size_t args[2] = {heap_new_int((unsigned char)s[i]), acc};
    acc = heap_new_struct(atom_dot, 2, args);
  }
  return acc;
}

static int cstr_from_codes(size_t list, char *buf, size_t bufcap) {
  size_t d = heap_deref(list);
  size_t n = 0;
  while (heap[d].tag != TAG_ATOM || heap[d].as.atom_id != atom_nil) {
    if (heap[d].tag != TAG_STR)
      return 0;
    size_t f = heap[d].as.ptr;
    if (heap[f].as.func.atom_id != atom_dot || heap[f].as.func.arity != 2)
      return 0;
    size_t h = heap_deref(f + 1);
    if (heap[h].tag != TAG_INT)
      return 0;
    if (n + 1 >= bufcap)
      return 0;
    buf[n++] = (char)heap[h].as.ival;
    d = heap_deref(f + 2);
  }
  buf[n] = '\0';
  return 1;
}

static int term_compare(size_t a, size_t b) {
  a = heap_deref(a);
  b = heap_deref(b);
  if (a == b)
    return 0;
  int ra = heap[a].tag == TAG_REF                               ? 0
           : (heap[a].tag == TAG_INT || heap[a].tag == TAG_FLT) ? 1
           : heap[a].tag == TAG_ATOM                            ? 2
                                                                : 3;
  int rb = heap[b].tag == TAG_REF                               ? 0
           : (heap[b].tag == TAG_INT || heap[b].tag == TAG_FLT) ? 1
           : heap[b].tag == TAG_ATOM                            ? 2
                                                                : 3;
  if (ra != rb)
    return ra < rb ? -1 : 1;
  switch (ra) {
  case 0:
    return a < b ? -1 : 1;
  case 1: {
    double av =
        heap[a].tag == TAG_INT ? (double)heap[a].as.ival : heap[a].as.fval;
    double bv =
        heap[b].tag == TAG_INT ? (double)heap[b].as.ival : heap[b].as.fval;
    return av < bv ? -1 : (av > bv ? 1 : 0);
  }
  case 2: {
    if (heap[a].as.atom_id == heap[b].as.atom_id)
      return 0;
    int c =
        strcmp(atom_name(heap[a].as.atom_id), atom_name(heap[b].as.atom_id));
    return c < 0 ? -1 : 1;
  }
  default: {
    size_t af = heap[a].as.ptr, bf = heap[b].as.ptr;
    int32_t aa = heap[af].as.func.arity, ba = heap[bf].as.func.arity;
    if (aa != ba)
      return aa < ba ? -1 : 1;
    int32_t af_id = heap[af].as.func.atom_id, bf_id = heap[bf].as.func.atom_id;
    if (af_id != bf_id) {
      int nc = strcmp(atom_name(af_id), atom_name(bf_id));
      return nc < 0 ? -1 : 1;
    }
    for (int32_t i = 1; i <= aa; i++) {
      int c = term_compare(af + i, bf + i);
      if (c != 0)
        return c;
    }
    return 0;
  }
  }
}

static int resolve_stream_id(size_t arg, int *id_out) {
  size_t s = heap_deref(arg);
  if (heap[s].tag != TAG_STR)
    return 0;
  size_t sf = heap[s].as.ptr;
  if (heap[sf].as.func.atom_id != atom_stream || heap[sf].as.func.arity != 1)
    return 0;
  size_t idv = heap_deref(sf + 1);
  if (heap[idv].tag != TAG_INT)
    return 0;
  *id_out = (int)heap[idv].as.ival;
  return 1;
}

static void *file_target;
static void emit_to_file(const char *str) { io_file_write(file_target, str); }

enum { OUT_STDOUT, OUT_STDERR, OUT_FILE };

static int resolve_write_target(size_t target, int *kind_out,
                                void **handle_out) {
  if (heap[target].tag == TAG_INT) {
    int64_t n = heap[target].as.ival;
    if (n == 0) {
      *kind_out = OUT_STDOUT;
      return 1;
    }
    if (n == 1) {
      *kind_out = OUT_STDERR;
      return 1;
    }
    return 0;
  }
  int id;
  void *h;
  if (!resolve_stream_id(target, &id) || !(h = stream_handle(id)))
    return 0;
  *kind_out = OUT_FILE;
  *handle_out = h;
  return 1;
}

// with_output_to/2's C half (see boot/core.pl). Not reentrant: a nested
// with_output_to before the outer's $$capture_stop mixes both into one buffer.
#define CAPTURE_BUF_SIZE 4096
static char capture_buf[CAPTURE_BUF_SIZE];
static int capture_pos;
static io_hooks_t capture_saved;
static void capture_write_str(const char *str, void *ud) {
  (void)ud;
  int len = (int)strlen(str);
  int rem = CAPTURE_BUF_SIZE - capture_pos - 1;
  if (len > rem)
    len = rem;
  if (len > 0) {
    memcpy(capture_buf + capture_pos, str, (size_t)len);
    capture_pos += len;
    capture_buf[capture_pos] = '\0';
  }
}

static char tta_buf[CAPTURE_BUF_SIZE];
static int tta_pos;
static void tta_emit(const char *str) {
  int len = (int)strlen(str);
  int rem = CAPTURE_BUF_SIZE - tta_pos - 1;
  if (len > rem)
    len = rem;
  if (len > 0) {
    memcpy(tta_buf + tta_pos, str, (size_t)len);
    tta_pos += len;
    tta_buf[tta_pos] = '\0';
  }
}

static int dispatch_builtin(size_t goal, int *ok) {
  size_t g = heap_deref(goal);
  size_t f = 0;
  int32_t arity;
  int32_t id;
  if (heap[g].tag == TAG_ATOM) {
    arity = 0;
    id = heap[g].as.atom_id;
  } else if (heap[g].tag == TAG_STR) {
    f = heap[g].as.ptr;
    arity = heap[f].as.func.arity;
    id = heap[f].as.func.atom_id;
  } else {
    return 0;
  }

  if (arity == 0 && (id == atom_fail || id == atom_false)) {
    *ok = 0;
    return 1;
  }

  if (arity == 1 && id == atom_halt) {
    size_t d = heap_deref(f + 1);
    if (heap[d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    exit((int)heap[d].as.ival);
  }

  // flush_output/0 always flushes stdout specifically (not whichever stream
  // write/2 last targeted) - ISO's default.
  if (arity == 0 && id == atom_flush_output) {
    fflush(stdout);
    *ok = 1;
    return 1;
  }

  if (arity == 2 && id == atom_is) {
    int aok = 1;
    int64_t v = eval_arith(f + 2, &aok);
    *ok = aok && unify(f + 1, heap_new_int(v));
    return 1;
  }
  if (arity == 2 && id == atom_unify_op) {
    *ok = unify(f + 1, f + 2);
    return 1;
  }
  if (arity == 2 &&
      (id == atom_lt || id == atom_gt || id == atom_arith_le ||
       id == atom_arith_ge || id == atom_arith_eq || id == atom_arith_ne)) {
    int aok = 1;
    int64_t a = eval_arith(f + 1, &aok);
    int64_t b = aok ? eval_arith(f + 2, &aok) : 0;
    if (!aok) {
      *ok = 0;
      return 1;
    }
    if (id == atom_lt)
      *ok = a < b;
    else if (id == atom_gt)
      *ok = a > b;
    else if (id == atom_arith_le)
      *ok = a <= b;
    else if (id == atom_arith_ge)
      *ok = a >= b;
    else if (id == atom_arith_eq)
      *ok = a == b;
    else
      *ok = a != b;
    return 1;
  }
  if (arity == 2 &&
      (id == atom_term_eq || id == atom_term_ne || id == atom_term_lt ||
       id == atom_term_gt || id == atom_term_le || id == atom_term_ge)) {
    int c = term_compare(f + 1, f + 2);
    if (id == atom_term_eq)
      *ok = c == 0;
    else if (id == atom_term_ne)
      *ok = c != 0;
    else if (id == atom_term_lt)
      *ok = c < 0;
    else if (id == atom_term_gt)
      *ok = c > 0;
    else if (id == atom_term_le)
      *ok = c <= 0;
    else
      *ok = c >= 0;
    return 1;
  }
  if (arity == 1 && id == atom_put_code) {
    size_t a = heap_deref(f + 1);
    char c[2] = {(char)heap[a].as.ival, '\0'};
    io_write_str(c);
    *ok = 1;
    return 1;
  }
  if (arity == 1 && id == atom_get_code) {
    int c = io_read_char();
    *ok = unify(f + 1, heap_new_int(c == -1 ? -1 : c));
    return 1;
  }
  if (arity == 3 && id == atom_write_raw) {
    size_t target = heap_deref(f + 1);
    int quoted = heap[heap_deref(f + 3)].as.ival != 0;
    int kind;
    void *h;
    if (!resolve_write_target(target, &kind, &h)) {
      *ok = 0;
      return 1;
    }
    if (kind == OUT_STDOUT)
      print_term_via(f + 2, quoted, io_write_str);
    else if (kind == OUT_STDERR)
      print_term_via(f + 2, quoted, io_write_err);
    else {
      file_target = h;
      print_term_via(f + 2, quoted, emit_to_file);
    }
    *ok = 1;
    return 1;
  }
  if (arity == 3 && id == atom_open) {
    size_t path_d = heap_deref(f + 1);
    size_t mode_d = heap_deref(f + 2);
    if (heap[path_d].tag != TAG_ATOM || heap[mode_d].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    int32_t mode_id = heap[mode_d].as.atom_id;
    const char *fmode = mode_id == atom_mode_read     ? "r"
                        : mode_id == atom_mode_write  ? "w"
                        : mode_id == atom_mode_append ? "a"
                                                      : NULL;
    if (!fmode) {
      *ok = 0;
      return 1;
    }
    int stream_id = stream_open(atom_name(heap[path_d].as.atom_id), fmode);
    if (stream_id < 0) {
      *ok = 0;
      return 1;
    }
    size_t id_arg[1] = {heap_new_int(stream_id)};
    *ok = unify(f + 3, heap_new_struct(atom_stream, 1, id_arg));
    return 1;
  }
  if (arity == 1 && id == atom_close) {
    int id;
    if (!resolve_stream_id(f + 1, &id)) {
      *ok = 0;
      return 1;
    }
    stream_close(id);
    *ok = 1;
    return 1;
  }
  // Fragile: a directive in the consulted file runs via a nested
  // run_query while this one is still on the C stack, and sp is global.
  if (arity == 1 && id == atom_consult) {
    size_t path_d = heap_deref(f + 1);
    if (heap[path_d].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    *ok = consult_file(atom_name(heap[path_d].as.atom_id));
    return 1;
  }
  if (arity == 1 && id == atom_dynamic) {
    size_t d = heap_deref(f + 1);
    if (heap[d].tag != TAG_STR) {
      *ok = 0;
      return 1;
    }
    size_t df = heap[d].as.ptr;
    if (heap[df].as.func.atom_id != atom_slash || heap[df].as.func.arity != 2) {
      *ok = 0;
      return 1;
    }
    size_t name_d = heap_deref(df + 1);
    size_t arity_d = heap_deref(df + 2);
    if (heap[name_d].tag != TAG_ATOM || heap[arity_d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    dynamic_declare(heap[name_d].as.atom_id, (int32_t)heap[arity_d].as.ival);
    *ok = 1;
    return 1;
  }
  if (arity == 0 && id == atom_capture_start) {
    capture_saved = io_hooks_get();
    capture_pos = 0;
    capture_buf[0] = '\0';
    io_hooks_t tmp = capture_saved;
    tmp.write_str = capture_write_str;
    io_hooks_replace(tmp);
    *ok = 1;
    return 1;
  }
  if (arity == 1 && id == atom_capture_stop) {
    io_hooks_restore(capture_saved);
    *ok = unify(f + 1, heap_new_atom(atom_intern(capture_buf)));
    return 1;
  }
  if (arity == 2 && id == atom_copy_term) {
    int32_t nvars;
    tterm_t *tmpl = heap_to_template(f + 1, &nvars);
    size_t rn[nvars > 0 ? nvars : 1];
    rename_init(rn, nvars);
    *ok = unify(f + 2, heap_copy(tmpl, rn, 0));
    return 1;
  }
  if (arity == 2 && id == atom_clause_candidates) {
    idx_key_t want = key_of_goal(f + 1);
    size_t list = heap_new_atom(atom_nil);
    pred_bucket_t *bucket = pred_bucket_find(want.pred_id, want.pred_arity);
    for (int32_t bi = bucket ? bucket->count - 1 : -1; bi >= 0; bi--) {
      clause_t *c = &db[bucket->indices[bi]];
      if (keys_conflict(want, c->key))
        continue;
      size_t h2, b2;
      fresh_copy_clause(c, &h2, &b2);
      size_t pair_args[2] = {h2, b2};
      size_t pair = heap_new_struct(atom_minus, 2, pair_args);
      size_t cons_args[2] = {pair, list};
      list = heap_new_struct(atom_dot, 2, cons_args);
    }
    *ok = unify(f + 2, list);
    return 1;
  }
  if (arity == 1 && id == atom_choice_mark) {
    *ok = unify(f + 1, heap_new_int((int64_t)sp));
    return 1;
  }
  if (arity == 1 && id == atom_cut_to) {
    size_t mark_d = heap_deref(f + 1);
    if (heap[mark_d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    sp = (size_t)heap[mark_d].as.ival;
    *ok = 1;
    return 1;
  }
  if (arity == 2 && id == atom_term_to_atom) {
    size_t term_arg = heap_deref(f + 1);
    size_t atom_arg = heap_deref(f + 2);
    if (heap[term_arg].tag != TAG_REF) {
      tta_pos = 0;
      tta_buf[0] = '\0';
      print_term_via(term_arg, 1, tta_emit); // quoted, so it round-trips
      *ok = unify(atom_arg, heap_new_atom(atom_intern(tta_buf)));
      return 1;
    }
    if (heap[atom_arg].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    int32_t nvars;
    const char **names;
    tterm_t *t;
    if (!parse_term_from_string(atom_name(heap[atom_arg].as.atom_id), &t,
                                &nvars, &names)) {
      *ok = 0;
      return 1;
    }
    *ok = unify(term_arg, fresh_copy_term(t, nvars));
    return 1;
  }
  // Bindings is always []
  // TODO: this is fine for now, but not a complete impl
  if (arity == 3 && id == atom_atom_to_term) {
    size_t atom_arg = heap_deref(f + 1);
    if (heap[atom_arg].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    int32_t nvars;
    const char **names;
    tterm_t *t;
    if (!parse_term_from_string(atom_name(heap[atom_arg].as.atom_id), &t,
                                &nvars, &names)) {
      *ok = 0;
      return 1;
    }
    *ok = unify(f + 2, fresh_copy_term(t, nvars)) &&
          unify(f + 3, heap_new_atom(atom_nil));
    return 1;
  }

  if (arity == 1 &&
      (id == atom_var || id == atom_kw_atom || id == atom_integer ||
       id == atom_kw_float || id == atom_compound)) {
    tag_t t = heap[heap_deref(f + 1)].tag;
    if (id == atom_var)
      *ok = t == TAG_REF;
    else if (id == atom_kw_atom)
      *ok = t == TAG_ATOM;
    else if (id == atom_integer)
      *ok = t == TAG_INT;
    else if (id == atom_kw_float)
      *ok = t == TAG_FLT;
    else
      *ok = t == TAG_STR; // compound
    return 1;
  }

  if (arity == 3 && id == atom_functor) {
    size_t term = heap_deref(f + 1);
    if (heap[term].tag != TAG_REF) {
      size_t name_val, arity_val;
      if (heap[term].tag == TAG_STR) {
        size_t tf = heap[term].as.ptr;
        name_val = heap_new_atom(heap[tf].as.func.atom_id);
        arity_val = heap_new_int(heap[tf].as.func.arity);
      } else {
        name_val = term;
        arity_val = heap_new_int(0);
      }
      *ok = unify(f + 2, name_val) && unify(f + 3, arity_val);
      return 1;
    }
    size_t name_d = heap_deref(f + 2);
    size_t arity_d = heap_deref(f + 3);
    if (heap[arity_d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    int64_t ar = heap[arity_d].as.ival;
    if (ar == 0) {
      *ok = unify(term, name_d);
      return 1;
    }
    if (ar < 1 || ar > 255 || heap[name_d].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    size_t args[ar];
    for (int64_t i = 0; i < ar; i++)
      args[i] = heap_new_var();
    *ok = unify(term,
                heap_new_struct(heap[name_d].as.atom_id, (int32_t)ar, args));
    return 1;
  }
  if (arity == 3 && id == atom_arg) {
    size_t n_d = heap_deref(f + 1);
    size_t term = heap_deref(f + 2);
    if (heap[n_d].tag != TAG_INT || heap[term].tag != TAG_STR) {
      *ok = 0;
      return 1;
    }
    int64_t n = heap[n_d].as.ival;
    size_t tf = heap[term].as.ptr;
    if (n < 1 || n > heap[tf].as.func.arity) {
      *ok = 0;
      return 1;
    }
    *ok = unify(f + 3, tf + (size_t)n);
    return 1;
  }
  if (arity == 2 && id == atom_univ) {
    size_t term = heap_deref(f + 1);
    if (heap[term].tag != TAG_REF) {
      size_t list = heap_new_atom(atom_nil);
      if (heap[term].tag == TAG_STR) {
        size_t tf = heap[term].as.ptr;
        int32_t tarity = heap[tf].as.func.arity;
        for (int32_t i = tarity; i >= 1; i--) {
          size_t args2[2] = {tf + (size_t)i, list};
          list = heap_new_struct(atom_dot, 2, args2);
        }
        size_t head_args[2] = {heap_new_atom(heap[tf].as.func.atom_id), list};
        list = heap_new_struct(atom_dot, 2, head_args);
      } else {
        size_t args2[2] = {term, list};
        list = heap_new_struct(atom_dot, 2, args2);
      }
      *ok = unify(f + 2, list);
      return 1;
    }
    size_t d = heap_deref(f + 2);
    if (heap[d].tag != TAG_STR) {
      *ok = 0;
      return 1;
    }
    size_t df = heap[d].as.ptr;
    if (heap[df].as.func.atom_id != atom_dot || heap[df].as.func.arity != 2) {
      *ok = 0;
      return 1;
    }
    size_t head = heap_deref(df + 1);
    size_t cur = heap_deref(df + 2);
    size_t elems[255];
    int32_t ne = 0;
    while (heap[cur].tag == TAG_STR) {
      size_t cf = heap[cur].as.ptr;
      if (heap[cf].as.func.atom_id != atom_dot || heap[cf].as.func.arity != 2 ||
          ne >= 255)
        break;
      elems[ne++] = heap_deref(cf + 1);
      cur = heap_deref(cf + 2);
    }
    size_t built;
    if (ne == 0)
      built = head;
    else if (heap[head].tag == TAG_ATOM)
      built = heap_new_struct(heap[head].as.atom_id, ne, elems);
    else {
      *ok = 0;
      return 1;
    }
    *ok = unify(term, built);
    return 1;
  }
  if (arity == 2 && id == atom_var_addr) {
    size_t d = heap_deref(f + 1);
    *ok = unify(f + 2, heap_new_int((int64_t)d));
    return 1;
  }
  if (arity == 2 && id == atom_atom_codes) {
    size_t a = heap_deref(f + 1);
    if (heap[a].tag == TAG_ATOM) {
      *ok = unify(f + 2, codes_from_cstr(atom_name(heap[a].as.atom_id)));
      return 1;
    }
    char buf[4096];
    if (!cstr_from_codes(f + 2, buf, sizeof buf)) {
      *ok = 0;
      return 1;
    }
    *ok = unify(f + 1, heap_new_atom(atom_intern(buf)));
    return 1;
  }
  if (arity == 2 && id == atom_number_codes) {
    size_t a = heap_deref(f + 1);
    if (heap[a].tag == TAG_INT) {
      char buf[32];
      snprintf(buf, sizeof buf, "%" PRId64, heap[a].as.ival);
      *ok = unify(f + 2, codes_from_cstr(buf));
      return 1;
    }
    if (heap[a].tag == TAG_FLT) {
      char buf[64];
      snprintf(buf, sizeof buf, "%g", heap[a].as.fval);
      *ok = unify(f + 2, codes_from_cstr(buf));
      return 1;
    }
    char buf[64];
    if (!cstr_from_codes(f + 2, buf, sizeof buf)) {
      *ok = 0;
      return 1;
    }
    char *end;
    int64_t iv = strtoll(buf, &end, 10);
    if (*end == '\0' && end != buf) {
      *ok = unify(f + 1, heap_new_int(iv));
      return 1;
    }
    double dv = strtod(buf, &end);
    *ok = (*end == '\0' && end != buf) && unify(f + 1, heap_new_flt(dv));
    return 1;
  }
  return 0;
}

static void rename_init(size_t *rename, int32_t n) {
  for (int32_t i = 0; i < n; i++)
    rename[i] = (size_t)-1;
}

static int do_throw(size_t ball, size_t *cn_out, size_t *active_catch_ptr) {
  int32_t nballvars;
  tterm_t *ball_template = heap_to_template(ball, &nballvars);
  size_t idx = *active_catch_ptr;
  for (;;) {
    if (idx == (size_t)-1) {
      io_write_err("uncaught exception: ");
      print_term_via(ball, 0, io_write_err);
      io_write_err("\n");
      return 0;
    }
    catch_frame_t entry = catch_stack[idx];
    heap_release(entry.heap_mark);
    trail_release(entry.trail_mark);
    sp = entry.sp_at_entry;
    size_t ball_copy = fresh_copy_term(ball_template, nballvars);
    if (unify(entry.catcher, ball_copy)) {
      *active_catch_ptr = entry.outer_active_catch;
      *cn_out = build_conj_tail(&entry.recovery, 1, entry.continuation);
      return 1;
    }
    idx = entry.outer_active_catch;
  }
}

void run_query(tterm_t **goals, int32_t ngoals, int32_t nvars,
               const char **varnames, int mode) {
  size_t rename[nvars > 0 ? nvars : 1];
  rename_init(rename, nvars);

  sp = 0;
  size_t hmark = heap_mark(), tmark = trail_mark(), cut_barrier = 0;
  int any_found = 0;

  size_t qgoals[ngoals > 0 ? ngoals : 1];
  for (int32_t i = 0; i < ngoals; i++)
    qgoals[i] = heap_copy_goal(goals[i], rename, cut_barrier);
  size_t cn = build_conj_tail(qgoals, ngoals, heap_new_atom(atom_true));

  size_t first, rest;
  int32_t clause_idx = 0;
  idx_key_t caller_key = {.kind = IDX_ANY};
  size_t active_catch = (size_t)-1;
  int predicate_known = 0;

A:
  gc_maybe_run(&cn, stack, sp, rename, nvars);
  {
    // check cn == true before decompose, or a mid-clause true goal
    // wrongly ends the query.
    size_t cnd = heap_deref(cn);
    if (heap[cnd].tag == TAG_ATOM && heap[cnd].as.atom_id == atom_true) {
      if (mode == RUN_INTERACTIVE) {
        io_write_str(any_found ? "\n;  " : "   ");
        any_found = 1;
        int any_var = 0;
        for (int32_t i = 0; i < nvars; i++)
          if (rename[i] != (size_t)-1) {
            char buf[300];
            snprintf(buf, sizeof buf, "%s%s = ", any_var ? ", " : "",
                     varnames[i]);
            io_write_str(buf);
            print_term(rename[i]);
            any_var = 1;
          }
        if (!any_var)
          io_write_str("true");

        if (sp == 0) {
          io_write_str(".\n");
          return;
        }
        int key = io_read_key();
        if (key != ';' && key != ' ') {
          io_write_str(".\n");
          return;
        }
      } else if (mode == RUN_BATCH) {
        io_write_str("yes:");
        for (int32_t i = 0; i < nvars; i++)
          if (rename[i] != (size_t)-1) {
            char buf[300];
            snprintf(buf, sizeof buf, " %s=", varnames[i]);
            io_write_str(buf);
            print_term(rename[i]);
          }
        io_write_str("\n");
      }
      goto C;
    }
  }
  decompose(cn, &first, &rest);
  {
    size_t fd = heap_deref(first);
    if (heap[fd].tag == TAG_ATOM && heap[fd].as.atom_id == atom_true) {
      cn = rest;
      goto A;
    }
    if (heap[fd].tag == TAG_STR) {
      size_t cf = heap[fd].as.ptr;
      int32_t fd_arity = heap[cf].as.func.arity;
      int32_t fd_id = heap[cf].as.func.atom_id;
      if (fd_arity == 2 && fd_id == atom_comma) {
        size_t inner_first = heap_deref(cf + 1);
        size_t inner_rest = heap_deref(cf + 2);
        size_t new_rest = build_conj_tail(&inner_rest, 1, rest);
        cn = build_conj_tail(&inner_first, 1, new_rest);
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_call) {
        size_t goal = heap_rebake_cuts(heap_deref(cf + 1), sp);
        cn = build_conj_tail(&goal, 1, rest);
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_cut) {
        sp = (size_t)heap[heap_deref(cf + 1)].as.ival;
        cn = rest;
        goto A;
      }
      if (fd_arity == 3 && fd_id == atom_catch) {
        size_t goal = heap_rebake_cuts(heap_deref(cf + 1), sp);
        size_t catcher = heap_deref(cf + 2);
        size_t recovery = heap_deref(cf + 3);
        size_t idx = catch_stack_push(
            (catch_frame_t){.heap_mark = heap_mark(),
                            .trail_mark = trail_mark(),
                            .sp_at_entry = sp,
                            .catcher = catcher,
                            .recovery = recovery,
                            .continuation = rest,
                            .outer_active_catch = active_catch});
        active_catch = idx;
        size_t uncatch_arg[1] = {heap_new_int((int64_t)idx)};
        size_t uncatch_term = heap_new_struct(atom_uncatch, 1, uncatch_arg);
        size_t after_goal = build_conj_tail(&uncatch_term, 1, rest);
        cn = build_conj_tail(&goal, 1, after_goal);
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_uncatch) {
        size_t idx = (size_t)heap[heap_deref(cf + 1)].as.ival;
        active_catch = catch_stack[idx].outer_active_catch;
        cn = rest;
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_throw) {
        size_t ball = heap_deref(cf + 1);
        if (do_throw(ball, &cn, &active_catch))
          goto A;
        return;
      }
      if (fd_arity == 1 && (fd_id == atom_assertz || fd_id == atom_assert ||
                            fd_id == atom_asserta)) {
        size_t clause = heap_deref(cf + 1);
        size_t body_refs[MAX_ASSERT_GOALS];
        size_t head, all_terms[1 + MAX_ASSERT_GOALS];
        int32_t nbody;
        split_clause(clause, &head, body_refs, &nbody);
        all_terms[0] = head;
        for (int32_t i = 0; i < nbody; i++)
          all_terms[1 + i] = body_refs[i];

        tterm_t **templates =
            arena_alloc((size_t)(1 + nbody) * sizeof(tterm_t *));
        int32_t nvars;
        heap_terms_to_templates(all_terms, 1 + nbody, templates, &nvars);

        if (fd_id == atom_asserta)
          db_add_front(templates[0], nbody > 0 ? templates + 1 : NULL, nbody,
                       nvars);
        else
          db_add(templates[0], nbody > 0 ? templates + 1 : NULL, nbody, nvars);
        cn = rest;
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_retract) {
        size_t clause = heap_deref(cf + 1);
        size_t want_head, want_body;
        split_clause_whole(clause, &want_head, &want_body);

        idx_key_t want_key = key_of_goal(want_head);
        pred_bucket_t *bucket =
            pred_bucket_find(want_key.pred_id, want_key.pred_arity);
        size_t rmark = heap_mark(), rtmark = trail_mark();
        int found = 0;
        for (int32_t bi = 0; bucket && bi < bucket->count; bi++) {
          int32_t ci = bucket->indices[bi];
          if (keys_conflict(want_key, db[ci].key))
            continue;
          trail_release(rtmark);
          heap_release(rmark);
          clause_t *c = &db[ci];
          size_t rn[c->nvars > 0 ? c->nvars : 1];
          rename_init(rn, c->nvars);
          size_t h = heap_copy(c->head, rn, 0);
          if (!unify(h, want_head))
            continue;
          size_t bodies[c->nbody > 0 ? c->nbody : 1];
          for (int32_t i = 0; i < c->nbody; i++)
            bodies[i] = heap_copy(c->body[i], rn, 0);
          size_t body_whole = body_as_term(bodies, c->nbody);
          if (!unify(body_whole, want_body))
            continue;
          db_remove_at(ci);
          found = 1;
          break;
        }
        if (!found) {
          trail_release(rtmark);
          heap_release(rmark);
          goto C;
        }
        cn = rest;
        goto A;
      }
    }
    int ok;
    if (dispatch_builtin(first, &ok)) {
      if (ok) {
        cn = rest;
        goto A;
      }
      if (pending_error_ball != (size_t)-1) {
        size_t ball = pending_error_ball;
        pending_error_ball = (size_t)-1;
        if (do_throw(ball, &cn, &active_catch))
          goto A;
        return;
      }
      goto C;
    }
  }
  clause_idx = 0;
  tmark = trail_mark();
  hmark = heap_mark();
  cut_barrier = sp;
  caller_key = key_of_goal(first);
  predicate_known = 0;

B:
  if (clause_idx >= db_count) {
    if (!predicate_known &&
        is_dynamic(caller_key.pred_id, caller_key.pred_arity))
      goto C; // declared dynamic - no clauses is a normal fail, not
              // existence_error
    if (!predicate_known) {
      size_t ball = make_existence_error("procedure", caller_key.pred_id,
                                         caller_key.pred_arity);
      if (do_throw(ball, &cn, &active_catch))
        goto A;
      return;
    }
    goto C;
  }
  {
    clause_t *c = &db[clause_idx];
    clause_idx++;
    if (c->key.pred_id == caller_key.pred_id &&
        c->key.pred_arity == caller_key.pred_arity)
      predicate_known = 1;
    if (keys_conflict(caller_key, c->key))
      goto B;
    trail_release(tmark);
    heap_release(hmark);

    size_t r2[c->nvars > 0 ? c->nvars : 1];
    rename_init(r2, c->nvars);
    size_t h = heap_copy(c->head, r2, cut_barrier);

    if (!unify(h, first))
      goto B;

    size_t bodies[c->nbody > 0 ? c->nbody : 1];
    for (int32_t i = 0; i < c->nbody; i++)
      bodies[i] = heap_copy_goal(c->body[i], r2, cut_barrier);
    size_t newcn = build_conj_tail(bodies, c->nbody, rest);

    if (!no_more_candidates(clause_idx, caller_key))
      stack_push((frame_t){.goals = cn,
                           .clause_idx = clause_idx,
                           .heap_mark = hmark,
                           .trail_mark = tmark,
                           .cut_barrier = cut_barrier,
                           .active_catch = active_catch});
    cn = newcn;
    goto A;
  }

C:
  if (sp == 0) {
    if (mode == RUN_INTERACTIVE)
      io_write_str(any_found ? ".\n" : "   false.\n");
    return;
  }
  {
    frame_t f = stack[--sp];
    cn = f.goals;
    clause_idx = f.clause_idx;
    hmark = f.heap_mark;
    tmark = f.trail_mark;
    cut_barrier = f.cut_barrier;
    active_catch = f.active_catch;
    decompose(cn, &first, &rest);
    // release before keying, or a stale binding from the last clause
    // tried wrongly indexes out every other clause.
    trail_release(tmark);
    heap_release(hmark);
    caller_key = key_of_goal(first);
    goto B;
  }
}

static int op_lookup(int32_t name_atom_id, int want_infix, int *pri,
                     int *assoc_code) {
  pred_bucket_t *b = pred_bucket_find(atom_op_pred, 3);
  if (!b)
    return 0;
  int found = 0;
  for (int32_t i = 0; i < b->count; i++) {
    tterm_t *head = db[b->indices[i]].head;
    tterm_t *pri_t = head->as.str.args[0];
    tterm_t *type_t = head->as.str.args[1];
    tterm_t *name_t = head->as.str.args[2];
    if (name_t->tag != T_ATOM || name_t->as.atom_id != name_atom_id)
      continue;
    if (pri_t->tag != T_INT || type_t->tag != T_ATOM)
      continue; // malformed fact
    int32_t tid = type_t->as.atom_id;
    int code;
    if (tid == atom_optype_xfx)
      code = 0;
    else if (tid == atom_optype_xfy)
      code = 1;
    else if (tid == atom_optype_yfx)
      code = 2;
    else if (tid == atom_optype_fx)
      code = 3;
    else if (tid == atom_optype_fy)
      code = 4;
    else
      continue; // unrecognized Type atom
    if ((code <= 2) != want_infix)
      continue;
    *pri = (int)pri_t->as.ival;
    *assoc_code = code;
    found = 1;
  }
  return found;
}

int op_lookup_infix(int32_t name_atom_id, int *pri, int *assoc_code) {
  return op_lookup(name_atom_id, 1, pri, assoc_code);
}
int op_lookup_prefix(int32_t name_atom_id, int *pri, int *assoc_code) {
  return op_lookup(name_atom_id, 0, pri, assoc_code);
}

static tterm_t *wrap_conj(tterm_t **goals, int32_t n) {
  if (n == 0)
    return tt_atom("true");
  tterm_t *acc = goals[n - 1];
  for (int32_t i = n - 2; i >= 0; i--) {
    tterm_t *args[2] = {goals[i], acc};
    acc = tt_struct(",", 2, args);
  }
  return acc;
}
void run_query_meta(tterm_t **goals, int32_t ngoals, int32_t nvars,
                    const char **names, int mode) {
  tterm_t *solve_args[1] = {wrap_conj(goals, ngoals)};
  tterm_t *wrapped[1] = {tt_struct("solve", 1, solve_args)};
  run_query(wrapped, 1, nvars, names, mode);
}

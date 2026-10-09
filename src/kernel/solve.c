#include "solve.h"
#include "arena.h"
#include "atoms.h"
#include "ctx.h"
#include "fmt.h"
#include "gc.h"
#include "heap.h"
#include "io.h"
#include "mem.h"
#include "parse.h"
#include "platform.h"
#include "streams.h"
#include "unify.h"
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// real cap enforced by functor/3 and =../2 below;
// current_prolog_flag(max_arity, V) reports this exact number.

static uint32_t pred_hash_slot(int32_t pred_id, int32_t pred_arity) {
  uint32_t h = (uint32_t)pred_id * 2654435761u + (uint32_t)pred_arity * 40503u;
  return h % PRED_HASH_SIZE;
}

static pred_bucket_t *pred_bucket_find(trilog_t *T, int32_t pred_id,
                                       int32_t pred_arity) {
  for (pred_bucket_t *b = T->pred_hash[pred_hash_slot(pred_id, pred_arity)]; b;
       b = b->next)
    if (b->pred_id == pred_id && b->pred_arity == pred_arity)
      return b;
  return NULL;
}

static pred_bucket_t *pred_bucket_find_or_create(trilog_t *T, int32_t pred_id,
                                                 int32_t pred_arity) {
  pred_bucket_t *b = pred_bucket_find(T, pred_id, pred_arity);
  if (b)
    return b;
  b = mem_grow_n(T, NULL, 1, sizeof(pred_bucket_t));
  *b = (pred_bucket_t){0};
  b->pred_id = pred_id;
  b->pred_arity = pred_arity;
  uint32_t slot = pred_hash_slot(pred_id, pred_arity);
  b->next = T->pred_hash[slot];
  T->pred_hash[slot] = b;
  return b;
}

static void pred_bucket_grow_if_needed(trilog_t *T, pred_bucket_t *b) {
  if (b->count < b->cap)
    return;
  int32_t cap = b->cap ? b->cap * 2 : 4;
  b->indices = mem_grow_n(T, b->indices, (size_t)cap, sizeof(int32_t));
  b->cap = cap;
}

static void pred_bucket_add_index(trilog_t *T, int32_t pred_id,
                                  int32_t pred_arity, int32_t idx) {
  pred_bucket_t *b = pred_bucket_find_or_create(T, pred_id, pred_arity);
  pred_bucket_grow_if_needed(T, b);
  b->indices[b->count++] = idx;
}

static void pred_bucket_add_index_front(trilog_t *T, int32_t pred_id,
                                        int32_t pred_arity, int32_t idx) {
  pred_bucket_t *b = pred_bucket_find_or_create(T, pred_id, pred_arity);
  pred_bucket_grow_if_needed(T, b);
  memmove(&b->indices[1], &b->indices[0], (size_t)b->count * sizeof(int32_t));
  b->indices[0] = idx;
  b->count++;
}

static void pred_bucket_remove_index(trilog_t *T, int32_t pred_id,
                                     int32_t pred_arity, int32_t idx) {
  pred_bucket_t *b = pred_bucket_find(T, pred_id, pred_arity);
  if (!b)
    return;
  int32_t lo = 0, hi = b->count; // indices stay sorted ascending
  while (lo < hi) {
    int32_t mid = lo + (hi - lo) / 2;
    if (b->indices[mid] < idx)
      lo = mid + 1;
    else
      hi = mid;
  }
  if (lo < b->count && b->indices[lo] == idx) {
    memmove(&b->indices[lo], &b->indices[lo + 1],
            (size_t)(b->count - lo - 1) * sizeof(int32_t));
    b->count--;
  }
}

static void pred_index_fixup_insert_at(trilog_t *T, int32_t at) {
  for (int i = 0; i < PRED_HASH_SIZE; i++)
    for (pred_bucket_t *b = T->pred_hash[i]; b; b = b->next)
      for (int32_t j = 0; j < b->count; j++)
        if (b->indices[j] >= at)
          b->indices[j]++;
}

catch_frame_t *catch_stack_array(trilog_t *T) { return T->catch_stack; }
size_t catch_stack_size(trilog_t *T) { return T->catch_sp; }
void catch_stack_set_size(trilog_t *T, size_t n) { T->catch_sp = n; }

static size_t catch_stack_push(trilog_t *T, catch_frame_t f) {
  if (T->catch_sp >= T->catch_cap) {
    size_t cap = T->catch_cap ? T->catch_cap * 2 : 16;
    T->catch_stack = mem_grow_n(T, T->catch_stack, cap, sizeof(catch_frame_t));
    T->catch_cap = cap;
  }
  T->catch_stack[T->catch_sp] = f;
  return T->catch_sp++;
}

static size_t make_error(trilog_t *T, size_t formal) {
  size_t context;
  if (T->error_pi_name >= 0) {
    size_t pi[2] = {heap_new_atom(T, T->error_pi_name),
                    heap_new_int(T, T->error_pi_arity)};
    context = heap_new_struct(T, atom_slash, 2, pi);
  } else {
    context = heap_new_var(T);
  }
  size_t args[2] = {formal, context};
  return heap_new_struct(T, atom_error, 2, args);
}
static size_t make_instantiation_error(trilog_t *T) {
  return make_error(T, heap_new_atom(T, atom_instantiation_error));
}
static size_t make_type_error(trilog_t *T, const char *type, size_t culprit) {
  size_t args[2] = {heap_new_atom(T, atom_intern(T, type)), culprit};
  return make_error(T, heap_new_struct(T, atom_type_error, 2, args));
}
static size_t make_existence_error_term(trilog_t *T, const char *obj_type,
                                        size_t culprit) {
  size_t args[2] = {heap_new_atom(T, atom_intern(T, obj_type)), culprit};
  return make_error(T, heap_new_struct(T, atom_existence_error, 2, args));
}
static size_t make_existence_error(trilog_t *T, const char *obj_type,
                                   int32_t pred_id, int32_t pred_arity) {
  size_t pi_args[2] = {heap_new_atom(T, pred_id), heap_new_int(T, pred_arity)};
  return make_existence_error_term(T, obj_type,
                                   heap_new_struct(T, atom_slash, 2, pi_args));
}

static size_t make_cyclic_term_error(trilog_t *T) {
  size_t args[1] = {heap_new_atom(T, atom_intern(T, "cyclic_term"))};
  return make_error(
      T, heap_new_struct(T, atom_intern(T, "representation_error"), 1, args));
}

static size_t make_domain_error(trilog_t *T, const char *domain,
                                size_t culprit) {
  size_t args[2] = {heap_new_atom(T, atom_intern(T, domain)), culprit};
  return make_error(
      T, heap_new_struct(T, atom_intern(T, "domain_error"), 2, args));
}
static size_t make_syntax_error(trilog_t *T) {
  size_t args[1] = {heap_new_atom(T, atom_intern(T, T->err_msg))};
  return make_error(
      T, heap_new_struct(T, atom_intern(T, "syntax_error"), 1, args));
}
static size_t make_resource_error(trilog_t *T, const char *what) {
  size_t args[1] = {heap_new_atom(T, atom_intern(T, what))};
  return make_error(
      T, heap_new_struct(T, atom_intern(T, "resource_error"), 1, args));
}
static size_t make_evaluation_error(trilog_t *T, int32_t what_atom) {
  size_t args[1] = {heap_new_atom(T, what_atom)};
  return make_error(T, heap_new_struct(T, atom_evaluation_error, 1, args));
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

static idx_key_t key_of_goal(trilog_t *T, size_t goal) {
  idx_key_t k = {.pred_id = -1, .pred_arity = 0, .kind = IDX_ANY};
  size_t g = heap_deref(T, goal);
  if (T->heap[g].tag == TAG_ATOM) {
    k.pred_id = T->heap[g].as.atom_id;
    return k;
  }
  if (T->heap[g].tag != TAG_STR)
    return k;
  size_t f = T->heap[g].as.ptr;
  k.pred_id = T->heap[f].as.func.atom_id;
  k.pred_arity = T->heap[f].as.func.arity;
  size_t a0 = heap_deref(T, f + 1);
  switch (T->heap[a0].tag) {
  case TAG_REF:
  case TAG_FLT:
    return k;
  case TAG_ATOM:
    k.kind = IDX_ATOM;
    k.atom_id = T->heap[a0].as.atom_id;
    return k;
  case TAG_INT:
    k.kind = IDX_INT;
    k.ival = T->heap[a0].as.ival;
    return k;
  case TAG_STR: {
    size_t af = T->heap[a0].as.ptr;
    k.kind = IDX_STRUCT;
    k.atom_id = T->heap[af].as.func.atom_id;
    k.arity = T->heap[af].as.func.arity;
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

// db index of the first clause at or after from_idx that matches key, or -1.
// Walks only key's predicate bucket, whose indices stay sorted ascending.
static int32_t next_candidate(trilog_t *T, int32_t from_idx, idx_key_t key) {
  pred_bucket_t *b = pred_bucket_find(T, key.pred_id, key.pred_arity);
  if (!b)
    return -1;
  int32_t lo = 0, hi = b->count;
  while (lo < hi) {
    int32_t mid = lo + (hi - lo) / 2;
    if (b->indices[mid] < from_idx)
      lo = mid + 1;
    else
      hi = mid;
  }
  for (; lo < b->count; lo++)
    if (!keys_conflict(key, T->db[b->indices[lo]].key))
      return b->indices[lo];
  return -1;
}

static int no_more_candidates(trilog_t *T, int32_t from_idx,
                              idx_key_t caller_key) {
  return next_candidate(T, from_idx, caller_key) < 0;
}

static void db_ensure_cap(trilog_t *T) {
  if (T->db_count < T->db_cap)
    return;
  int32_t cap = T->db_cap ? T->db_cap * 2 : 8;
  T->db = mem_grow_n(T, T->db, (size_t)cap, sizeof(clause_t));
  T->db_cap = cap;
}

static int is_dynamic(trilog_t *T, int32_t pred_id,
                      int32_t pred_arity); // below

// static == was_consulted: dynamic_declare removes from consulted_decls on
// declaration, so the two sets stay complementary either order.
static int was_consulted(trilog_t *T, int32_t pred_id, int32_t pred_arity) {
  for (int32_t i = 0; i < T->consulted_count; i++)
    if (T->consulted_decls[i].pred_id == pred_id &&
        T->consulted_decls[i].pred_arity == pred_arity)
      return 1;
  return 0;
}

static void mark_consulted(trilog_t *T, int32_t pred_id, int32_t pred_arity) {
  if (is_dynamic(T, pred_id, pred_arity) ||
      was_consulted(T, pred_id, pred_arity))
    return;
  if (T->consulted_count >= T->consulted_cap) {
    int32_t cap = T->consulted_cap ? T->consulted_cap * 2 : 8;
    T->consulted_decls =
        mem_grow_n(T, T->consulted_decls, (size_t)cap, sizeof(pred_decl_t));
    T->consulted_cap = cap;
  }
  T->consulted_decls[T->consulted_count++] = (pred_decl_t){pred_id, pred_arity};
}

static void unmark_consulted(trilog_t *T, int32_t pred_id, int32_t pred_arity) {
  for (int32_t i = 0; i < T->consulted_count; i++)
    if (T->consulted_decls[i].pred_id == pred_id &&
        T->consulted_decls[i].pred_arity == pred_arity) {
      T->consulted_decls[i] = T->consulted_decls[--T->consulted_count];
      return;
    }
}

void db_add(trilog_t *T, tterm_t *head, tterm_t **body, int32_t nbody,
            int32_t nvars, int mark_static) {
  idx_key_t key = key_of_template(head);
  pred_bucket_grow_if_needed(
      T, pred_bucket_find_or_create(T, key.pred_id, key.pred_arity));
  db_ensure_cap(T);
  if (mark_static)
    mark_consulted(T, key.pred_id, key.pred_arity);
  int32_t idx = T->db_count++;
  T->db[idx] = (clause_t){.head = head,
                          .body = body,
                          .nbody = nbody,
                          .nvars = nvars,
                          .key = key,
                          .source = mark_static ? T->consulting_atom : -1};
  pred_bucket_add_index(T, key.pred_id, key.pred_arity, idx);
}

static void db_fixup_choice_points_insert_at(trilog_t *T, int32_t at) {
  for (size_t i = 0; i < T->sp; i++)
    if (T->stack[i].clause_idx >= at)
      T->stack[i].clause_idx++;
}

static void db_add_front(trilog_t *T, tterm_t *head, tterm_t **body,
                         int32_t nbody, int32_t nvars) {
  idx_key_t key = key_of_template(head);
  pred_bucket_grow_if_needed(
      T, pred_bucket_find_or_create(T, key.pred_id, key.pred_arity));
  db_ensure_cap(T);
  memmove(&T->db[1], &T->db[0], (size_t)T->db_count * sizeof(clause_t));
  T->db_count++;
  T->db[0] = (clause_t){.head = head,
                        .body = body,
                        .nbody = nbody,
                        .nvars = nvars,
                        .key = key,
                        .source = -1};
  db_fixup_choice_points_insert_at(T, 0);
  pred_index_fixup_insert_at(T, 0);
  pred_bucket_add_index_front(T, key.pred_id, key.pred_arity, 0);
  // asserta: never marks static - see db_add's comment.
}

// slides live clauses down over dead slots, remapping every stored db index:
// bucket entries, and choicepoints' resume positions (a lower bound, so it
// maps to the number of live slots before it).
static void db_compact(trilog_t *T) {
  int32_t *newpos =
      mem_grow_n(T, NULL, (size_t)T->db_count + 1, sizeof(int32_t));
  int32_t live = 0;
  for (int32_t i = 0; i < T->db_count; i++) {
    newpos[i] = live;
    if (T->db[i].head)
      T->db[live++] = T->db[i];
  }
  newpos[T->db_count] = live;
  for (int i = 0; i < PRED_HASH_SIZE; i++)
    for (pred_bucket_t *b = T->pred_hash[i]; b; b = b->next)
      for (int32_t j = 0; j < b->count; j++)
        b->indices[j] = newpos[b->indices[j]];
  for (size_t i = 0; i < T->sp; i++)
    T->stack[i].clause_idx = newpos[T->stack[i].clause_idx];
  T->db_count = live;
  T->db_dead = 0;
  mem_free(T, newpos);
}

// unlinks the clause from its bucket and leaves db[idx] as a dead slot, so no
// shifting or fixups per removal; db_compact reclaims slots once dead ones
// outnumber live ones.
static void db_kill(trilog_t *T, int32_t idx) {
  pred_bucket_remove_index(T, T->db[idx].key.pred_id, T->db[idx].key.pred_arity,
                           idx);
  T->db[idx].head = NULL;
  T->db_dead++;
}

static void db_maybe_compact(trilog_t *T) {
  if (T->db_dead >= 64 && T->db_dead > T->db_count - T->db_dead)
    db_compact(T);
}

static void db_remove_at(trilog_t *T, int32_t idx) {
  db_kill(T, idx);
  db_maybe_compact(T);
}

void db_unload(trilog_t *T, int32_t source) {
  for (int32_t i = 0; i < T->db_count; i++) {
    if (!T->db[i].head || T->db[i].source != source)
      continue;
    idx_key_t key = T->db[i].key;
    db_kill(T, i);
    pred_bucket_t *b = pred_bucket_find(T, key.pred_id, key.pred_arity);
    if (!b || b->count == 0)
      unmark_consulted(T, key.pred_id, key.pred_arity);
  }
  db_maybe_compact(T);
}

static void dynamic_declare(trilog_t *T, int32_t pred_id, int32_t pred_arity) {
  if (is_dynamic(T, pred_id, pred_arity))
    return;
  pred_bucket_t *b = pred_bucket_find_or_create(T, pred_id, pred_arity);
  if (T->dynamic_count >= T->dynamic_cap) {
    int32_t cap = T->dynamic_cap ? T->dynamic_cap * 2 : 8;
    T->dynamic_decls =
        mem_grow_n(T, T->dynamic_decls, (size_t)cap, sizeof(dyn_decl_t));
    T->dynamic_cap = cap;
  }
  T->dynamic_decls[T->dynamic_count++] = (dyn_decl_t){pred_id, pred_arity};
  unmark_consulted(T, pred_id, pred_arity);
  b->dynamic = 1;
}

static void dynamic_undeclare(trilog_t *T, int32_t pred_id,
                              int32_t pred_arity) {
  for (int32_t i = 0; i < T->dynamic_count; i++)
    if (T->dynamic_decls[i].pred_id == pred_id &&
        T->dynamic_decls[i].pred_arity == pred_arity) {
      T->dynamic_decls[i] = T->dynamic_decls[--T->dynamic_count];
      pred_bucket_find(T, pred_id, pred_arity)->dynamic = 0;
      return;
    }
}

static int is_dynamic(trilog_t *T, int32_t pred_id, int32_t pred_arity) {
  for (int32_t i = 0; i < T->dynamic_count; i++)
    if (T->dynamic_decls[i].pred_id == pred_id &&
        T->dynamic_decls[i].pred_arity == pred_arity)
      return 1;
  return 0;
}

static void stack_push(trilog_t *T, frame_t f) {
  if (T->sp >= T->stack_cap) {
    size_t cap = T->stack_cap ? T->stack_cap * 2 : 64;
    T->stack = mem_grow_n(T, T->stack, cap, sizeof(frame_t));
    T->stack_cap = cap;
  }
  T->stack[T->sp++] = f;
}

static size_t build_conj_tail(trilog_t *T, size_t *goals, int32_t n,
                              size_t tail) {
  size_t acc = tail;
  for (int32_t i = n - 1; i >= 0; i--) {
    size_t args[2] = {goals[i], acc};
    acc = heap_new_struct(T, atom_comma, 2, args);
  }
  return acc;
}

static size_t body_as_term(trilog_t *T, size_t *goals, int32_t n) {
  if (n == 0)
    return heap_new_atom(T, atom_true);
  if (n == 1)
    return goals[0];
  return build_conj_tail(T, goals, n - 1, goals[n - 1]);
}

static void rename_init(size_t *rename, int32_t n);

static size_t *tmp_rename(trilog_t *T, int32_t n) {
  mem_reserve(T, (void **)&T->rename_tmp, &T->rename_tmp_cap,
              (size_t)(n > 0 ? n : 1) * sizeof(size_t));
  rename_init(T->rename_tmp, n);
  return T->rename_tmp;
}

static size_t *tmp_goals(trilog_t *T, int32_t n) {
  mem_reserve(T, (void **)&T->goals_tmp, &T->goals_tmp_cap,
              (size_t)(n > 0 ? n : 1) * sizeof(size_t));
  return T->goals_tmp;
}

static size_t fresh_copy_term(trilog_t *T, tterm_t *t, int32_t nvars) {
  return heap_copy(T, t, tmp_rename(T, nvars), 0);
}

static void fresh_copy_clause(trilog_t *T, clause_t *c, size_t *head_out,
                              size_t *body_out) {
  size_t *rn = tmp_rename(T, c->nvars);
  *head_out = heap_copy(T, c->head, rn, 0);
  size_t *bodies = tmp_goals(T, c->nbody);
  for (int32_t j = 0; j < c->nbody; j++)
    bodies[j] = heap_copy(T, c->body[j], rn, 0);
  *body_out = body_as_term(T, bodies, c->nbody);
}

static void decompose(trilog_t *T, size_t cn, size_t *first, size_t *rest) {
  size_t d = heap_deref(T, cn);
  if (T->heap[d].tag == TAG_STR) {
    size_t f = T->heap[d].as.ptr;
    if (T->heap[f].as.func.atom_id == atom_comma &&
        T->heap[f].as.func.arity == 2) {
      // deref, or rest re-wraps in one more indirection every call, forever
      *first = heap_deref(T, f + 1);
      *rest = heap_deref(T, f + 2);
      return;
    }
  }
  *first = d;
  *rest = heap_new_atom(T, atom_true);
}

static int32_t heap_flatten_conj(trilog_t *T, size_t t, size_t *out,
                                 int32_t max) {
  int32_t n = 0;
  size_t d = heap_deref(T, t);
  while (n < max - 1) {
    if (T->heap[d].tag != TAG_STR)
      break;
    size_t f = T->heap[d].as.ptr;
    if (T->heap[f].as.func.atom_id != atom_comma ||
        T->heap[f].as.func.arity != 2)
      break;
    out[n++] = heap_deref(T, f + 1);
    d = heap_deref(T, f + 2);
  }
  out[n++] = d;
  return n;
}

#define MAX_ASSERT_GOALS 64

static void split_clause(trilog_t *T, size_t clause, size_t *head_out,
                         size_t *body_out, int32_t *nbody_out) {
  size_t d = heap_deref(T, clause);
  if (T->heap[d].tag == TAG_STR) {
    size_t f = T->heap[d].as.ptr;
    if (T->heap[f].as.func.atom_id == atom_ruleop &&
        T->heap[f].as.func.arity == 2) {
      *head_out = heap_deref(T, f + 1);
      *nbody_out = heap_flatten_conj(T, heap_deref(T, f + 2), body_out,
                                     MAX_ASSERT_GOALS);
      return;
    }
  }
  *head_out = d;
  *nbody_out = 0;
}

static void split_clause_whole(trilog_t *T, size_t clause, size_t *head_out,
                               size_t *body_out) {
  size_t d = heap_deref(T, clause);
  if (T->heap[d].tag == TAG_STR) {
    size_t f = T->heap[d].as.ptr;
    if (T->heap[f].as.func.atom_id == atom_ruleop &&
        T->heap[f].as.func.arity == 2) {
      *head_out = heap_deref(T, f + 1);
      *body_out = heap_deref(T, f + 2);
      return;
    }
  }
  *head_out = d;
  *body_out = heap_new_atom(T, atom_true);
}

static double arith_dbl(trilog_t *T, size_t v) {
  return T->heap[v].tag == TAG_FLT ? T->heap[v].as.fval
                                   : (double)T->heap[v].as.ival;
}

// //, mod, bitwise ops reject a float operand outright.
static int arith_require_int(trilog_t *T, size_t v, int64_t *out, int *ok) {
  if (T->heap[v].tag == TAG_FLT) {
    T->pending_error_ball = make_type_error(T, "integer", v);
    *ok = 0;
    return 0;
  }
  *out = T->heap[v].as.ival;
  return 1;
}

// INT64_MIN / -1 and friends overflow (and trap on x86) in C.
static size_t arith_int_overflow(trilog_t *T, int *ok) {
  T->pending_error_ball = make_evaluation_error(T, atom_int_overflow);
  *ok = 0;
  return 0;
}

// Shifts a right by b >= 0 bits, rounding towards -infinity on every target.
static int64_t arith_shift_right(int64_t a, int64_t b) {
  if (b >= 63)
    return a < 0 ? -1 : 0;
  return a < 0 ? ~(~a >> b) : a >> b;
}

static size_t arith_shift_left(trilog_t *T, int64_t a, int64_t b, int *ok) {
  if (a == 0)
    return heap_new_int(T, 0);
  if (b == 63 && a == -1)
    return heap_new_int(T, INT64_MIN);
  if (b >= 63 || a > (INT64_MAX >> b) || a < arith_shift_right(INT64_MIN, b))
    return arith_int_overflow(T, ok);
  return heap_new_int(T, a * ((int64_t)1 << b));
}

static size_t arith_eval_error(trilog_t *T, int32_t what, int *ok) {
  T->pending_error_ball = make_evaluation_error(T, what);
  *ok = 0;
  return 0;
}

static size_t arith_float(trilog_t *T, double v, int *ok) {
  if (isnan(v))
    return arith_eval_error(T, atom_undefined, ok);
  if (isinf(v))
    return arith_eval_error(T, atom_float_overflow, ok);
  return heap_new_flt(T, v);
}

static size_t arith_pow_float(trilog_t *T, double x, double y, int *ok) {
  if (x == 0.0 && y < 0.0)
    return arith_eval_error(T, atom_zero_divisor, ok);
  if (x < 0.0 && y != floor(y))
    return arith_eval_error(T, atom_undefined, ok);
  return arith_float(T, pow(x, y), ok);
}

// Cor.2 integer power: negative exponents only for bases 1 and -1.
static size_t arith_pow_int(trilog_t *T, size_t a, int64_t x, int64_t y,
                            int *ok) {
  if (y < 0) {
    if (x == 1)
      return heap_new_int(T, 1);
    if (x == -1)
      return heap_new_int(T, y % 2 ? -1 : 1);
    if (x == 0)
      return arith_eval_error(T, atom_zero_divisor, ok);
    T->pending_error_ball = make_type_error(T, "float", a);
    *ok = 0;
    return 0;
  }
  int64_t acc = 1;
  while (y > 0) {
    if ((y & 1) && __builtin_mul_overflow(acc, x, &acc))
      return arith_int_overflow(T, ok);
    y >>= 1;
    if (y > 0 && __builtin_mul_overflow(x, x, &x))
      return arith_int_overflow(T, ok);
  }
  return heap_new_int(T, acc);
}

static size_t eval_arith(trilog_t *T, size_t r, int *ok) {
  r = heap_deref(T, r);
  if (T->heap[r].tag == TAG_REF) {
    T->pending_error_ball = make_instantiation_error(T);
    *ok = 0;
    return 0;
  }
  if (T->heap[r].tag == TAG_INT || T->heap[r].tag == TAG_FLT)
    return r;
  if (T->heap[r].tag == TAG_STR) {
    size_t f = T->heap[r].as.ptr;
    int32_t arity = T->heap[f].as.func.arity;
    int32_t id = T->heap[f].as.func.atom_id;
    if (arity == 2) {
      size_t a = eval_arith(T, f + 1, ok);
      size_t b = *ok ? eval_arith(T, f + 2, ok) : 0;
      if (!*ok)
        return 0;
      int mixed = T->heap[a].tag == TAG_FLT || T->heap[b].tag == TAG_FLT;

      if (id == atom_plus || id == atom_minus || id == atom_star) {
        if (mixed) {
          double fa = arith_dbl(T, a), fb = arith_dbl(T, b);
          if (id == atom_plus)
            return heap_new_flt(T, fa + fb);
          if (id == atom_minus)
            return heap_new_flt(T, fa - fb);
          return heap_new_flt(T, fa * fb);
        }
        int64_t res;
        int overflowed;
        if (id == atom_plus)
          overflowed = __builtin_add_overflow(T->heap[a].as.ival,
                                              T->heap[b].as.ival, &res);
        else if (id == atom_minus)
          overflowed = __builtin_sub_overflow(T->heap[a].as.ival,
                                              T->heap[b].as.ival, &res);
        else
          overflowed = __builtin_mul_overflow(T->heap[a].as.ival,
                                              T->heap[b].as.ival, &res);
        if (overflowed) {
          T->pending_error_ball = make_evaluation_error(T, atom_int_overflow);
          *ok = 0;
          return 0;
        }
        return heap_new_int(T, res);
      }
      // "/" is polymorphic: int/int truncates, any float divides exactly.
      if (id == atom_slash) {
        if (mixed) {
          double fb = arith_dbl(T, b);
          if (fb == 0.0) {
            T->pending_error_ball = make_evaluation_error(T, atom_zero_divisor);
            *ok = 0;
            return 0;
          }
          return heap_new_flt(T, arith_dbl(T, a) / fb);
        }
        if (T->heap[b].as.ival == 0) {
          T->pending_error_ball = make_evaluation_error(T, atom_zero_divisor);
          *ok = 0;
          return 0;
        }
        if (T->heap[a].as.ival == INT64_MIN && T->heap[b].as.ival == -1)
          return arith_int_overflow(T, ok);
        return heap_new_int(T, T->heap[a].as.ival / T->heap[b].as.ival);
      }
      if (id == atom_starstar)
        return arith_pow_float(T, arith_dbl(T, a), arith_dbl(T, b), ok);
      if (id == atom_caret) {
        if (mixed)
          return arith_pow_float(T, arith_dbl(T, a), arith_dbl(T, b), ok);
        return arith_pow_int(T, a, T->heap[a].as.ival, T->heap[b].as.ival, ok);
      }
      if (id == atom_atan2) {
        double y = arith_dbl(T, a), x = arith_dbl(T, b);
        if (x == 0.0 && y == 0.0)
          return arith_eval_error(T, atom_undefined, ok);
        return arith_float(T, atan2(y, x), ok);
      }
      if (id == atom_rem) {
        int64_t ai, bi;
        if (!arith_require_int(T, a, &ai, ok) ||
            !arith_require_int(T, b, &bi, ok))
          return 0;
        if (bi == 0)
          return arith_eval_error(T, atom_zero_divisor, ok);
        return heap_new_int(T, bi == -1 ? 0 : ai % bi);
      }
      if (id == atom_intdiv || id == atom_mod) {
        int64_t ai, bi;
        if (!arith_require_int(T, a, &ai, ok) ||
            !arith_require_int(T, b, &bi, ok))
          return 0;
        if (bi == 0) {
          T->pending_error_ball = make_evaluation_error(T, atom_zero_divisor);
          *ok = 0;
          return 0;
        }
        if (bi == -1) // x mod -1 is 0; x // -1 overflows only for INT64_MIN
          return ai == INT64_MIN && id == atom_intdiv
                     ? arith_int_overflow(T, ok)
                     : heap_new_int(T, id == atom_mod ? 0 : -ai);
        if (id == atom_mod) {
          int64_t rem = ai % bi;
          if (rem != 0 && (rem < 0) != (bi < 0))
            rem += bi; // take the divisor's sign, without overflowing
          return heap_new_int(T, rem);
        }
        return heap_new_int(T, ai / bi);
      }
      // min(1, 2.5) = 1.0, not 1: the winner goes float if either side is.
      if (id == atom_min || id == atom_max) {
        int a_wins = id == atom_min ? arith_dbl(T, a) <= arith_dbl(T, b)
                                    : arith_dbl(T, a) >= arith_dbl(T, b);
        size_t winner = a_wins ? a : b;
        if (mixed && T->heap[winner].tag != TAG_FLT)
          return heap_new_flt(T, arith_dbl(T, winner));
        return winner;
      }
      if (id == atom_bitand || id == atom_bitor || id == atom_bitxor ||
          id == atom_shl || id == atom_shr) {
        int64_t ai, bi;
        if (!arith_require_int(T, a, &ai, ok) ||
            !arith_require_int(T, b, &bi, ok))
          return 0;
        if (id == atom_bitand)
          return heap_new_int(T, ai & bi);
        if (id == atom_bitor)
          return heap_new_int(T, ai | bi);
        if (id == atom_bitxor)
          return heap_new_int(T, ai ^ bi);
        // negative shift amount shifts the other way.
        int left = id == atom_shl ? bi >= 0 : bi < 0;
        int64_t amount = bi >= 0 ? bi : bi == INT64_MIN ? INT64_MAX : -bi;
        if (left)
          return arith_shift_left(T, ai, amount, ok);
        return heap_new_int(T, arith_shift_right(ai, amount));
      }
    } else if (arity == 1) {
      size_t a = eval_arith(T, f + 1, ok);
      if (!*ok)
        return 0;
      int a_flt = T->heap[a].tag == TAG_FLT;
      if (!a_flt && T->heap[a].as.ival == INT64_MIN &&
          (id == atom_minus || id == atom_abs))
        return arith_int_overflow(T, ok);
      if (id == atom_minus)
        return a_flt ? heap_new_flt(T, -T->heap[a].as.fval)
                     : heap_new_int(T, -T->heap[a].as.ival);
      if (id == atom_plus)
        return a;
      if (id == atom_abs)
        return a_flt ? heap_new_flt(T, fabs(T->heap[a].as.fval))
                     : heap_new_int(T, T->heap[a].as.ival < 0
                                           ? -T->heap[a].as.ival
                                           : T->heap[a].as.ival);
      // sign/1 rejects a float by falling through.
      if (id == atom_sign && !a_flt)
        return heap_new_int(T, (T->heap[a].as.ival > 0) -
                                   (T->heap[a].as.ival < 0));
      if (id == atom_bitnot) {
        int64_t ai;
        if (!arith_require_int(T, a, &ai, ok))
          return 0;
        return heap_new_int(T, ~ai);
      }
      if (id == atom_kw_float)
        return a_flt ? a : heap_new_flt(T, (double)T->heap[a].as.ival);
      if (id == atom_sqrt || id == atom_log) {
        double x = arith_dbl(T, a);
        if (id == atom_sqrt ? x < 0.0 : x <= 0.0)
          return arith_eval_error(T, atom_undefined, ok);
        return arith_float(T, id == atom_sqrt ? sqrt(x) : log(x), ok);
      }
      if (id == atom_sin || id == atom_cos || id == atom_atan ||
          id == atom_exp) {
        double x = arith_dbl(T, a);
        return arith_float(T,
                           id == atom_sin    ? sin(x)
                           : id == atom_cos  ? cos(x)
                           : id == atom_atan ? atan(x)
                                             : exp(x),
                           ok);
      }
      if (id == atom_float_integer_part || id == atom_float_fractional_part) {
        if (!a_flt) {
          T->pending_error_ball = make_type_error(T, "float", a);
          *ok = 0;
          return 0;
        }
        double ip, fp = modf(T->heap[a].as.fval, &ip);
        return heap_new_flt(T, id == atom_float_integer_part ? ip : fp);
      }
      // casting a double outside [-2^63, 2^63) to int64_t is undefined
      // behavior in C, not just an overflow like +/-/*.
      if ((id == atom_floor || id == atom_ceiling || id == atom_round ||
           id == atom_truncate) &&
          a_flt) {
        double rounded = id == atom_floor     ? floor(T->heap[a].as.fval)
                         : id == atom_ceiling ? ceil(T->heap[a].as.fval)
                         : id == atom_round   ? round(T->heap[a].as.fval)
                                              : trunc(T->heap[a].as.fval);
        if (!(rounded >= -9223372036854775808.0 &&
              rounded < 9223372036854775808.0)) {
          T->pending_error_ball = make_evaluation_error(T, atom_int_overflow);
          *ok = 0;
          return 0;
        }
        return heap_new_int(T, (int64_t)rounded);
      }
      if (id == atom_floor || id == atom_ceiling || id == atom_round ||
          id == atom_truncate)
        return heap_new_int(T, T->heap[a].as.ival);
    }
    T->pending_error_ball = make_type_error(
        T, "evaluable",
        heap_new_struct(
            T, atom_slash, 2,
            (size_t[2]){heap_new_atom(T, T->heap[f].as.func.atom_id),
                        heap_new_int(T, arity)}));
    *ok = 0;
    return 0;
  }
  if (T->heap[r].tag == TAG_ATOM && T->heap[r].as.atom_id == atom_pi)
    return heap_new_flt(T, 3.14159265358979323846);
  if (T->heap[r].tag == TAG_ATOM) {
    T->pending_error_ball = make_type_error(
        T, "evaluable",
        heap_new_struct(T, atom_slash, 2,
                        (size_t[2]){heap_new_atom(T, T->heap[r].as.atom_id),
                                    heap_new_int(T, 0)}));
    *ok = 0;
    return 0;
  }
  *ok = 0;
  return 0;
}

// One whole line from user_input (sid < 0) or a stream into T->scratch,
// or NULL at end of file.
static char *read_whole_line(trilog_t *T, int sid) {
  size_t len = 0;
  for (;;) {
    mem_reserve(T, &T->scratch, &T->scratch_cap, len + 256);
    size_t room = T->scratch_cap - len;
    int size = room > INT_MAX ? INT_MAX : (int)room;
    char *buf = (char *)T->scratch + len;
    char *got = sid < 0 ? io_read_line(T, buf, size)
                        : stream_read_line(T, sid, buf, size);
    if (!got)
      break;
    size_t k = strlen(got);
    len += k;
    if (got[k - 1] == '\n' || k + 1 < (size_t)size)
      break;
  }
  if (len == 0)
    return NULL;
  ((char *)T->scratch)[len] = '\0';
  return T->scratch;
}

static size_t codes_from_cstr(trilog_t *T, const char *s) {
  size_t acc = heap_new_atom(T, atom_nil);
  size_t n = strlen(s);
  for (size_t i = n; i-- > 0;) {
    size_t args[2] = {heap_new_int(T, (unsigned char)s[i]), acc};
    acc = heap_new_struct(T, atom_dot, 2, args);
  }
  return acc;
}

// The text of a code list in T->scratch, or NULL. incomplete is set when the
// list or an element is unbound (vs. wrong shape/type)
// lets callers throw instantiation_error, not just fail.
static char *codes_text(trilog_t *T, size_t list, size_t max_len,
                        int *incomplete) {
  size_t d = heap_deref(T, list);
  size_t n = 0;
  while (T->heap[d].tag != TAG_ATOM || T->heap[d].as.atom_id != atom_nil) {
    if (T->heap[d].tag == TAG_REF) {
      if (incomplete)
        *incomplete = 1;
      return 0;
    }
    if (T->heap[d].tag != TAG_STR)
      return 0;
    size_t f = T->heap[d].as.ptr;
    if (T->heap[f].as.func.atom_id != atom_dot || T->heap[f].as.func.arity != 2)
      return 0;
    size_t h = heap_deref(T, f + 1);
    if (T->heap[h].tag == TAG_REF) {
      if (incomplete)
        *incomplete = 1;
      return 0;
    }
    if (T->heap[h].tag != TAG_INT)
      return 0;
    if (n >= max_len)
      return 0;
    mem_reserve(T, &T->scratch, &T->scratch_cap, n + 2);
    ((char *)T->scratch)[n++] = (char)T->heap[h].as.ival;
    d = heap_deref(T, f + 2);
  }
  mem_reserve(T, &T->scratch, &T->scratch_cap, n + 1);
  ((char *)T->scratch)[n] = '\0';
  return T->scratch;
}

// Recurses into every argument but the last and loops on that one.
// 0: equal so far, or arguments pushed.
static int compare_step(trilog_t *T, size_t a, size_t b) {
  {
    a = heap_deref(T, a);
    b = heap_deref(T, b);
    if (a == b)
      return 0;
    int ra = T->heap[a].tag == TAG_REF                                  ? 0
             : (T->heap[a].tag == TAG_INT || T->heap[a].tag == TAG_FLT) ? 1
             : T->heap[a].tag == TAG_ATOM                               ? 2
                                                                        : 3;
    int rb = T->heap[b].tag == TAG_REF                                  ? 0
             : (T->heap[b].tag == TAG_INT || T->heap[b].tag == TAG_FLT) ? 1
             : T->heap[b].tag == TAG_ATOM                               ? 2
                                                                        : 3;
    if (ra != rb)
      return ra < rb ? -1 : 1;
    switch (ra) {
    case 0:
      return a < b ? -1 : 1;
    case 1: {
      double av = T->heap[a].tag == TAG_INT ? (double)T->heap[a].as.ival
                                            : T->heap[a].as.fval;
      double bv = T->heap[b].tag == TAG_INT ? (double)T->heap[b].as.ival
                                            : T->heap[b].as.fval;
      if (av != bv)
        return av < bv ? -1 : 1;
      // standard order of terms: same-valued numbers compare by type,
      // Float before Int (1.0 @< 1).
      if (T->heap[a].tag == T->heap[b].tag)
        return 0;
      return T->heap[a].tag == TAG_FLT ? -1 : 1;
    }
    case 2: {
      if (T->heap[a].as.atom_id == T->heap[b].as.atom_id)
        return 0;
      int c = strcmp(atom_name(T, T->heap[a].as.atom_id),
                     atom_name(T, T->heap[b].as.atom_id));
      return c < 0 ? -1 : 1;
    }
    default: {
      size_t af = T->heap[a].as.ptr, bf = T->heap[b].as.ptr;
      int32_t aa = T->heap[af].as.func.arity, ba = T->heap[bf].as.func.arity;
      if (aa != ba)
        return aa < ba ? -1 : 1;
      int32_t af_id = T->heap[af].as.func.atom_id,
              bf_id = T->heap[bf].as.func.atom_id;
      if (af_id != bf_id) {
        int nc = strcmp(atom_name(T, af_id), atom_name(T, bf_id));
        return nc < 0 ? -1 : 1;
      }
      if (pair_visits_seen(T, &T->compare_visits, af, bf))
        return 0; // already being compared, so equal as rational trees
      for (int32_t i = aa; i >= 1; i--) {
        wstack_push(T, af + (size_t)i);
        wstack_push(T, bf + (size_t)i);
      }
      return 0;
    }
    }
  }
}

static int term_compare_rec(trilog_t *T, size_t a, size_t b) {
  size_t wbase = T->wsp;
  for (;;) {
    int c = compare_step(T, a, b);
    if (c != 0) {
      T->wsp = wbase;
      return c;
    }
    if (T->wsp == wbase)
      return 0;
    b = T->wstack[--T->wsp];
    a = T->wstack[--T->wsp];
  }
}

static int term_compare(trilog_t *T, size_t a, size_t b) {
  pair_visits_reset(&T->compare_visits);
  return term_compare_rec(T, a, b);
}

static int resolve_stream_id(trilog_t *T, size_t arg, int *id_out) {
  size_t s = heap_deref(T, arg);
  if (T->heap[s].tag != TAG_STR)
    return 0;
  size_t sf = T->heap[s].as.ptr;
  if (T->heap[sf].as.func.atom_id != atom_stream ||
      T->heap[sf].as.func.arity != 1)
    return 0;
  size_t idv = heap_deref(T, sf + 1);
  if (T->heap[idv].tag != TAG_INT)
    return 0;
  *id_out = (int)T->heap[idv].as.ival;
  return 1;
}

static void emit_to_file(trilog_t *T, const char *str) {
  io_file_write(T, T->file_target, str);
}

enum { OUT_STDOUT, OUT_STDERR, OUT_FILE };

static int resolve_write_target(trilog_t *T, size_t target, int *kind_out,
                                void **handle_out) {
  if (T->heap[target].tag == TAG_INT) {
    int64_t n = T->heap[target].as.ival;
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
  if (!resolve_stream_id(T, target, &id) || !(h = stream_handle(T, id)))
    return 0;
  *kind_out = OUT_FILE;
  *handle_out = h;
  return 1;
}

static void tta_emit(trilog_t *T, const char *str) {
  size_t len = strlen(str);
  mem_reserve(T, &T->scratch, &T->scratch_cap, T->tta_pos + len + 1);
  memcpy((char *)T->scratch + T->tta_pos, str, len + 1);
  T->tta_pos += len;
}

bool foreign_register(trilog_t *T, const char *name, const char *types,
                      int32_t nin, int32_t nout, trilog_fn fn, void *ud) {
  int32_t id = atom_intern(T, name), arity = nin + nout;
  pred_bucket_t *b = pred_bucket_find_or_create(T, id, arity);
  if (b->count > 0 || b->dynamic)
    return false;
  if (!b->foreign) {
    if (T->foreign_count >= T->foreign_cap) {
      int32_t cap = T->foreign_cap ? T->foreign_cap * 2 : 8;
      T->foreign = mem_grow_n(T, T->foreign, (size_t)cap, sizeof(foreign_t));
      T->foreign_cap = cap;
    }
    mark_consulted(T, id, arity);
    b->foreign = ++T->foreign_count;
  }
  T->foreign[b->foreign - 1] = (foreign_t){.fn = fn,
                                           .ud = ud,
                                           .types = arena_strdup(T, types),
                                           .name = id,
                                           .nin = nin,
                                           .nout = nout};
  return true;
}

size_t foreign_error_ball(trilog_t *T, const char *formal) {
  const foreign_t *f = T->foreign_current;
  tterm_t *tmpl;
  int32_t nvars;
  const char **names;
  size_t term;
  if (parse_term_from_string(T, formal, &tmpl, &nvars, &names)) {
    term = heap_copy(T, tmpl, tmp_rename(T, nvars), 0);
  } else {
    size_t text[1] = {heap_new_atom(T, atom_intern(T, formal))};
    term = heap_new_struct(T, atom_intern(T, "syntax_error"), 1, text);
  }
  size_t pi[2] = {heap_new_atom(T, f->name), heap_new_int(T, f->nin + f->nout)};
  size_t args[2] = {term, heap_new_struct(T, atom_slash, 2, pi)};
  return heap_new_struct(T, atom_error, 2, args);
}

static int call_foreign(trilog_t *T, const foreign_t *f, size_t goal,
                        size_t *ball) {
  trilog_value_t in[TRILOG_MAX_FOREIGN_ARGS], out[TRILOG_MAX_FOREIGN_ARGS];
  size_t g = heap_deref(T, goal);
  size_t base = T->heap[g].tag == TAG_STR ? T->heap[g].as.ptr : 0;
  for (int32_t i = 0; i < f->nin; i++) {
    size_t a = heap_deref(T, base + 1 + (size_t)i);
    cell_t c = T->heap[a];
    if (c.tag == TAG_REF) {
      *ball = make_instantiation_error(T);
      return -1;
    }
    switch (f->types[i]) {
    case 'i':
      if (c.tag != TAG_INT) {
        *ball = make_type_error(T, "integer", a);
        return -1;
      }
      in[i].i = c.as.ival;
      break;
    case 'f':
      if (c.tag != TAG_INT && c.tag != TAG_FLT) {
        *ball = make_type_error(T, "number", a);
        return -1;
      }
      in[i].f = c.tag == TAG_INT ? (double)c.as.ival : c.as.fval;
      break;
    default:
      if (c.tag != TAG_ATOM) {
        *ball = make_type_error(T, "atom", a);
        return -1;
      }
      in[i].a = atom_name(T, c.as.atom_id);
      break;
    }
  }
  memset(out, 0, sizeof out);
  T->foreign_current = f;
  T->foreign_error = (size_t)-1;
  bool ok = f->fn(T, f->ud, in, out);
  T->foreign_current = NULL;
  if (T->foreign_error != (size_t)-1) {
    *ball = T->foreign_error;
    T->foreign_error = (size_t)-1;
    return -1;
  }
  if (!ok)
    return 0;
  for (int32_t j = 0; j < f->nout; j++) {
    size_t v;
    switch (f->types[f->nin + j]) {
    case 'i':
      v = heap_new_int(T, out[j].i);
      break;
    case 'f':
      if (!isfinite(out[j].f)) {
        *ball = make_evaluation_error(T, atom_intern(T, "undefined"));
        return -1;
      }
      v = heap_new_flt(T, out[j].f);
      break;
    default:
      if (!out[j].a)
        return 0;
      v = heap_new_atom(T, atom_intern(T, out[j].a));
      break;
    }
    if (!unify(T, base + 1 + (size_t)(f->nin + j), v))
      return 0;
  }
  return 1;
}

static int dispatch_builtin_(trilog_t *T, size_t goal, int *ok);

// Errors raised while a builtin runs name it as their context, unless it is
// one of the engine's own $-primitives.
static int dispatch_builtin(trilog_t *T, size_t goal, int *ok) {
  int32_t saved_name = T->error_pi_name, saved_arity = T->error_pi_arity;
  size_t g = heap_deref(T, goal);
  int32_t name = -1, arity = 0;
  if (T->heap[g].tag == TAG_ATOM) {
    name = T->heap[g].as.atom_id;
  } else if (T->heap[g].tag == TAG_STR) {
    name = T->heap[T->heap[g].as.ptr].as.func.atom_id;
    arity = T->heap[T->heap[g].as.ptr].as.func.arity;
  }
  if (name >= 0 && atom_name(T, name)[0] == '$')
    name = -1;
  T->error_pi_name = name;
  T->error_pi_arity = arity;
  int r = dispatch_builtin_(T, goal, ok);
  T->error_pi_name = saved_name;
  T->error_pi_arity = saved_arity;
  return r;
}

static int dispatch_builtin_(trilog_t *T, size_t goal, int *ok) {
  size_t g = heap_deref(T, goal);
  size_t f = 0;
  int32_t arity;
  int32_t id;
  if (T->heap[g].tag == TAG_ATOM) {
    arity = 0;
    id = T->heap[g].as.atom_id;
  } else if (T->heap[g].tag == TAG_STR) {
    f = T->heap[g].as.ptr;
    arity = T->heap[f].as.func.arity;
    id = T->heap[f].as.func.atom_id;
  } else {
    return 0;
  }

  if (arity == 0 && (id == atom_fail || id == atom_false)) {
    *ok = 0;
    return 1;
  }
  if (arity == 0 && id == atom_bang) {
    *ok = 1;
    return 1;
  }

  if (arity == 1 && id == atom_halt) {
    size_t d = heap_deref(T, f + 1);
    if (T->heap[d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    engine_halt(T, (int)T->heap[d].as.ival);
  }

  // flush_output/0 always flushes stdout specifically (not whichever stream
  // write/2 last targeted) - ISO's default.
  if (arity == 0 && id == atom_flush_output) {
    io_flush(T);
    *ok = 1;
    return 1;
  }

  if (arity == 2 && id == atom_is) {
    int aok = 1;
    size_t v = eval_arith(T, f + 2, &aok);
    *ok = aok && unify(T, f + 1, v);
    return 1;
  }
  if (arity == 2 && id == atom_unify_op) {
    *ok = unify(T, f + 1, f + 2);
    return 1;
  }
  if (arity == 2 && id == atom_unify_oc) {
    *ok = unify_with_occurs_check(T, f + 1, f + 2);
    return 1;
  }
  if (arity == 2 &&
      (id == atom_lt || id == atom_gt || id == atom_arith_le ||
       id == atom_arith_ge || id == atom_arith_eq || id == atom_arith_ne)) {
    int aok = 1;
    size_t av = eval_arith(T, f + 1, &aok);
    size_t bv = aok ? eval_arith(T, f + 2, &aok) : 0;
    if (!aok) {
      *ok = 0;
      return 1;
    }
    // exact int64 compare unless a float forces double comparison.
    int cmp;
    if (T->heap[av].tag == TAG_FLT || T->heap[bv].tag == TAG_FLT) {
      double a = arith_dbl(T, av), b = arith_dbl(T, bv);
      cmp = a < b ? -1 : a > b ? 1 : 0;
    } else {
      int64_t a = T->heap[av].as.ival, b = T->heap[bv].as.ival;
      cmp = a < b ? -1 : a > b ? 1 : 0;
    }
    if (id == atom_lt)
      *ok = cmp < 0;
    else if (id == atom_gt)
      *ok = cmp > 0;
    else if (id == atom_arith_le)
      *ok = cmp <= 0;
    else if (id == atom_arith_ge)
      *ok = cmp >= 0;
    else if (id == atom_arith_eq)
      *ok = cmp == 0;
    else
      *ok = cmp != 0;
    return 1;
  }
  if (arity == 2 &&
      (id == atom_term_eq || id == atom_term_ne || id == atom_term_lt ||
       id == atom_term_gt || id == atom_term_le || id == atom_term_ge)) {
    int c = term_compare(T, f + 1, f + 2);
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
    size_t a = heap_deref(T, f + 1);
    char c[2] = {(char)T->heap[a].as.ival, '\0'};
    io_write_str(T, c);
    *ok = 1;
    return 1;
  }
  if (arity == 1 && id == atom_get_code) {
    int c = io_read_char(T);
    *ok = unify(T, f + 1, heap_new_int(T, c == -1 ? -1 : c));
    return 1;
  }
  if (arity == 3 && id == atom_write_raw) {
    size_t target = heap_deref(T, f + 1);
    int flags = (int)T->heap[heap_deref(T, f + 3)].as.ival;
    int kind;
    void *h;
    if (!resolve_write_target(T, target, &kind, &h)) {
      *ok = 0;
      return 1;
    }
    if (kind == OUT_STDOUT)
      print_term_via(T, f + 2, flags, io_write_str);
    else if (kind == OUT_STDERR)
      print_term_via(T, f + 2, flags, io_write_err);
    else {
      T->file_target = h;
      print_term_via(T, f + 2, flags, emit_to_file);
    }
    *ok = 1;
    return 1;
  }
  if (arity == 3 && id == atom_open) {
    size_t path_d = heap_deref(T, f + 1);
    size_t mode_d = heap_deref(T, f + 2);
    if (T->heap[path_d].tag != TAG_ATOM || T->heap[mode_d].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    int32_t mode_id = T->heap[mode_d].as.atom_id;
    const char *fmode = mode_id == atom_mode_read     ? "r"
                        : mode_id == atom_mode_write  ? "w"
                        : mode_id == atom_mode_append ? "a"
                                                      : NULL;
    if (!fmode) {
      *ok = 0;
      return 1;
    }
    int stream_id =
        stream_open(T, atom_name(T, T->heap[path_d].as.atom_id), fmode);
    if (stream_id < 0) {
      *ok = 0;
      return 1;
    }
    size_t id_arg[1] = {heap_new_int(T, stream_id)};
    *ok = unify(T, f + 3, heap_new_struct(T, atom_stream, 1, id_arg));
    return 1;
  }
  if (arity == 1 && id == atom_close) {
    int id;
    if (!resolve_stream_id(T, f + 1, &id)) {
      *ok = 0;
      return 1;
    }
    stream_close(T, id);
    *ok = 1;
    return 1;
  }
  if (arity == 2 && id == atom_read_line_to_atom) {
    size_t sd = heap_deref(T, f + 1);
    int sid = -1;
    if ((T->heap[sd].tag != TAG_ATOM ||
         T->heap[sd].as.atom_id != atom_user_input) &&
        !resolve_stream_id(T, f + 1, &sid)) {
      *ok = 0;
      return 1;
    }
    char *got = read_whole_line(T, sid);
    size_t line;
    if (!got) {
      line = heap_new_atom(T, atom_end_of_file);
    } else {
      size_t len = strlen(got);
      while (len > 0 && (got[len - 1] == '\n' || got[len - 1] == '\r'))
        got[--len] = '\0';
      line = heap_new_atom(T, atom_intern(T, got));
    }
    *ok = unify(T, f + 2, line);
    return 1;
  }
  // Fragile: a directive in the consulted file runs via a nested
  // run_query while this one is still on the C stack, and sp is global.
  if (arity == 2 && id == atom_consult) {
    size_t path_d = heap_deref(T, f + 1);
    int32_t source;
    if (T->heap[path_d].tag != TAG_ATOM ||
        !consult_file(T, atom_name(T, T->heap[path_d].as.atom_id), &source)) {
      *ok = 0;
      return 1;
    }
    *ok = unify(T, f + 2, heap_new_atom(T, source));
    return 1;
  }
  if (arity == 2 && id == atom_source_path) {
    size_t d = heap_deref(T, f + 1);
    const char *path = T->heap[d].tag == TAG_ATOM
                           ? source_path(T, atom_name(T, T->heap[d].as.atom_id))
                           : NULL;
    *ok = path && unify(T, f + 2, heap_new_atom(T, atom_intern(T, path)));
    return 1;
  }
  if (arity == 1 && id == atom_loading_file) {
    *ok = T->consulting_atom >= 0 &&
          unify(T, f + 1, heap_new_atom(T, T->consulting_atom));
    return 1;
  }
  if (arity == 1 && id == atom_unload) {
    size_t d = heap_deref(T, f + 1);
    *ok = T->heap[d].tag == TAG_ATOM;
    if (*ok)
      db_unload(T, T->heap[d].as.atom_id);
    return 1;
  }
  if (arity == 1 && id == atom_dynamic) {
    size_t d = heap_deref(T, f + 1);
    if (T->heap[d].tag != TAG_STR) {
      *ok = 0;
      return 1;
    }
    size_t df = T->heap[d].as.ptr;
    if (T->heap[df].as.func.atom_id != atom_slash ||
        T->heap[df].as.func.arity != 2) {
      *ok = 0;
      return 1;
    }
    size_t name_d = heap_deref(T, df + 1);
    size_t arity_d = heap_deref(T, df + 2);
    if (T->heap[name_d].tag != TAG_ATOM || T->heap[arity_d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    dynamic_declare(T, T->heap[name_d].as.atom_id,
                    (int32_t)T->heap[arity_d].as.ival);
    *ok = 1;
    return 1;
  }
  if (arity == 2 && id == atom_undynamic) {
    size_t name_d = heap_deref(T, f + 1);
    size_t arity_d = heap_deref(T, f + 2);
    if (T->heap[name_d].tag != TAG_ATOM || T->heap[arity_d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    dynamic_undeclare(T, T->heap[name_d].as.atom_id,
                      (int32_t)T->heap[arity_d].as.ival);
    *ok = 1;
    return 1;
  }
  if (arity == 2 && id == atom_is_static_pred) {
    size_t name_d = heap_deref(T, f + 1);
    size_t arity_d = heap_deref(T, f + 2);
    if (T->heap[name_d].tag != TAG_ATOM || T->heap[arity_d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    int32_t pid = T->heap[name_d].as.atom_id,
            par = (int32_t)T->heap[arity_d].as.ival;
    *ok = was_consulted(T, pid, par);
    return 1;
  }
  if (arity == 1 && id == atom_prolog_flags) {
    // real values - this engine's actual int64_t arithmetic, not borrowed
    // numbers.
    size_t flags[][2] = {
        {heap_new_atom(T, atom_flag_bounded), heap_new_atom(T, atom_true)},
        {heap_new_atom(T, atom_flag_max_integer), heap_new_int(T, INT64_MAX)},
        {heap_new_atom(T, atom_flag_min_integer), heap_new_int(T, INT64_MIN)},
        {heap_new_atom(T, atom_flag_integer_rounding_function),
         heap_new_atom(T, atom_toward_zero)},
        {heap_new_atom(T, atom_flag_max_arity),
         heap_new_atom(T, atom_intern(T, "unbounded"))},
        {heap_new_atom(T, atom_flag_double_quotes),
         heap_new_atom(T, atom_chars_kw)},
        {heap_new_atom(T, atom_intern(T, "unknown")),
         heap_new_atom(T, atom_error)},
        {heap_new_atom(T, atom_intern(T, "char_conversion")),
         heap_new_atom(T, atom_intern(T, "off"))},
        {heap_new_atom(T, atom_intern(T, "debug")),
         heap_new_atom(T, atom_intern(T, "off"))},
    };
    size_t list = heap_new_atom(T, atom_nil);
    for (size_t i = sizeof flags / sizeof *flags; i-- > 0;) {
      size_t pair = heap_new_struct(T, atom_minus, 2, flags[i]);
      size_t cell[2] = {pair, list};
      list = heap_new_struct(T, atom_dot, 2, cell);
    }
    *ok = unify(T, f + 1, list);
    return 1;
  }
  // with_output_to/2's C half. capture_buf is a stack arena: each nested
  // capture pops back to its own start on $$capture_stop, so nesting works.
  if (arity == 0 && id == atom_capture_start) {
    if (T->capture_sp >= CAPTURE_STACK_MAX) {
      *ok = 0;
      return 1;
    }
    T->capture_starts[T->capture_sp++] = T->capture_pos;
    *ok = 1;
    return 1;
  }
  if (arity == 1 && id == atom_capture_stop) {
    if (T->capture_sp <= 0) {
      *ok = 0;
      return 1;
    }
    T->capture_sp--;
    size_t start = T->capture_starts[T->capture_sp];
    size_t result = heap_new_atom(
        T, atom_intern(T, T->capture_buf ? T->capture_buf + start : ""));
    if (T->capture_buf)
      T->capture_buf[start] = '\0';
    T->capture_pos = start;
    *ok = unify(T, f + 1, result);
    return 1;
  }
  if (arity == 2 && id == atom_copy_term) {
    int32_t nvars;
    tterm_t *tmpl = heap_to_template(T, f + 1, &nvars);
    if (!tmpl) {
      T->pending_error_ball = make_cyclic_term_error(T);
      *ok = 0;
      return 1;
    }
    *ok = unify(T, f + 2, heap_copy(T, tmpl, tmp_rename(T, nvars), 0));
    return 1;
  }
  if (arity == 2 && id == atom_clause_candidates) {
    idx_key_t want = key_of_goal(T, f + 1);
    size_t list = heap_new_atom(T, atom_nil);
    // These 15 stay purely native - a stray same-name assertz must never
    // silently shadow real unification/comparison.
    int32_t pid = want.pred_id, par = want.pred_arity;
    if ((par == 2 &&
         (pid == atom_unify_op || pid == atom_is || pid == atom_lt ||
          pid == atom_gt || pid == atom_arith_le || pid == atom_arith_ge ||
          pid == atom_arith_eq || pid == atom_arith_ne || pid == atom_term_eq ||
          pid == atom_term_ne || pid == atom_term_lt || pid == atom_term_gt ||
          pid == atom_term_le || pid == atom_term_ge || pid == atom_univ))) {
      *ok = unify(T, f + 2, list);
      return 1;
    }
    pred_bucket_t *bucket = pred_bucket_find(T, want.pred_id, want.pred_arity);
    for (int32_t bi = bucket ? bucket->count - 1 : -1; bi >= 0; bi--) {
      clause_t *c = &T->db[bucket->indices[bi]];
      if (keys_conflict(want, c->key))
        continue;
      size_t h2, b2;
      fresh_copy_clause(T, c, &h2, &b2);
      size_t pair_args[2] = {h2, b2};
      size_t pair = heap_new_struct(T, atom_minus, 2, pair_args);
      size_t cons_args[2] = {pair, list};
      list = heap_new_struct(T, atom_dot, 2, cons_args);
    }
    *ok = unify(T, f + 2, list);
    return 1;
  }
  if (arity == 1 && id == atom_choice_mark) {
    *ok = unify(T, f + 1, heap_new_int(T, (int64_t)T->sp));
    return 1;
  }
  if (arity == 1 && id == atom_cut_to) {
    size_t mark_d = heap_deref(T, f + 1);
    if (T->heap[mark_d].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    T->sp = (size_t)T->heap[mark_d].as.ival;
    *ok = 1;
    return 1;
  }
  if (arity == 2 && id == atom_term_to_atom) {
    size_t term_arg = heap_deref(T, f + 1);
    size_t atom_arg = heap_deref(T, f + 2);
    if (T->heap[term_arg].tag != TAG_REF) {
      T->tta_pos = 0;
      mem_reserve(T, &T->scratch, &T->scratch_cap, 1);
      ((char *)T->scratch)[0] = '\0';
      print_term_via(T, term_arg, PRINT_QUOTED,
                     tta_emit); // quoted, so it round-trips
      *ok = unify(T, atom_arg, heap_new_atom(T, atom_intern(T, T->scratch)));
      return 1;
    }
    if (T->heap[atom_arg].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    int32_t nvars;
    const char **names;
    tterm_t *t;
    if (!parse_term_from_string(T, atom_name(T, T->heap[atom_arg].as.atom_id),
                                &t, &nvars, &names)) {
      T->pending_error_ball = make_syntax_error(T);
      *ok = 0;
      return 1;
    }
    *ok = unify(T, term_arg, fresh_copy_term(T, t, nvars));
    return 1;
  }
  if (arity == 3 && id == atom_atom_to_term) {
    size_t atom_arg = heap_deref(T, f + 1);
    if (T->heap[atom_arg].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    int32_t nvars;
    const char **names;
    tterm_t *t;
    if (!parse_term_from_string(T, atom_name(T, T->heap[atom_arg].as.atom_id),
                                &t, &nvars, &names)) {
      T->pending_error_ball = make_syntax_error(T);
      *ok = 0;
      return 1;
    }
    size_t *rn = tmp_rename(T, nvars);
    size_t term_copy = heap_copy(T, t, rn, 0);
    // 'Name'=Var per named source variable; skips bare "_" and any slot
    // heap_copy never visited.
    size_t namevars = heap_new_atom(T, atom_nil);
    for (int32_t i = nvars - 1; i >= 0; i--) {
      if (!strcmp(names[i], "_") || rn[i] == (size_t)-1)
        continue;
      size_t pair_args[2] = {heap_new_atom(T, atom_intern(T, names[i])), rn[i]};
      size_t cons_args[2] = {heap_new_struct(T, atom_unify_op, 2, pair_args),
                             namevars};
      namevars = heap_new_struct(T, atom_dot, 2, cons_args);
    }
    *ok = unify(T, f + 2, term_copy) && unify(T, f + 3, namevars);
    return 1;
  }

  if (arity == 1 &&
      (id == atom_var || id == atom_kw_atom || id == atom_integer ||
       id == atom_kw_float || id == atom_compound)) {
    tag_t t = T->heap[heap_deref(T, f + 1)].tag;
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
    size_t term = heap_deref(T, f + 1);
    if (T->heap[term].tag != TAG_REF) {
      size_t name_val, arity_val;
      if (T->heap[term].tag == TAG_STR) {
        size_t tf = T->heap[term].as.ptr;
        name_val = heap_new_atom(T, T->heap[tf].as.func.atom_id);
        arity_val = heap_new_int(T, T->heap[tf].as.func.arity);
      } else {
        name_val = term;
        arity_val = heap_new_int(T, 0);
      }
      *ok = unify(T, f + 2, name_val) && unify(T, f + 3, arity_val);
      return 1;
    }
    size_t name_d = heap_deref(T, f + 2);
    size_t arity_d = heap_deref(T, f + 3);
    if (T->heap[name_d].tag == TAG_REF || T->heap[arity_d].tag == TAG_REF) {
      T->pending_error_ball = make_instantiation_error(T);
      *ok = 0;
      return 1;
    }
    int64_t ar =
        T->heap[arity_d].tag == TAG_INT ? T->heap[arity_d].as.ival : -1;
    if (T->heap[arity_d].tag != TAG_INT)
      T->pending_error_ball = make_type_error(T, "integer", arity_d);
    else if (ar < 0)
      T->pending_error_ball =
          make_domain_error(T, "not_less_than_zero", arity_d);
    else if (T->heap[name_d].tag == TAG_STR)
      T->pending_error_ball = make_type_error(T, "atomic", name_d);
    else if (ar > 0 && T->heap[name_d].tag != TAG_ATOM)
      T->pending_error_ball = make_type_error(T, "atom", name_d);
    else if ((uint64_t)ar > gc_max_live(T) || ar > INT32_MAX)
      T->pending_error_ball = make_resource_error(T, "memory");
    if (T->pending_error_ball != (size_t)-1) {
      *ok = 0;
      return 1;
    }
    if (ar == 0) {
      *ok = unify(T, term, name_d);
      return 1;
    }
    mem_reserve(T, &T->scratch, &T->scratch_cap, (size_t)ar * sizeof(size_t));
    size_t *args = T->scratch;
    for (int64_t i = 0; i < ar; i++)
      args[i] = heap_new_var(T);
    *ok = unify(
        T, term,
        heap_new_struct(T, T->heap[name_d].as.atom_id, (int32_t)ar, args));
    return 1;
  }
  if (arity == 3 && id == atom_arg) {
    size_t n_d = heap_deref(T, f + 1);
    size_t term = heap_deref(T, f + 2);
    if (T->heap[n_d].tag == TAG_REF || T->heap[term].tag == TAG_REF) {
      T->pending_error_ball = make_instantiation_error(T);
      *ok = 0;
      return 1;
    }
    if (T->heap[n_d].tag != TAG_INT)
      T->pending_error_ball = make_type_error(T, "integer", n_d);
    else if (T->heap[term].tag != TAG_STR)
      T->pending_error_ball = make_type_error(T, "compound", term);
    if (T->pending_error_ball != (size_t)-1) {
      *ok = 0;
      return 1;
    }
    int64_t n = T->heap[n_d].as.ival;
    size_t tf = T->heap[term].as.ptr;
    if (n < 1 || n > T->heap[tf].as.func.arity) {
      *ok = 0;
      return 1;
    }
    *ok = unify(T, f + 3, tf + (size_t)n);
    return 1;
  }
  if (arity == 3 && id == atom_skip_list) {
    size_t cell = heap_deref(T, f + 1);
    size_t tortoise = (size_t)-1;
    int64_t n = 0, power = 1, lam = 0;
    while (T->heap[cell].tag == TAG_STR) {
      size_t cf = T->heap[cell].as.ptr;
      if (T->heap[cf].as.func.arity != 2 ||
          T->heap[cf].as.func.atom_id != atom_dot)
        break;
      if (cf == tortoise)
        break; // cyclic: Tail is a list cell on the cycle
      if (lam == power) {
        tortoise = cf;
        power *= 2;
        lam = 0;
      }
      lam++;
      n++;
      cell = heap_deref(T, cf + 2);
    }
    *ok = unify(T, f + 2, heap_new_int(T, n)) && unify(T, f + 3, cell);
    return 1;
  }
  if (arity == 2 && id == atom_univ) {
    size_t term = heap_deref(T, f + 1);
    if (T->heap[term].tag != TAG_REF) {
      size_t list = heap_new_atom(T, atom_nil);
      if (T->heap[term].tag == TAG_STR) {
        size_t tf = T->heap[term].as.ptr;
        int32_t tarity = T->heap[tf].as.func.arity;
        for (int32_t i = tarity; i >= 1; i--) {
          size_t args2[2] = {tf + (size_t)i, list};
          list = heap_new_struct(T, atom_dot, 2, args2);
        }
        size_t head_args[2] = {heap_new_atom(T, T->heap[tf].as.func.atom_id),
                               list};
        list = heap_new_struct(T, atom_dot, 2, head_args);
      } else {
        size_t args2[2] = {term, list};
        list = heap_new_struct(T, atom_dot, 2, args2);
      }
      *ok = unify(T, f + 2, list);
      return 1;
    }
    size_t d = heap_deref(T, f + 2);
    *ok = 0;
    if (T->heap[d].tag == TAG_REF) {
      T->pending_error_ball = make_instantiation_error(T);
      return 1;
    }
    if (T->heap[d].tag == TAG_ATOM && T->heap[d].as.atom_id == atom_nil) {
      T->pending_error_ball = make_domain_error(T, "non_empty_list", d);
      return 1;
    }
    if (T->heap[d].tag != TAG_STR ||
        T->heap[T->heap[d].as.ptr].as.func.atom_id != atom_dot ||
        T->heap[T->heap[d].as.ptr].as.func.arity != 2) {
      T->pending_error_ball = make_type_error(T, "list", d);
      return 1;
    }
    size_t head = heap_deref(T, T->heap[d].as.ptr + 1);
    size_t cur = heap_deref(T, T->heap[d].as.ptr + 2);
    size_t *elems = NULL;
    int32_t ne = 0;
    while (T->heap[cur].tag == TAG_STR &&
           T->heap[T->heap[cur].as.ptr].as.func.atom_id == atom_dot &&
           T->heap[T->heap[cur].as.ptr].as.func.arity == 2) {
      if (ne == INT32_MAX) {
        T->pending_error_ball = make_resource_error(T, "memory");
        return 1;
      }
      mem_reserve(T, &T->scratch, &T->scratch_cap, (ne + 1) * sizeof(size_t));
      elems = T->scratch;
      elems[ne++] = heap_deref(T, T->heap[cur].as.ptr + 1);
      cur = heap_deref(T, T->heap[cur].as.ptr + 2);
    }
    if (T->heap[cur].tag == TAG_REF || T->heap[head].tag == TAG_REF)
      T->pending_error_ball = make_instantiation_error(T);
    else if (T->heap[cur].tag != TAG_ATOM ||
             T->heap[cur].as.atom_id != atom_nil)
      T->pending_error_ball = make_type_error(T, "list", d);
    else if (ne == 0 && T->heap[head].tag == TAG_STR)
      T->pending_error_ball = make_type_error(T, "atomic", head);
    else if (ne > 0 && T->heap[head].tag != TAG_ATOM)
      T->pending_error_ball = make_type_error(T, "atom", head);
    if (T->pending_error_ball != (size_t)-1)
      return 1;
    size_t built =
        ne == 0 ? head
                : heap_new_struct(T, T->heap[head].as.atom_id, ne, elems);
    *ok = unify(T, term, built);
    return 1;
  }
  if (arity == 2 && id == atom_atom_codes) {
    size_t a = heap_deref(T, f + 1);
    if (T->heap[a].tag == TAG_ATOM) {
      *ok = unify(T, f + 2,
                  codes_from_cstr(T, atom_name(T, T->heap[a].as.atom_id)));
      return 1;
    }
    int incomplete = 0;
    char *text = codes_text(T, f + 2, SIZE_MAX, &incomplete);
    if (!text) {
      if (incomplete)
        T->pending_error_ball = make_instantiation_error(T);
      *ok = 0;
      return 1;
    }
    *ok = unify(T, f + 1, heap_new_atom(T, atom_intern(T, text)));
    return 1;
  }
  if (arity == 2 && id == atom_number_codes) {
    size_t a = heap_deref(T, f + 1);
    if (T->heap[a].tag == TAG_INT) {
      char buf[32];
      fmt(buf, sizeof buf, "%lld", (long long)T->heap[a].as.ival);
      *ok = unify(T, f + 2, codes_from_cstr(T, buf));
      return 1;
    }
    if (T->heap[a].tag == TAG_FLT) {
      char buf[64];
      fmt(buf, sizeof buf, "%g", T->heap[a].as.fval);
      *ok = unify(T, f + 2, codes_from_cstr(T, buf));
      return 1;
    }
    int incomplete = 0;
    char *buf = codes_text(T, f + 2, 63, &incomplete);
    if (!buf) {
      if (incomplete)
        T->pending_error_ball = make_instantiation_error(T);
      *ok = 0;
      return 1;
    }
    const char *end;
    int64_t iv;
    bool fits = parse_int(buf, &end, &iv);
    if (*end == '\0' && end != buf) {
      if (!fits) {
        size_t args[1] = {heap_new_atom(
            T, atom_intern(T, iv > 0 ? "max_integer" : "min_integer"))};
        T->pending_error_ball = make_error(
            T, heap_new_struct(T, atom_intern(T, "representation_error"), 1,
                               args));
        *ok = 0;
        return 1;
      }
      *ok = unify(T, f + 1, heap_new_int(T, iv));
      return 1;
    }
    char *fend;
    double dv = strtod(buf, &fend);
    *ok =
        (*fend == '\0' && fend != buf) && unify(T, f + 1, heap_new_flt(T, dv));
    return 1;
  }
  return 0;
}

static void rename_init(size_t *rename, int32_t n) {
  for (int32_t i = 0; i < n; i++)
    rename[i] = (size_t)-1;
}

size_t query_error_ball(trilog_t *T) { return T->uncaught_ball; }

size_t query_binding(trilog_t *T, int32_t i) { return T->solution_rename[i]; }

static int do_throw(trilog_t *T, size_t ball, size_t *cn_out,
                    size_t *active_catch_ptr) {
  int32_t nballvars;
  tterm_t *ball_template = heap_to_template(T, ball, &nballvars);
  if (!ball_template)
    ball_template = heap_to_template(T, make_cyclic_term_error(T), &nballvars);
  size_t idx = *active_catch_ptr;
  for (;;) {
    if (idx == (size_t)-1) {
      T->uncaught_ball = ball;
      return 0;
    }
    catch_frame_t entry = T->catch_stack[idx];
    heap_release(T, entry.heap_mark);
    trail_release(T, entry.trail_mark);
    T->sp = entry.sp_at_entry;
    size_t ball_copy = fresh_copy_term(T, ball_template, nballvars);
    if (unify(T, entry.catcher, ball_copy)) {
      *active_catch_ptr = entry.outer_active_catch;
      *cn_out = build_conj_tail(T, &entry.recovery, 1, entry.continuation);
      return 1;
    }
    idx = entry.outer_active_catch;
  }
}

static query_result_t run_query_body(trilog_t *T, tterm_t **goals,
                                     int32_t ngoals, int32_t nvars,
                                     solution_fn on_solution, void *ud);

query_result_t run_query(trilog_t *T, tterm_t **goals, int32_t ngoals,
                         int32_t nvars, solution_fn on_solution, void *ud) {
  size_t saved_base = T->query_sp_base;
  size_t *saved_rename = T->solution_rename;
  T->query_sp_base = T->sp;
  T->query_depth++;
  T->uncaught_ball = (size_t)-1;
  query_result_t r = run_query_body(T, goals, ngoals, nvars, on_solution, ud);
  T->query_depth--;
  T->sp = T->query_sp_base;
  T->query_sp_base = saved_base;
  T->solution_rename = saved_rename;
  return r;
}

static query_result_t run_query_body(trilog_t *T, tterm_t **goals,
                                     int32_t ngoals, int32_t nvars,
                                     solution_fn on_solution, void *ud) {
  int depth = T->query_depth;
  if (depth > T->query_bufs_len) {
    T->query_bufs =
        mem_grow_n(T, T->query_bufs, (size_t)depth, sizeof *T->query_bufs);
    for (int i = T->query_bufs_len; i < depth; i++)
      T->query_bufs[i] = (struct query_buf){0};
    T->query_bufs_len = depth;
  }
  struct query_buf *qb = &T->query_bufs[depth - 1];
  size_t nrename = (size_t)(nvars > 0 ? nvars : 1);
  mem_reserve(T, (void **)&qb->p, &qb->cap,
              (nrename + (size_t)(ngoals > 0 ? ngoals : 1)) * sizeof(size_t));
  size_t *rename = qb->p;
  rename_init(rename, nvars);

  size_t hmark = heap_mark(T), tmark = trail_mark(T), cut_barrier = 0;
  int any_found = 0;

  size_t *qgoals = qb->p + nrename;
  for (int32_t i = 0; i < ngoals; i++)
    qgoals[i] = heap_copy_goal(T, goals[i], rename, cut_barrier);
  size_t cn = build_conj_tail(T, qgoals, ngoals, heap_new_atom(T, atom_true));

  size_t first, rest;
  int32_t clause_idx = 0;
  idx_key_t caller_key = {.kind = IDX_ANY};
  size_t active_catch = (size_t)-1;
  int predicate_known = 0;

A:
  if (T->yield_fn && ++T->yield_count >= T->yield_every) {
    T->yield_count = 0;
    if (!T->yield_fn(T, T->sp, T->yield_ud))
      engine_abort(T);
  }
  // FIXME: GC only knows this query's roots, so collecting inside a nested
  // query would move or free the outer queries' live terms
  // Nested queries skip GC instead; the real fix is GC marking
  // and relocating every running query's roots.
  if (T->query_depth == 1) {
    gc_maybe_run(T, &cn, T->stack, T->sp, rename, nvars, &active_catch);
    if (gc_heap_exhausted(T)) {
      if (do_throw(T, make_resource_error(T, "memory"), &cn, &active_catch))
        goto A;
      return QUERY_ERROR;
    }
  }
  {
    // check cn == true before decompose, or a mid-clause true goal
    // wrongly ends the query.
    size_t cnd = heap_deref(T, cn);
    if (T->heap[cnd].tag == TAG_ATOM && T->heap[cnd].as.atom_id == atom_true) {
      any_found = 1;
      T->solution_rename = rename;
      if (!on_solution(ud, T->sp != T->query_sp_base))
        return QUERY_TRUE;
      goto C;
    }
  }
  decompose(T, cn, &first, &rest);
  {
    size_t fd = heap_deref(T, first);
    if (T->heap[fd].tag == TAG_ATOM && T->heap[fd].as.atom_id == atom_true) {
      cn = rest;
      goto A;
    }
    if (T->heap[fd].tag == TAG_STR) {
      size_t cf = T->heap[fd].as.ptr;
      int32_t fd_arity = T->heap[cf].as.func.arity;
      int32_t fd_id = T->heap[cf].as.func.atom_id;
      if (fd_arity == 2 && fd_id == atom_comma) {
        size_t inner_first = heap_deref(T, cf + 1);
        size_t inner_rest = heap_deref(T, cf + 2);
        size_t new_rest = build_conj_tail(T, &inner_rest, 1, rest);
        cn = build_conj_tail(T, &inner_first, 1, new_rest);
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_call) {
        size_t goal = heap_rebake_cuts(T, heap_deref(T, cf + 1), T->sp);
        cn = build_conj_tail(T, &goal, 1, rest);
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_cut) {
        T->sp = (size_t)T->heap[heap_deref(T, cf + 1)].as.ival;
        cn = rest;
        goto A;
      }
      if (fd_arity == 3 && fd_id == atom_catch) {
        size_t goal = heap_rebake_cuts(T, heap_deref(T, cf + 1), T->sp);
        size_t catcher = heap_deref(T, cf + 2);
        size_t recovery = heap_deref(T, cf + 3);
        size_t idx = catch_stack_push(
            T, (catch_frame_t){.heap_mark = heap_mark(T),
                               .trail_mark = trail_mark(T),
                               .sp_at_entry = T->sp,
                               .catcher = catcher,
                               .recovery = recovery,
                               .continuation = rest,
                               .outer_active_catch = active_catch});
        active_catch = idx;
        size_t uncatch_arg[1] = {heap_new_int(T, (int64_t)idx)};
        size_t uncatch_term = heap_new_struct(T, atom_uncatch, 1, uncatch_arg);
        size_t after_goal = build_conj_tail(T, &uncatch_term, 1, rest);
        cn = build_conj_tail(T, &goal, 1, after_goal);
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_uncatch) {
        size_t idx = (size_t)T->heap[heap_deref(T, cf + 1)].as.ival;
        active_catch = T->catch_stack[idx].outer_active_catch;
        cn = rest;
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_throw) {
        size_t ball = heap_deref(T, cf + 1);
        if (do_throw(T, ball, &cn, &active_catch))
          goto A;
        return QUERY_ERROR;
      }
      // $$-prefixed: raw, unprotected primitives; boot/core.pl's public
      // assertz/asserta/retract check staticity first, then delegate here.
      if (fd_arity == 1 && (fd_id == atom_assertz || fd_id == atom_assert ||
                            fd_id == atom_asserta)) {
        size_t clause = heap_deref(T, cf + 1);
        size_t body_refs[MAX_ASSERT_GOALS];
        size_t head, all_terms[1 + MAX_ASSERT_GOALS];
        int32_t nbody;
        split_clause(T, clause, &head, body_refs, &nbody);
        all_terms[0] = head;
        for (int32_t i = 0; i < nbody; i++)
          all_terms[1 + i] = body_refs[i];

        tterm_t **templates =
            arena_alloc(T, (size_t)(1 + nbody) * sizeof(tterm_t *));
        int32_t nvars;
        if (!heap_terms_to_templates(T, all_terms, 1 + nbody, templates,
                                     &nvars)) {
          if (do_throw(T, make_cyclic_term_error(T), &cn, &active_catch))
            goto A;
          return QUERY_ERROR;
        }

        if (fd_id == atom_asserta)
          db_add_front(T, templates[0], nbody > 0 ? templates + 1 : NULL, nbody,
                       nvars);
        else
          db_add(T, templates[0], nbody > 0 ? templates + 1 : NULL, nbody,
                 nvars, 0);
        cn = rest;
        goto A;
      }
      if (fd_arity == 1 && fd_id == atom_retract) {
        size_t clause = heap_deref(T, cf + 1);
        size_t want_head, want_body;
        split_clause_whole(T, clause, &want_head, &want_body);

        idx_key_t want_key = key_of_goal(T, want_head);
        pred_bucket_t *bucket =
            pred_bucket_find(T, want_key.pred_id, want_key.pred_arity);
        size_t rmark = heap_mark(T), rtmark = trail_mark(T);
        int found = 0;
        for (int32_t bi = 0; bucket && bi < bucket->count; bi++) {
          int32_t ci = bucket->indices[bi];
          if (keys_conflict(want_key, T->db[ci].key))
            continue;
          trail_release(T, rtmark);
          heap_release(T, rmark);
          clause_t *c = &T->db[ci];
          size_t *rn = tmp_rename(T, c->nvars);
          size_t h = heap_copy(T, c->head, rn, 0);
          if (!unify(T, h, want_head))
            continue;
          size_t *bodies = tmp_goals(T, c->nbody);
          for (int32_t i = 0; i < c->nbody; i++)
            bodies[i] = heap_copy(T, c->body[i], rn, 0);
          size_t body_whole = body_as_term(T, bodies, c->nbody);
          if (!unify(T, body_whole, want_body))
            continue;
          db_remove_at(T, ci);
          found = 1;
          break;
        }
        if (!found) {
          trail_release(T, rtmark);
          heap_release(T, rmark);
          goto C;
        }
        cn = rest;
        goto A;
      }
    }
    int ok;
    if (dispatch_builtin(T, first, &ok)) {
      if (ok) {
        cn = rest;
        goto A;
      }
      if (T->pending_error_ball != (size_t)-1) {
        size_t ball = T->pending_error_ball;
        T->pending_error_ball = (size_t)-1;
        if (do_throw(T, ball, &cn, &active_catch))
          goto A;
        return QUERY_ERROR;
      }
      goto C;
    }
  }
  {
    idx_key_t dk = key_of_goal(T, first);
    pred_bucket_t *dbk = pred_bucket_find(T, dk.pred_id, dk.pred_arity);
    if (dbk && dbk->foreign) {
      size_t ball;
      int r = call_foreign(T, &T->foreign[dbk->foreign - 1], first, &ball);
      if (r > 0) {
        cn = rest;
        goto A;
      }
      if (r == 0)
        goto C;
      if (do_throw(T, ball, &cn, &active_catch))
        goto A;
      return QUERY_ERROR;
    }
    if (dbk && dbk->dynamic) {
      size_t args[1] = {first};
      size_t dyn_goal = heap_new_struct(T, atom_dyn_call, 1, args);
      cn = build_conj_tail(T, &dyn_goal, 1, rest);
      goto A;
    }
  }
  clause_idx = 0;
  tmark = trail_mark(T);
  hmark = heap_mark(T);
  cut_barrier = T->sp;
  caller_key = key_of_goal(T, first);
  predicate_known = 0;

B: {
  pred_bucket_t *bk =
      pred_bucket_find(T, caller_key.pred_id, caller_key.pred_arity);
  predicate_known = bk && bk->count > 0;
  int32_t next = next_candidate(T, clause_idx, caller_key);
  if (next < 0) {
    if (clause_idx > 0)
      goto C; // resuming a call that already matched: out of clauses is a
              // plain fail, even if the predicate was abolished meanwhile
    if (!predicate_known &&
        is_dynamic(T, caller_key.pred_id, caller_key.pred_arity))
      goto C; // declared dynamic - no clauses is a normal fail, not
              // existence_error
    if (!predicate_known) {
      // pred_id == -1: `first` was never callable (key_of_goal's "no key"
      // sentinel) - feeding that into make_existence_error would
      // heap_new_atom(-1) and later corrupt the heap.
      size_t first_d = heap_deref(T, first);
      size_t ball;
      if (caller_key.pred_id != -1)
        ball = make_existence_error(T, "procedure", caller_key.pred_id,
                                    caller_key.pred_arity);
      else if (T->heap[first_d].tag == TAG_REF)
        ball = make_instantiation_error(T);
      else
        ball = make_type_error(T, "callable", first_d);
      if (do_throw(T, ball, &cn, &active_catch))
        goto A;
      return QUERY_ERROR;
    }
    goto C;
  }
  clause_idx = next;
}
  {
    clause_t *c = &T->db[clause_idx];
    clause_idx++;
    trail_release(T, tmark);
    heap_release(T, hmark);

    size_t *r2 = tmp_rename(T, c->nvars);
    size_t h = heap_copy(T, c->head, r2, cut_barrier);

    if (!unify(T, h, first))
      goto B;

    size_t *bodies = tmp_goals(T, c->nbody);
    for (int32_t i = 0; i < c->nbody; i++)
      bodies[i] = heap_copy_goal(T, c->body[i], r2, cut_barrier);
    size_t newcn = build_conj_tail(T, bodies, c->nbody, rest);

    if (!no_more_candidates(T, clause_idx, caller_key))
      stack_push(T, (frame_t){.goals = cn,
                              .clause_idx = clause_idx,
                              .heap_mark = hmark,
                              .trail_mark = tmark,
                              .cut_barrier = cut_barrier,
                              .active_catch = active_catch});
    cn = newcn;
    goto A;
  }

C:
  if (T->sp == T->query_sp_base)
    return any_found ? QUERY_TRUE : QUERY_FALSE;
  {
    frame_t f = T->stack[--T->sp];
    cn = f.goals;
    clause_idx = f.clause_idx;
    hmark = f.heap_mark;
    tmark = f.trail_mark;
    cut_barrier = f.cut_barrier;
    active_catch = f.active_catch;
    decompose(T, cn, &first, &rest);
    // release before keying, or a stale binding from the last clause
    // tried wrongly indexes out every other clause.
    trail_release(T, tmark);
    heap_release(T, hmark);
    caller_key = key_of_goal(T, first);
    goto B;
  }
}

static int op_lookup(trilog_t *T, int32_t name_atom_id, int want_infix,
                     int *pri, int *assoc_code) {
  pred_bucket_t *b = pred_bucket_find(T, atom_op_pred, 3);
  if (!b)
    return 0;
  int found = 0;
  for (int32_t i = 0; i < b->count; i++) {
    tterm_t *head = T->db[b->indices[i]].head;
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

int op_lookup_infix(trilog_t *T, int32_t name_atom_id, int *pri,
                    int *assoc_code) {
  return op_lookup(T, name_atom_id, 1, pri, assoc_code);
}
int op_lookup_prefix(trilog_t *T, int32_t name_atom_id, int *pri,
                     int *assoc_code) {
  return op_lookup(T, name_atom_id, 0, pri, assoc_code);
}

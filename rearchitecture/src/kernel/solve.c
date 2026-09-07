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

static size_t pending_error_ball = (size_t)-1;

static size_t make_error(size_t formal) {
  size_t args[2] = {formal, heap_new_var()};
  return heap_new_struct(atom_intern("error"), 2, args);
}
static size_t make_instantiation_error(void) {
  return make_error(heap_new_atom(atom_intern("instantiation_error")));
}
static size_t make_type_error(const char *type, size_t culprit) {
  size_t args[2] = {heap_new_atom(atom_intern(type)), culprit};
  return make_error(heap_new_struct(atom_intern("type_error"), 2, args));
}
static size_t make_existence_error(const char *obj_type, int32_t pred_id,
                                   int32_t pred_arity) {
  size_t pi_args[2] = {heap_new_atom(pred_id), heap_new_int(pred_arity)};
  size_t args[2] = {heap_new_atom(atom_intern(obj_type)),
                    heap_new_struct(atom_intern("/"), 2, pi_args)};
  return make_error(heap_new_struct(atom_intern("existence_error"), 2, args));
}

void solve_init(void) {
  atom_true = atom_intern("true");
  atom_comma = atom_intern(",");
  atom_dot = atom_intern(".");
  atom_nil = atom_intern("[]");
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
  db[db_count++] = (clause_t){.head = head,
                              .body = body,
                              .nbody = nbody,
                              .nvars = nvars,
                              .key = key_of_template(head)};
}

static void db_add_front(tterm_t *head, tterm_t **body, int32_t nbody,
                         int32_t nvars) {
  db_ensure_cap();
  memmove(&db[1], &db[0], (size_t)db_count * sizeof(clause_t));
  db_count++;
  db[0] = (clause_t){.head = head,
                     .body = body,
                     .nbody = nbody,
                     .nvars = nvars,
                     .key = key_of_template(head)};
}

static void db_remove_at(int32_t idx) {
  memmove(&db[idx], &db[idx + 1],
          (size_t)(db_count - idx - 1) * sizeof(clause_t));
  db_count--;
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
    if (!strcmp(atom_name(heap[f].as.func.atom_id), ":-") &&
        heap[f].as.func.arity == 2) {
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
    if (!strcmp(atom_name(heap[f].as.func.atom_id), ":-") &&
        heap[f].as.func.arity == 2) {
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
    const char *name = atom_name(heap[f].as.func.atom_id);
    if (arity == 2) {
      int64_t a = eval_arith(f + 1, ok);
      int64_t b = *ok ? eval_arith(f + 2, ok) : 0;
      if (!*ok)
        return 0;
      if (!strcmp(name, "+"))
        return a + b;
      if (!strcmp(name, "-"))
        return a - b;
      if (!strcmp(name, "*"))
        return a * b;
      if (!strcmp(name, "/") || !strcmp(name, "//") || !strcmp(name, "mod")) {
        if (b == 0) {
          *ok = 0;
          return 0;
        } // would be a C-level SIGFPE otherwise
        if (!strcmp(name, "mod"))
          return ((a % b) + b) % b; // ISO: result takes the sign of the divisor
        return a / b;
      }
      if (!strcmp(name, "min"))
        return a < b ? a : b;
      if (!strcmp(name, "max"))
        return a > b ? a : b;
    } else if (arity == 1) {
      int64_t a = eval_arith(f + 1, ok);
      if (!*ok)
        return 0;
      if (!strcmp(name, "-"))
        return -a;
      if (!strcmp(name, "+"))
        return a;
      if (!strcmp(name, "abs"))
        return a < 0 ? -a : a;
      if (!strcmp(name, "sign"))
        return (a > 0) - (a < 0);
      if (!strcmp(name, "floor") || !strcmp(name, "ceiling") ||
          !strcmp(name, "round") || !strcmp(name, "truncate"))
        return a;
    }
    pending_error_ball = make_type_error(
        "evaluable",
        heap_new_struct(atom_intern("/"), 2,
                        (size_t[2]){heap_new_atom(heap[f].as.func.atom_id),
                                    heap_new_int(arity)}));
    *ok = 0;
    return 0;
  }
  if (heap[r].tag == TAG_ATOM) {
    pending_error_ball = make_type_error(
        "evaluable",
        heap_new_struct(
            atom_intern("/"), 2,
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
    int c =
        strcmp(atom_name(heap[a].as.atom_id), atom_name(heap[b].as.atom_id));
    return c < 0 ? -1 : (c > 0 ? 1 : 0);
  }
  default: {
    size_t af = heap[a].as.ptr, bf = heap[b].as.ptr;
    int32_t aa = heap[af].as.func.arity, ba = heap[bf].as.func.arity;
    if (aa != ba)
      return aa < ba ? -1 : 1;
    int nc = strcmp(atom_name(heap[af].as.func.atom_id),
                    atom_name(heap[bf].as.func.atom_id));
    if (nc != 0)
      return nc < 0 ? -1 : 1;
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
  if (heap[sf].as.func.atom_id != atom_intern("$stream") ||
      heap[sf].as.func.arity != 1)
    return 0;
  size_t idv = heap_deref(sf + 1);
  if (heap[idv].tag != TAG_INT)
    return 0;
  *id_out = (int)heap[idv].as.ival;
  return 1;
}

static int resolve_output_handle(size_t arg, void **handle_out) {
  size_t s = heap_deref(arg);
  if (heap[s].tag == TAG_ATOM) {
    const char *n = atom_name(heap[s].as.atom_id);
    if (strcmp(n, "user_output") && strcmp(n, "user"))
      return 0;
    *handle_out = NULL;
    return 1;
  }
  int id;
  void *h;
  if (!resolve_stream_id(arg, &id) || !(h = stream_handle(id)))
    return 0;
  *handle_out = h;
  return 1;
}

// Redirects write_str into a file handle for the duration of one print.
static void *redirect_handle;
static void redirect_write_str(const char *str, void *ud) {
  (void)ud;
  io_file_write(redirect_handle, str);
}
static void print_term_to(void *handle, size_t r, int quoted) {
  io_hooks_t saved = io_hooks_get();
  redirect_handle = handle;
  io_hooks_t tmp = saved;
  tmp.write_str = redirect_write_str;
  io_hooks_replace(tmp);
  if (quoted)
    print_term_quoted(r);
  else
    print_term(r);
  io_hooks_restore(saved);
}

// Same trick, relayed to the write_err hook instead - for the one term
// (an uncaught exception's ball) that belongs on the error stream.
static void err_relay_write_str(const char *str, void *ud) {
  (void)ud;
  io_write_err(str);
}
static void print_term_err(size_t r) {
  io_hooks_t saved = io_hooks_get();
  io_hooks_t tmp = saved;
  tmp.write_str = err_relay_write_str;
  io_hooks_replace(tmp);
  print_term(r);
  io_hooks_restore(saved);
}

// with_output_to/2's C half (see boot/core.pl). Not reentrant: a nested
// with_output_to before the outer's $capture_stop mixes both into one buffer.
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

static int dispatch_builtin(size_t goal, int *ok) {
  size_t g = heap_deref(goal);
  size_t f = 0;
  int32_t arity;
  const char *name;
  if (heap[g].tag == TAG_ATOM) {
    arity = 0;
    name = atom_name(heap[g].as.atom_id);
  } else if (heap[g].tag == TAG_STR) {
    f = heap[g].as.ptr;
    arity = heap[f].as.func.arity;
    name = atom_name(heap[f].as.func.atom_id);
  } else {
    return 0;
  }

  if (arity == 2 && !strcmp(name, "is")) {
    int aok = 1;
    int64_t v = eval_arith(f + 2, &aok);
    *ok = aok && unify(f + 1, heap_new_int(v));
    return 1;
  }
  if (arity == 2 && !strcmp(name, "=")) {
    *ok = unify(f + 1, f + 2);
    return 1;
  }
  if (arity == 2 &&
      (!strcmp(name, "<") || !strcmp(name, ">") || !strcmp(name, "=<") ||
       !strcmp(name, ">=") || !strcmp(name, "=:=") || !strcmp(name, "=\\="))) {
    int aok = 1;
    int64_t a = eval_arith(f + 1, &aok);
    int64_t b = aok ? eval_arith(f + 2, &aok) : 0;
    if (!aok) {
      *ok = 0;
      return 1;
    }
    if (!strcmp(name, "<"))
      *ok = a < b;
    else if (!strcmp(name, ">"))
      *ok = a > b;
    else if (!strcmp(name, "=<"))
      *ok = a <= b;
    else if (!strcmp(name, ">="))
      *ok = a >= b;
    else if (!strcmp(name, "=:="))
      *ok = a == b;
    else
      *ok = a != b;
    return 1;
  }
  if (arity == 1 && !strcmp(name, "put_code")) {
    size_t a = heap_deref(f + 1);
    char c[2] = {(char)heap[a].as.ival, '\0'};
    io_write_str(c);
    *ok = 1;
    return 1;
  }
  if (arity == 1 && !strcmp(name, "get_code")) {
    int c = io_read_char();
    *ok = unify(f + 1, heap_new_int(c == -1 ? -1 : c));
    return 1;
  }
  if (arity == 1 && !strcmp(name, "get_char")) {
    int c = io_read_char();
    size_t r;
    if (c == -1)
      r = heap_new_atom(atom_intern("end_of_file"));
    else {
      char buf[2] = {(char)c, '\0'};
      r = heap_new_atom(atom_intern(buf));
    }
    *ok = unify(f + 1, r);
    return 1;
  }
  if (arity == 0 && (!strcmp(name, "fail") || !strcmp(name, "false"))) {
    *ok = 0;
    return 1;
  }
  if (arity == 0 && !strcmp(name, "nl")) {
    io_write_str("\n");
    *ok = 1;
    return 1;
  }
  if (arity == 1 && !strcmp(name, "nl")) {
    void *h;
    if (!resolve_output_handle(f + 1, &h)) {
      *ok = 0;
      return 1;
    }
    if (h)
      io_file_write(h, "\n");
    else
      io_write_str("\n");
    *ok = 1;
    return 1;
  }
  if (arity == 1 && (!strcmp(name, "write") || !strcmp(name, "writeq"))) {
    if (!strcmp(name, "writeq"))
      print_term_quoted(f + 1);
    else
      print_term(f + 1);
    *ok = 1;
    return 1;
  }
  if (arity == 2 && (!strcmp(name, "write") || !strcmp(name, "writeq"))) {
    void *h;
    if (!resolve_output_handle(f + 1, &h)) {
      *ok = 0;
      return 1;
    }
    int quoted = !strcmp(name, "writeq");
    if (h)
      print_term_to(h, f + 2, quoted);
    else if (quoted)
      print_term_quoted(f + 2);
    else
      print_term(f + 2);
    *ok = 1;
    return 1;
  }
  if (arity == 3 && !strcmp(name, "open")) {
    size_t path_d = heap_deref(f + 1);
    size_t mode_d = heap_deref(f + 2);
    if (heap[path_d].tag != TAG_ATOM || heap[mode_d].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    const char *mn = atom_name(heap[mode_d].as.atom_id);
    const char *fmode = !strcmp(mn, "read")     ? "r"
                        : !strcmp(mn, "write")  ? "w"
                        : !strcmp(mn, "append") ? "a"
                                                : NULL;
    if (!fmode) {
      *ok = 0;
      return 1;
    }
    int id = stream_open(atom_name(heap[path_d].as.atom_id), fmode);
    if (id < 0) {
      *ok = 0;
      return 1;
    }
    size_t id_arg[1] = {heap_new_int(id)};
    *ok = unify(f + 3, heap_new_struct(atom_intern("$stream"), 1, id_arg));
    return 1;
  }
  if (arity == 1 && !strcmp(name, "close")) {
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
  if (arity == 1 && !strcmp(name, "consult")) {
    size_t path_d = heap_deref(f + 1);
    if (heap[path_d].tag != TAG_ATOM) {
      *ok = 0;
      return 1;
    }
    *ok = consult_file(atom_name(heap[path_d].as.atom_id));
    return 1;
  }
  if (arity == 0 && !strcmp(name, "$capture_start")) {
    capture_saved = io_hooks_get();
    capture_pos = 0;
    capture_buf[0] = '\0';
    io_hooks_t tmp = capture_saved;
    tmp.write_str = capture_write_str;
    io_hooks_replace(tmp);
    *ok = 1;
    return 1;
  }
  if (arity == 1 && !strcmp(name, "$capture_stop")) {
    io_hooks_restore(capture_saved);
    *ok = unify(f + 1, heap_new_atom(atom_intern(capture_buf)));
    return 1;
  }

  if (arity == 1 && (!strcmp(name, "var") || !strcmp(name, "nonvar") ||
                     !strcmp(name, "atom") || !strcmp(name, "atomic") ||
                     !strcmp(name, "number") || !strcmp(name, "integer") ||
                     !strcmp(name, "float") || !strcmp(name, "compound") ||
                     !strcmp(name, "callable"))) {
    tag_t t = heap[heap_deref(f + 1)].tag;
    if (!strcmp(name, "var"))
      *ok = t == TAG_REF;
    else if (!strcmp(name, "nonvar"))
      *ok = t != TAG_REF;
    else if (!strcmp(name, "atom"))
      *ok = t == TAG_ATOM;
    else if (!strcmp(name, "number"))
      *ok = t == TAG_INT || t == TAG_FLT;
    else if (!strcmp(name, "integer"))
      *ok = t == TAG_INT;
    else if (!strcmp(name, "float"))
      *ok = t == TAG_FLT;
    else if (!strcmp(name, "atomic"))
      *ok = t == TAG_ATOM || t == TAG_INT || t == TAG_FLT;
    else if (!strcmp(name, "compound"))
      *ok = t == TAG_STR;
    else
      *ok = t == TAG_ATOM || t == TAG_STR; // callable
    return 1;
  }

  if (arity == 3 && !strcmp(name, "functor")) {
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
  if (arity == 3 && !strcmp(name, "arg")) {
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
  if (arity == 2 && !strcmp(name, "=..")) {
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
  if (arity == 3 && !strcmp(name, "compare")) {
    int c = term_compare(f + 2, f + 3);
    *ok = unify(f + 1,
                heap_new_atom(atom_intern(c < 0 ? "<" : (c > 0 ? ">" : "="))));
    return 1;
  }
  if (arity == 2 && !strcmp(name, "atom_codes")) {
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
  if (arity == 2 && !strcmp(name, "char_code")) {
    size_t a = heap_deref(f + 1);
    if (heap[a].tag == TAG_ATOM) {
      *ok = unify(
          f + 2, heap_new_int((unsigned char)atom_name(heap[a].as.atom_id)[0]));
      return 1;
    }
    size_t c = heap_deref(f + 2);
    if (heap[c].tag != TAG_INT) {
      *ok = 0;
      return 1;
    }
    char buf[2] = {(char)heap[c].as.ival, '\0'};
    *ok = unify(f + 1, heap_new_atom(atom_intern(buf)));
    return 1;
  }
  if (arity == 2 && !strcmp(name, "number_codes")) {
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
      print_term_err(ball);
      io_write_err("\n");
      return 0;
    }
    catch_frame_t entry = catch_stack[idx];
    heap_release(entry.heap_mark);
    trail_release(entry.trail_mark);
    sp = entry.sp_at_entry;
    size_t rn[nballvars > 0 ? nballvars : 1];
    rename_init(rn, nballvars);
    size_t ball_copy = heap_copy(ball_template, rn, 0);
    if (unify(entry.catcher, ball_copy)) {
      *active_catch_ptr = entry.outer_active_catch;
      *cn_out = build_conj_tail(&entry.recovery, 1, entry.continuation);
      return 1;
    }
    idx = entry.outer_active_catch;
  }
}

void run_query(tterm_t **goals, int32_t ngoals, int32_t nvars,
               const char **varnames, int interactive) {
  size_t rename[nvars > 0 ? nvars : 1];
  rename_init(rename, nvars);

  sp = 0;
  size_t hmark = heap_mark(), tmark = trail_mark(), cut_barrier = 0;
  int any_found = 0;

  size_t qgoals[ngoals > 0 ? ngoals : 1];
  for (int32_t i = 0; i < ngoals; i++)
    qgoals[i] = heap_copy(goals[i], rename, cut_barrier);
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
      if (interactive) {
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
      } else {
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
      const char *fd_name = atom_name(heap[cf].as.func.atom_id);
      if (fd_arity == 2 && heap[cf].as.func.atom_id == atom_comma) {
        size_t inner_first = heap_deref(cf + 1);
        size_t inner_rest = heap_deref(cf + 2);
        size_t new_rest = build_conj_tail(&inner_rest, 1, rest);
        cn = build_conj_tail(&inner_first, 1, new_rest);
        goto A;
      }
      if (fd_arity == 1 && !strcmp(fd_name, "$cut")) {
        sp = (size_t)heap[heap_deref(cf + 1)].as.ival;
        cn = rest;
        goto A;
      }
      if (fd_arity == 3 && !strcmp(fd_name, "catch")) {
        size_t goal = heap_deref(cf + 1);
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
        size_t uncatch_term =
            heap_new_struct(atom_intern("$uncatch"), 1, uncatch_arg);
        size_t after_goal = build_conj_tail(&uncatch_term, 1, rest);
        cn = build_conj_tail(&goal, 1, after_goal);
        goto A;
      }
      if (fd_arity == 1 && !strcmp(fd_name, "$uncatch")) {
        size_t idx = (size_t)heap[heap_deref(cf + 1)].as.ival;
        active_catch = catch_stack[idx].outer_active_catch;
        cn = rest;
        goto A;
      }
      if (fd_arity == 1 && !strcmp(fd_name, "throw")) {
        size_t ball = heap_deref(cf + 1);
        if (do_throw(ball, &cn, &active_catch))
          goto A;
        return;
      }
      if (fd_arity == 1 &&
          (!strcmp(fd_name, "assertz") || !strcmp(fd_name, "assert") ||
           !strcmp(fd_name, "asserta"))) {
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

        if (!strcmp(fd_name, "asserta"))
          db_add_front(templates[0], nbody > 0 ? templates + 1 : NULL, nbody,
                       nvars);
        else
          db_add(templates[0], nbody > 0 ? templates + 1 : NULL, nbody, nvars);
        cn = rest;
        goto A;
      }
      if (fd_arity == 1 && !strcmp(fd_name, "retract")) {
        size_t clause = heap_deref(cf + 1);
        size_t want_head, want_body;
        split_clause_whole(clause, &want_head, &want_body);

        size_t rmark = heap_mark(), rtmark = trail_mark();
        int found = 0;
        for (int32_t ci = 0; ci < db_count; ci++) {
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
      bodies[i] = heap_copy(c->body[i], r2, cut_barrier);
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
    if (interactive)
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

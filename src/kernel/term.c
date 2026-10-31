#include "term.h"
#include "arena.h"
#include "atoms.h"
#include "chars.h"
#include "ctx.h"
#include "fmt.h"
#include "heap.h"
#include "io.h"
#include "mem.h"
#include "solve.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

static int is_transparent_functor(int32_t id) {
  return id == atom_comma || id == atom_semicolon || id == atom_arrow;
}

static tterm_t *tt_new(trilog_t *T, ttag_t tag) {
  tterm_t *t = arena_alloc(T, sizeof(tterm_t));
  t->tag = tag;
  return t;
}

tterm_t *tt_var(trilog_t *T, int32_t slot) {
  tterm_t *t = tt_new(T, T_VAR);
  t->as.slot = slot;
  return t;
}

tterm_t *tt_atom(trilog_t *T, const char *name) {
  tterm_t *t = tt_new(T, T_ATOM);
  t->as.atom_id = atom_intern(T, name);
  return t;
}

tterm_t *tt_int(trilog_t *T, int64_t v) {
  tterm_t *t = tt_new(T, T_INT);
  t->as.ival = v;
  return t;
}

tterm_t *tt_flt(trilog_t *T, double v) {
  tterm_t *t = tt_new(T, T_FLT);
  t->as.fval = v;
  return t;
}

tterm_t *tt_struct(trilog_t *T, const char *name, int32_t arity,
                   tterm_t **args) {
  tterm_t *t = tt_new(T, T_STR);
  t->as.str.atom_id = atom_intern(T, name);
  t->as.str.arity = arity;
  tterm_t **permanent = arena_alloc(T, (size_t)arity * sizeof(tterm_t *));
  if (args)
    memcpy(permanent, args, (size_t)arity * sizeof(tterm_t *));
  else
    memset(permanent, 0, (size_t)arity * sizeof(tterm_t *));
  t->as.str.args = permanent;
  return t;
}

#define NO_HOLE ((size_t)-1)

static void fill_hole(trilog_t *T, size_t hole, size_t r, size_t *root) {
  if (hole == NO_HOLE)
    *root = r;
  else
    T->heap[hole].as.ref = r;
}

// Left to right; one entry per list cell.
static void push_template_args(trilog_t *T, tterm_t *t, size_t f) {
  for (int32_t i = t->as.str.arity - 1; i >= 1; i--) {
    wstack_push(T, (size_t)(uintptr_t)t->as.str.args[i]);
    wstack_push(T, f + 1 + (size_t)i);
  }
}

static int pop_template(trilog_t *T, size_t wbase, tterm_t **t, size_t *hole) {
  if (T->wsp == wbase)
    return 0;
  *hole = T->wstack[--T->wsp];
  *t = (tterm_t *)(uintptr_t)T->wstack[--T->wsp];
  return 1;
}

size_t heap_copy(trilog_t *T, tterm_t *t, size_t *rename, size_t cut_barrier) {
  (void)cut_barrier;
  size_t wbase = T->wsp, root = NO_HOLE, hole = NO_HOLE;
  for (;;) {
    size_t r;
    switch (t->tag) {
    case T_VAR:
      if (rename[t->as.slot] == (size_t)-1)
        rename[t->as.slot] = heap_new_var(T);
      r = rename[t->as.slot];
      break;
    case T_ATOM:
      r = heap_new_atom(T, t->as.atom_id);
      break;
    case T_INT:
      r = heap_new_int(T, t->as.ival);
      break;
    case T_FLT:
      r = heap_new_flt(T, t->as.fval);
      break;
    default: {
      r = heap_new_struct(T, t->as.str.atom_id, t->as.str.arity, NULL);
      size_t f = T->heap[r].as.ptr;
      fill_hole(T, hole, r, &root);
      push_template_args(T, t, f);
      hole = f + 1;
      t = t->as.str.args[0];
      continue;
    }
    }
    fill_hole(T, hole, r, &root);
    if (!pop_template(T, wbase, &t, &hole))
      return root;
  }
}

// Same as unify(heap_copy(t), goal) but builds only the parts of t
// that meet an unbound variable in goal.
int unify_template(trilog_t *T, tterm_t *t, size_t goal, size_t *rename) {
  size_t wbase = T->wsp;
  for (;;) {
    size_t g = heap_deref(T, goal);
    int ok = 1;
    if (t->tag == T_VAR) {
      size_t *v = &rename[t->as.slot];
      if (*v == (size_t)-1)
        *v = g;
      else
        ok = unify(T, *v, g);
    } else if (T->heap[g].tag == TAG_REF) {
      heap_bind(T, g, heap_copy(T, t, rename, 0));
    } else {
      switch (t->tag) {
      case T_ATOM:
        ok = T->heap[g].tag == TAG_ATOM &&
             T->heap[g].as.atom_id == t->as.atom_id;
        break;
      case T_INT:
        ok = T->heap[g].tag == TAG_INT && T->heap[g].as.ival == t->as.ival;
        break;
      case T_FLT:
        ok = T->heap[g].tag == TAG_FLT && T->heap[g].as.fval == t->as.fval;
        break;
      default: {
        if (T->heap[g].tag != TAG_STR) {
          ok = 0;
          break;
        }
        size_t f = T->heap[g].as.ptr;
        int32_t arity = t->as.str.arity;
        if (T->heap[f].as.func.atom_id != t->as.str.atom_id ||
            T->heap[f].as.func.arity != arity) {
          ok = 0;
          break;
        }
        for (int32_t i = arity - 1; i >= 1; i--) {
          wstack_push(T, (size_t)(uintptr_t)t->as.str.args[i - 1]);
          wstack_push(T, f + (size_t)i);
        }
        t = t->as.str.args[arity - 1];
        goal = f + (size_t)arity;
        continue;
      }
      }
    }
    if (!ok) {
      T->wsp = wbase;
      return 0;
    }
    if (T->wsp == wbase)
      return 1;
    goal = T->wstack[--T->wsp];
    t = (tterm_t *)(uintptr_t)T->wstack[--T->wsp];
  }
}

tterm_t **templates_flatten(trilog_t *T, tterm_t **roots, int32_t n) {
  struct chunk *flat = arena_flatten(T, T->arena_pending);
  T->arena_pending = flat;
  tterm_t **moved = arena_moved(flat, roots);
  size_t wbase = T->wsp;
  for (int32_t i = 0; i < n; i++) {
    moved[i] = arena_moved(flat, moved[i]);
    wstack_push(T, (size_t)(uintptr_t)moved[i]);
  }
  while (T->wsp > wbase) {
    tterm_t *t = (tterm_t *)(uintptr_t)T->wstack[--T->wsp];
    if (t->tag != T_STR || t->as.str.arity <= 0)
      continue;
    t->as.str.args = arena_moved(flat, t->as.str.args);
    for (int32_t j = 0; j < t->as.str.arity; j++) {
      t->as.str.args[j] = arena_moved(flat, t->as.str.args[j]);
      wstack_push(T, (size_t)(uintptr_t)t->as.str.args[j]);
    }
  }
  arena_drop_rest(T, flat);
  return moved;
}

static int is_bang(tterm_t *t) {
  return t->tag == T_ATOM && t->as.atom_id == atom_bang;
}

static int is_control(tterm_t *t) {
  return t->tag == T_STR && t->as.str.arity == 2 &&
         is_transparent_functor(t->as.str.atom_id);
}

size_t heap_copy_goal(trilog_t *T, tterm_t *t, size_t *rename,
                      size_t cut_barrier) {
  size_t wbase = T->wsp, root = NO_HOLE, hole = NO_HOLE;
  for (;;) {
    size_t r;
    if (is_bang(t)) {
      size_t barrier_arg[1] = {heap_new_int(T, (int64_t)cut_barrier)};
      r = heap_new_struct(T, atom_cut, 1, barrier_arg);
    } else if (is_control(t)) {
      r = heap_new_struct(T, t->as.str.atom_id, 2, NULL);
      size_t f = T->heap[r].as.ptr;
      fill_hole(T, hole, r, &root);
      push_template_args(T, t, f);
      hole = f + 1;
      t = t->as.str.args[0];
      continue;
    } else {
      r = heap_copy(T, t, rename, cut_barrier);
    }
    fill_hole(T, hole, r, &root);
    if (!pop_template(T, wbase, &t, &hole))
      return root;
  }
}

size_t heap_rebake_cuts(trilog_t *T, size_t r, size_t cut_barrier) {
  size_t wbase = T->wsp, root = NO_HOLE, hole = NO_HOLE;
  for (;;) {
    r = heap_deref(T, r);
    size_t out = r;
    if (T->heap[r].tag == TAG_ATOM && T->heap[r].as.atom_id == atom_bang) {
      size_t barrier_arg[1] = {heap_new_int(T, (int64_t)cut_barrier)};
      out = heap_new_struct(T, atom_cut, 1, barrier_arg);
    } else if (T->heap[r].tag == TAG_STR) {
      size_t f = T->heap[r].as.ptr;
      int32_t id = T->heap[f].as.func.atom_id;
      if (T->heap[f].as.func.arity == 2 && is_transparent_functor(id)) {
        out = heap_new_struct(T, id, 2, NULL);
        size_t nf = T->heap[out].as.ptr;
        fill_hole(T, hole, out, &root);
        wstack_push(T, f + 2);
        wstack_push(T, nf + 2);
        hole = nf + 1;
        r = f + 1;
        continue;
      }
    }
    fill_hole(T, hole, out, &root);
    if (T->wsp == wbase)
      return root;
    hole = T->wstack[--T->wsp];
    r = T->wstack[--T->wsp];
  }
}

static int atom_needs_quote(const char *s) {
  if (!s[0] || !strcmp(s, "."))
    return 1;
  if (!strcmp(s, "[]") || !strcmp(s, "{}") || !strcmp(s, "!") ||
      !strcmp(s, ";"))
    return 0;
  if (ascii_lower((unsigned char)s[0])) {
    for (const char *p = s + 1; *p; p++)
      if (!ascii_alnum((unsigned char)*p) && *p != '_')
        return 1;
    return 0;
  }
  if (s[0] == '/' && s[1] == '*')
    return 1; // it would start a comment
  for (const char *p = s; *p; p++)
    if (!ascii_symbol((unsigned char)*p))
      return 1;
  return 0;
}

static bool word_char(int c) { return ascii_alnum(c) || c == '_'; }

// Two tokens that would read back as one get a space between them, as does a
// prefix operator and a following (, which would otherwise make it a functor.
static void glue(trilog_t *T, emit_fn emit, int first) {
  int last = T->print_last;
  if ((T->print_prefix && first == '(') ||
      (word_char(last) && word_char(first)) ||
      (ascii_symbol(last) && ascii_symbol(first)) ||
      ((last == '\'' || last == '0') && first == '\''))
    emit(T, " ");
  T->print_prefix = false;
}

static void token(trilog_t *T, emit_fn emit, const char *s) {
  if (!s[0])
    return;
  glue(T, emit, (unsigned char)s[0]);
  emit(T, s);
  T->print_last = (unsigned char)s[strlen(s) - 1];
}

// A float needs a fraction to read back: 2.0 and 1.0e-8, not 2 and 1e-8.
void float_text(char *buf, size_t cap, double v) {
  size_t n = fmt(buf, cap, "%g", v);
  if (n + 2 >= cap || strpbrk(buf, ".nN"))
    return;
  char *e = strpbrk(buf, "eE");
  size_t at = e ? (size_t)(e - buf) : n;
  memmove(buf + at + 2, buf + at, n - at + 1);
  buf[at] = '.';
  buf[at + 1] = '0';
}

static void print_quoted_char(trilog_t *T, emit_fn emit, int c, int quote) {
  char buf[8];
  char e = escape_letter(c);
  if (c == quote || c == '\\')
    fmt(buf, sizeof buf, "\\%c", c);
  else if (e)
    fmt(buf, sizeof buf, "\\%c", e);
  else if (c < 0x20 || c == 0x7F) {
    char *p = buf + sizeof buf - 1;
    *p = '\0';
    *--p = '\\';
    do
      *--p = (char)('0' + c % 8);
    while ((c /= 8) > 0);
    *--p = '\\';
    emit(T, p);
    return;
  } else
    fmt(buf, sizeof buf, "%c", c);
  emit(T, buf);
}

static void print_atom(trilog_t *T, const char *name, int quoted,
                       emit_fn emit) {
  if (!quoted || !atom_needs_quote(name)) {
    token(T, emit, name);
    return;
  }
  glue(T, emit, '\'');
  emit(T, "'");
  for (const char *p = name; *p; p++)
    print_quoted_char(T, emit, (unsigned char)*p, '\'');
  emit(T, "'");
  T->print_last = '\'';
}

// In an answer, a proper list of single-character atoms (what "abc" parses
// to) prints as "abc".
#define MAX_PRINT_DEPTH 10000

static int try_print_char_string(trilog_t *T, size_t r, emit_fn emit) {
  size_t cell = r;
  for (int n = 0;; n++) {
    if (n >= MAX_PRINT_DEPTH)
      return 0; // too long, or cyclic: print as a capped list instead
    size_t cf = T->heap[cell].as.ptr;
    size_t head = heap_deref(T, cf + 1);
    if (T->heap[head].tag != TAG_ATOM)
      return 0;
    const char *name = atom_name(T, T->heap[head].as.atom_id);
    if (name[0] == '\0' || name[1] != '\0')
      return 0;
    size_t tail = heap_deref(T, cf + 2);
    if (T->heap[tail].tag == TAG_ATOM && T->heap[tail].as.atom_id == atom_nil)
      break;
    if (T->heap[tail].tag != TAG_STR)
      return 0;
    size_t tf = T->heap[tail].as.ptr;
    if (T->heap[tf].as.func.arity != 2 ||
        T->heap[tf].as.func.atom_id != atom_dot)
      return 0;
    cell = tail;
  }
  glue(T, emit, '"');
  emit(T, "\"");
  for (cell = r;;) {
    size_t cf = T->heap[cell].as.ptr;
    char c = atom_name(T, T->heap[heap_deref(T, cf + 1)].as.atom_id)[0];
    print_quoted_char(T, emit, (unsigned char)c, '"');
    size_t tail = heap_deref(T, cf + 2);
    if (T->heap[tail].tag == TAG_ATOM && T->heap[tail].as.atom_id == atom_nil)
      break;
    cell = tail;
  }
  emit(T, "\"");
  T->print_last = '"';
  return 1;
}

// '$VAR'(N) prints as A..Z, then A1..Z1 and so on
static int print_var_name(trilog_t *T, size_t f, emit_fn emit) {
  if (T->heap[f].as.func.arity != 1 ||
      T->heap[f].as.func.atom_id != atom_dollar_var)
    return 0;
  size_t n = heap_deref(T, f + 1);
  if (T->heap[n].tag != TAG_INT || T->heap[n].as.ival < 0)
    return 0;
  int64_t i = T->heap[n].as.ival;
  char buf[32];
  if (i / 26)
    fmt(buf, sizeof buf, "%c%lld", 'A' + (int)(i % 26), (long long)(i / 26));
  else
    fmt(buf, sizeof buf, "%c", 'A' + (int)(i % 26));
  token(T, emit, buf);
  return 1;
}

enum { P_TERM, P_TEXT, P_LIST, P_EXIT, P_NAME, P_PREFIX };

// A term's priority word: the highest priority it may print at without
// brackets, and whether it is an operand, where an operator atom is bracketed.
#define OPERAND ((size_t)1 << 16)

static void template_mark(trilog_t *T, size_t f);

static void print_push(trilog_t *T, size_t kind, size_t a, size_t prio) {
  wstack_push(T, kind);
  wstack_push(T, a);
  wstack_push(T, prio);
}

static void print_text(trilog_t *T, const char *s) {
  print_push(T, P_TEXT, (size_t)(uintptr_t)s, 0);
}

static int is_cons(trilog_t *T, size_t r) {
  if (T->heap[r].tag != TAG_STR)
    return 0;
  size_t f = T->heap[r].as.ptr;
  return T->heap[f].as.func.arity == 2 &&
         T->heap[f].as.func.atom_id == atom_dot;
}

// Marked again: a cycle.
static void print_enter(trilog_t *T, size_t f) {
  template_mark(T, f);
  print_push(T, P_EXIT, f, 0);
}

static size_t answer_slot(trilog_t *T, size_t ref) {
  size_t mask = T->answer_slots - 1;
  size_t i = (ref * 2654435761u) & mask;
  while (T->answer_index[i] &&
         T->answer_vars[T->answer_index[i] - 1].ref != ref)
    i = (i + 1) & mask;
  return i;
}

void answer_names_reset(trilog_t *T) {
  T->answer_len = 0;
  T->answer_fresh = 0;
  if (T->answer_slots)
    memset(T->answer_index, 0, T->answer_slots * sizeof *T->answer_index);
}

static answer_var_t *answer_find(trilog_t *T, size_t ref) {
  if (!T->answer_slots)
    return NULL;
  uint32_t k = T->answer_index[answer_slot(T, ref)];
  return k ? &T->answer_vars[k - 1] : NULL;
}

static void answer_rehash(trilog_t *T, size_t slots) {
  mem_reserve(T, (void **)&T->answer_index, &T->answer_index_cap,
              slots * sizeof *T->answer_index);
  T->answer_slots = slots;
  memset(T->answer_index, 0, slots * sizeof *T->answer_index);
  for (size_t i = 0; i < T->answer_len; i++)
    T->answer_index[answer_slot(T, T->answer_vars[i].ref)] = (uint32_t)i + 1;
}

static answer_var_t *answer_add(trilog_t *T, size_t ref) {
  if (T->answer_len >= UINT32_MAX - 1)
    mem_fail(T);
  mem_reserve(T, (void **)&T->answer_vars, &T->answer_vars_cap,
              (T->answer_len + 1) * sizeof *T->answer_vars);
  if ((T->answer_len + 1) * 2 > T->answer_slots)
    answer_rehash(T, T->answer_slots ? T->answer_slots * 2 : 64);
  answer_var_t *a = &T->answer_vars[T->answer_len];
  *a = (answer_var_t){.ref = ref, .fresh = -1};
  T->answer_index[answer_slot(T, ref)] = (uint32_t)++T->answer_len;
  return a;
}

void answer_name_claim(trilog_t *T, size_t ref, const char *name) {
  answer_var_t *a = answer_find(T, ref);
  (a ? a : answer_add(T, ref))->name = name;
}

const char *answer_name(trilog_t *T, size_t ref) {
  answer_var_t *a = answer_find(T, ref);
  return a ? a->name : NULL;
}

static void fresh_name(int k, char *buf, size_t cap) {
  if (k / 26)
    fmt(buf, cap, "_%c%d", 'A' + k % 26, k / 26);
  else
    fmt(buf, cap, "_%c", 'A' + k % 26);
}

static bool is_query_name(trilog_t *T, const char *name) {
  for (int32_t v = 0; v < T->nvars; v++)
    if (!strcmp(T->varnames[v], name))
      return true;
  return false;
}

static void print_answer_var(trilog_t *T, size_t r, emit_fn emit) {
  char buf[32];
  answer_var_t *a = answer_find(T, r);
  if (a && a->name) {
    token(T, emit, a->name);
    return;
  }
  if (!a) {
    for (;; T->answer_fresh++) {
      fresh_name(T->answer_fresh, buf, sizeof buf);
      if (!is_query_name(T, buf))
        break;
    }
    a = answer_add(T, r);
    a->fresh = T->answer_fresh++;
  }
  fresh_name(a->fresh, buf, sizeof buf);
  token(T, emit, buf);
}

enum { OP_NONE, OP_INFIX, OP_PREFIX, OP_POSTFIX, OP_ATOM };
enum {
  ASSOC_XFX,
  ASSOC_XFY,
  ASSOC_YFX,
  ASSOC_FX,
  ASSOC_FY,
  ASSOC_XF,
  ASSOC_YF
};

// How r prints with operators: an infix, prefix or postfix operator term, an
// atom that is an operator, or neither
static int op_kind(trilog_t *T, size_t r, int flags, int *pri, int *assoc) {
  if (flags & PRINT_IGNORE_OPS)
    return OP_NONE;
  if (T->heap[r].tag == TAG_ATOM) {
    int32_t id = T->heap[r].as.atom_id;
    return op_lookup_infix(T, id, pri, assoc) ||
                   op_lookup_prefix(T, id, pri, assoc) ||
                   op_lookup_postfix(T, id, pri, assoc)
               ? OP_ATOM
               : OP_NONE;
  }
  if (T->heap[r].tag != TAG_STR || is_cons(T, r))
    return OP_NONE;
  size_t f = T->heap[r].as.ptr;
  int32_t arity = T->heap[f].as.func.arity, id = T->heap[f].as.func.atom_id;
  if (arity == 2 && op_lookup_infix(T, id, pri, assoc))
    return OP_INFIX;
  if (arity == 1 && id != atom_curly && op_lookup_prefix(T, id, pri, assoc))
    return OP_PREFIX;
  if (arity == 1 && id != atom_curly && op_lookup_postfix(T, id, pri, assoc))
    return OP_POSTFIX;
  return OP_NONE;
}

static bool nonnegative_number(trilog_t *T, size_t r) {
  return T->heap[r].tag == TAG_INT   ? T->heap[r].as.ival >= 0
         : T->heap[r].tag == TAG_FLT ? !signbit(T->heap[r].as.fval)
                                     : false;
}

// Whether r, written with operators, begins with a nonnegative number.
static bool starts_with_number(trilog_t *T, size_t r, int flags) {
  int pri, assoc;
  for (;;) {
    r = heap_deref(T, r);
    if ((flags & PRINT_NUMBERVARS) && T->heap[r].tag == TAG_STR &&
        T->heap[T->heap[r].as.ptr].as.func.atom_id == atom_dollar_var)
      return false;
    int kind = op_kind(T, r, flags, &pri, &assoc);
    if (kind != OP_INFIX && kind != OP_POSTFIX)
      return nonnegative_number(T, r);
    r = T->heap[r].as.ptr + 1;
  }
}

static void print_term_ex(trilog_t *T, size_t r, int flags, emit_fn emit) {
  size_t wbase = T->wsp, mbase = T->template_marks_len;
  T->print_last = 0;
  T->print_prefix = false;
  print_push(T, P_TERM, r, flags & PRINT_ANSWER ? 699 : 1200);
  char buf[64];
  while (T->wsp > wbase) {
    size_t prio = T->wstack[--T->wsp];
    size_t a = T->wstack[--T->wsp];
    size_t kind = T->wstack[--T->wsp];
    if (kind == P_TEXT) {
      token(T, emit, (const char *)(uintptr_t)a);
      continue;
    }
    if (kind == P_NAME || kind == P_PREFIX) {
      print_atom(T, atom_name(T, (int32_t)a), flags & PRINT_QUOTED, emit);
      T->print_prefix = kind == P_PREFIX;
      continue;
    }
    if (kind == P_EXIT) {
      size_t f = T->template_marks[--T->template_marks_len];
      T->heap[f].as.func.arity = -1 - T->heap[f].as.func.arity;
      continue;
    }
    if (kind == P_LIST) {
      size_t tail = heap_deref(T, T->heap[a].as.ptr + 2);
      if (T->heap[tail].tag == TAG_ATOM &&
          T->heap[tail].as.atom_id == atom_nil) {
        token(T, emit, "]");
      } else if (is_cons(T, tail)) {
        token(T, emit, ",");
        print_enter(T, T->heap[tail].as.ptr);
        print_push(T, P_LIST, tail, 0);
        print_push(T, P_TERM, T->heap[tail].as.ptr + 1, 999);
      } else {
        token(T, emit, "|");
        print_text(T, "]");
        print_push(T, P_TERM, tail, 999);
      }
      continue;
    }
    r = heap_deref(T, a);
    size_t max = prio & ~OPERAND;
    int pri, assoc;
    switch (T->heap[r].tag) {
    case TAG_REF:
      if (T->answer_naming)
        print_answer_var(T, r, emit);
      else {
        fmt(buf, sizeof buf, "_G%zu", r);
        token(T, emit, buf);
      }
      break;
    case TAG_ATOM: {
      bool bracket =
          (prio & OPERAND) && op_kind(T, r, flags, &pri, &assoc) == OP_ATOM;
      if (bracket)
        token(T, emit, "(");
      print_atom(T, atom_name(T, T->heap[r].as.atom_id), flags & PRINT_QUOTED,
                 emit);
      if (bracket)
        token(T, emit, ")");
      break;
    }
    case TAG_INT:
      fmt(buf, sizeof buf, "%lld", (long long)T->heap[r].as.ival);
      token(T, emit, buf);
      break;
    case TAG_FLT:
      float_text(buf, sizeof buf, T->heap[r].as.fval);
      token(T, emit, buf);
      break;
    case TAG_STR: {
      size_t f = T->heap[r].as.ptr;
      int32_t arity = T->heap[f].as.func.arity;
      int32_t id = T->heap[f].as.func.atom_id;
      if (arity < 0) {
        token(T, emit, "...");
        break;
      }
      if (is_cons(T, r) && !(flags & PRINT_IGNORE_OPS)) {
        if ((flags & PRINT_ANSWER) && try_print_char_string(T, r, emit))
          break;
        token(T, emit, "[");
        print_enter(T, f);
        print_push(T, P_LIST, r, 0);
        print_push(T, P_TERM, f + 1, 999);
        break;
      }
      if ((flags & PRINT_NUMBERVARS) && print_var_name(T, f, emit))
        break;
      if (arity == 1 && id == atom_curly && !(flags & PRINT_IGNORE_OPS)) {
        token(T, emit, "{");
        print_enter(T, f);
        print_text(T, "}");
        print_push(T, P_TERM, f + 1, 1200);
        break;
      }
      int kind = op_kind(T, r, flags, &pri, &assoc);
      if (kind == OP_INFIX) {
        bool open = (size_t)pri > max;
        size_t left = heap_deref(T, f + 1);
        int lpri, lassoc;
        // The left operand's own operand would take in this operator, as
        // fy 1 yfx 2 reads fy(1 yfx 2), so that operand is bracketed.
        bool bracket = op_kind(T, left, flags, &lpri, &lassoc) == OP_PREFIX &&
                       pri <= (lassoc == ASSOC_FY ? lpri : lpri - 1);
        print_enter(T, f);
        if (open)
          print_text(T, ")");
        print_push(T, P_TERM, f + 2,
                   (size_t)(assoc == ASSOC_XFY ? pri : pri - 1) | OPERAND);
        if (id == atom_comma)
          print_text(T, ",");
        else
          print_push(T, P_NAME, (size_t)id, 0);
        if (bracket) {
          print_text(T, ")");
          print_push(T, P_TERM, f + 1, 1200);
          print_text(T, "(");
        } else {
          print_push(T, P_TERM, f + 1,
                     (size_t)(assoc == ASSOC_YFX ? pri : pri - 1) | OPERAND);
        }
        if (open)
          print_text(T, "(");
        break;
      }
      if (kind == OP_PREFIX) {
        size_t arg = heap_deref(T, f + 1);
        int apri, aassoc;
        int akind = op_kind(T, arg, flags, &apri, &aassoc);
        int amax = assoc == ASSOC_FY ? pri : pri - 1;
        bool bracket =
            (id == atom_minus &&
             (starts_with_number(T, arg, flags) ||
              ((akind == OP_INFIX || akind == OP_POSTFIX) && apri >= pri))) ||
            akind == OP_ATOM || (akind != OP_NONE && apri > amax);
        bool open = (size_t)pri > max;
        print_enter(T, f);
        if (open)
          print_text(T, ")");
        if (bracket) {
          print_text(T, ")");
          print_push(T, P_TERM, f + 1, 1200);
          print_text(T, "(");
        } else {
          print_push(T, P_TERM, f + 1, (size_t)amax | OPERAND);
        }
        print_push(T, P_PREFIX, (size_t)id, 0);
        if (open)
          print_text(T, "(");
        break;
      }
      if (kind == OP_POSTFIX) {
        size_t arg = heap_deref(T, f + 1);
        int apri, aassoc;
        int akind = op_kind(T, arg, flags, &apri, &aassoc);
        // The operator would bind to the operand's own right side, as
        // 1 xfy 2 yf reads xfy(1, yf(2)), so that operand is bracketed.
        int right = aassoc == ASSOC_XFY || aassoc == ASSOC_FY ? apri : apri - 1;
        bool bracket =
            (akind == OP_INFIX || akind == OP_PREFIX) && pri <= right;
        bool open = (size_t)pri > max;
        print_enter(T, f);
        if (open)
          print_text(T, ")");
        print_push(T, P_NAME, (size_t)id, 0);
        if (bracket) {
          print_text(T, ")");
          print_push(T, P_TERM, f + 1, 1200);
          print_text(T, "(");
        } else {
          print_push(T, P_TERM, f + 1,
                     (size_t)(assoc == ASSOC_YF ? pri : pri - 1) | OPERAND);
        }
        if (open)
          print_text(T, "(");
        break;
      }
      print_atom(T, atom_name(T, id), flags & PRINT_QUOTED, emit);
      if (arity > 0) {
        token(T, emit, "(");
        print_enter(T, f);
        print_text(T, ")");
        for (int32_t i = arity - 1; i >= 1; i--) {
          print_push(T, P_TERM, f + 1 + (size_t)i, 999);
          print_text(T, ",");
        }
        print_push(T, P_TERM, f + 1, 999);
      }
      break;
    }
    case TAG_FUNCTOR:
      break;
    }
  }
  while (T->template_marks_len > mbase) {
    size_t f = T->template_marks[--T->template_marks_len];
    T->heap[f].as.func.arity = -1 - T->heap[f].as.func.arity;
  }
}

void print_term(trilog_t *T, size_t r) { print_term_ex(T, r, 0, io_write_str); }
void print_term_quoted(trilog_t *T, size_t r) {
  print_term_ex(T, r, PRINT_QUOTED, io_write_str);
}
void print_term_via(trilog_t *T, size_t r, int flags, emit_fn emit) {
  print_term_ex(T, r, flags, emit);
}

static void template_mark(trilog_t *T, size_t f) {
  if (T->template_marks_len == T->template_marks_cap) {
    size_t cap = T->template_marks_cap ? T->template_marks_cap * 2 : 64;
    T->template_marks = mem_grow_n(T, T->template_marks, cap, sizeof(size_t));
    T->template_marks_cap = cap;
  }
  T->heap[f].as.func.arity = -1 - T->heap[f].as.func.arity;
  T->template_marks[T->template_marks_len++] = f;
}

#define TEMPLATE_EXIT ((size_t)-1)

// Path marks only: shared is not cyclic.
static tterm_t *heap_to_template_rec(trilog_t *T, size_t r, int32_t *nseen) {
  size_t base = T->template_marks_len, wbase = T->wsp;
  tterm_t *first = NULL, **hole = &first;
  for (;;) {
    r = heap_deref(T, r);
    tterm_t *t = NULL;
    switch (T->heap[r].tag) {
    case TAG_REF: {
      size_t m = heap_alloc(T, 1);
      T->heap[m].tag = TAG_FUNCTOR;
      T->heap[m].as.func.atom_id = -1;
      T->heap[m].as.func.arity = *nseen;
      heap_bind(T, r, m);
      t = tt_var(T, (*nseen)++);
      break;
    }
    case TAG_FUNCTOR:
      t = tt_var(T, T->heap[r].as.func.arity);
      break;
    case TAG_ATOM:
      t = tt_atom(T, atom_name(T, T->heap[r].as.atom_id));
      break;
    case TAG_INT:
      t = tt_int(T, T->heap[r].as.ival);
      break;
    case TAG_FLT:
      t = tt_flt(T, T->heap[r].as.fval);
      break;
    case TAG_STR: {
      size_t f = T->heap[r].as.ptr;
      int32_t arity = T->heap[f].as.func.arity;
      if (arity < 0 || T->template_cyclic) {
        T->template_cyclic = 1;
        t = tt_atom(T, "[]");
        break;
      }
      t = tt_struct(T, atom_name(T, T->heap[f].as.func.atom_id), arity, NULL);
      *hole = t;
      template_mark(T, f);
      wstack_push(T, TEMPLATE_EXIT);
      wstack_push(T, f);
      for (int32_t i = arity - 1; i >= 1; i--) {
        wstack_push(T, f + 1 + (size_t)i);
        wstack_push(T, (size_t)(uintptr_t)&t->as.str.args[i]);
      }
      hole = &t->as.str.args[0];
      r = f + 1;
      continue;
    }
    }
    *hole = t;
    for (;;) {
      if (T->wsp == wbase)
        goto done;
      size_t b = T->wstack[--T->wsp];
      size_t a = T->wstack[--T->wsp];
      if (a != TEMPLATE_EXIT) {
        r = a;
        hole = (tterm_t **)(uintptr_t)b;
        break;
      }
      size_t f = T->template_marks[--T->template_marks_len];
      T->heap[f].as.func.arity = -1 - T->heap[f].as.func.arity;
    }
  }
done:
  while (T->template_marks_len > base) {
    size_t f = T->template_marks[--T->template_marks_len];
    T->heap[f].as.func.arity = -1 - T->heap[f].as.func.arity;
  }
  T->wsp = wbase;
  return first;
}

// 0 if any of terms is cyclic.
int heap_terms_to_templates(trilog_t *T, size_t *terms, int32_t n,
                            tterm_t **out, int32_t *nvars_out) {
  size_t hmark = heap_mark(T), tmark = trail_mark(T);
  int32_t nseen = 0;
  T->template_cyclic = 0;
  for (int32_t i = 0; i < n; i++)
    out[i] = heap_to_template_rec(T, terms[i], &nseen);
  trail_release(T, tmark);
  heap_release(T, hmark);
  *nvars_out =
      nseen > 0 ? nseen : 1; // heap_copy's rename table is never zero-sized
  return !T->template_cyclic;
}

// NULL if r is cyclic.
tterm_t *heap_to_template(trilog_t *T, size_t r, int32_t *nvars_out) {
  tterm_t *t;
  return heap_terms_to_templates(T, &r, 1, &t, nvars_out) ? t : NULL;
}

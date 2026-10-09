#include "term.h"
#include "arena.h"
#include "atoms.h"
#include "chars.h"
#include "ctx.h"
#include "fmt.h"
#include "heap.h"
#include "io.h"
#include "mem.h"
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
  if (!s[0])
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
  static const char symbol_chars[] = "+-*/\\^<>=~:.?@#&$";
  int all_symbol = 1;
  for (const char *p = s; *p; p++)
    if (!strchr(symbol_chars, *p)) {
      all_symbol = 0;
      break;
    }
  return !all_symbol;
}

static void print_atom(trilog_t *T, const char *name, int quoted,
                       emit_fn emit) {
  if (!quoted || !atom_needs_quote(name)) {
    emit(T, name);
    return;
  }
  emit(T, "'");
  for (const char *p = name; *p; p++) {
    switch (*p) {
    case '\'':
      emit(T, "\\'");
      break;
    case '\\':
      emit(T, "\\\\");
      break;
    case '\n':
      emit(T, "\\n");
      break;
    case '\t':
      emit(T, "\\t");
      break;
    default: {
      char c[2] = {*p, '\0'};
      emit(T, c);
    }
    }
  }
  emit(T, "'");
}

// A proper list of single-character atoms (what "abc" parses to) prints as
// "abc" for write/1 and writeq/1 alike.
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
  emit(T, "\"");
  for (cell = r;;) {
    size_t cf = T->heap[cell].as.ptr;
    char c = atom_name(T, T->heap[heap_deref(T, cf + 1)].as.atom_id)[0];
    switch (c) {
    case '"':
      emit(T, "\\\"");
      break;
    case '\\':
      emit(T, "\\\\");
      break;
    case '\n':
      emit(T, "\\n");
      break;
    case '\t':
      emit(T, "\\t");
      break;
    default: {
      char s[2] = {c, '\0'};
      emit(T, s);
    }
    }
    size_t tail = heap_deref(T, cf + 2);
    if (T->heap[tail].tag == TAG_ATOM && T->heap[tail].as.atom_id == atom_nil)
      break;
    cell = tail;
  }
  emit(T, "\"");
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
  emit(T, buf);
  return 1;
}

enum { P_TERM, P_TEXT, P_LIST, P_EXIT };

static void template_mark(trilog_t *T, size_t f);

static void print_push(trilog_t *T, size_t kind, size_t a) {
  wstack_push(T, kind);
  wstack_push(T, a);
}

static void print_text(trilog_t *T, const char *s) {
  print_push(T, P_TEXT, (size_t)(uintptr_t)s);
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
  print_push(T, P_EXIT, f);
}

static void print_term_ex(trilog_t *T, size_t r, int flags, emit_fn emit) {
  size_t wbase = T->wsp, mbase = T->template_marks_len;
  print_push(T, P_TERM, r);
  char buf[64];
  while (T->wsp > wbase) {
    size_t a = T->wstack[--T->wsp];
    size_t kind = T->wstack[--T->wsp];
    if (kind == P_TEXT) {
      emit(T, (const char *)(uintptr_t)a);
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
        emit(T, "]");
      } else if (is_cons(T, tail)) {
        emit(T, ", ");
        print_enter(T, T->heap[tail].as.ptr);
        print_push(T, P_LIST, tail);
        print_push(T, P_TERM, T->heap[tail].as.ptr + 1);
      } else {
        emit(T, "|");
        print_text(T, "]");
        print_push(T, P_TERM, tail);
      }
      continue;
    }
    r = heap_deref(T, a);
    switch (T->heap[r].tag) {
    case TAG_REF:
      fmt(buf, sizeof buf, "_G%zu", r);
      emit(T, buf);
      break;
    case TAG_ATOM:
      print_atom(T, atom_name(T, T->heap[r].as.atom_id), flags & PRINT_QUOTED,
                 emit);
      break;
    case TAG_INT:
      fmt(buf, sizeof buf, "%lld", (long long)T->heap[r].as.ival);
      emit(T, buf);
      break;
    case TAG_FLT:
      fmt(buf, sizeof buf, "%g", T->heap[r].as.fval);
      if (!strpbrk(buf, ".eEnN")) // 2.0, not 2
        strncat(buf, ".0", sizeof buf - strlen(buf) - 1);
      emit(T, buf);
      break;
    case TAG_STR: {
      size_t f = T->heap[r].as.ptr;
      int32_t arity = T->heap[f].as.func.arity;
      if (arity < 0) {
        emit(T, "...");
        break;
      }
      if (is_cons(T, r)) {
        if (!(flags & PRINT_IGNORE_OPS) && try_print_char_string(T, r, emit))
          break;
        emit(T, "[");
        print_enter(T, f);
        print_push(T, P_LIST, r);
        print_push(T, P_TERM, f + 1);
        break;
      }
      if ((flags & PRINT_NUMBERVARS) && print_var_name(T, f, emit))
        break;
      if (arity == 1 && T->heap[f].as.func.atom_id == atom_curly) {
        emit(T, "{");
        print_enter(T, f);
        print_text(T, "}");
        print_push(T, P_TERM, f + 1);
        break;
      }
      print_atom(T, atom_name(T, T->heap[f].as.func.atom_id),
                 flags & PRINT_QUOTED, emit);
      if (arity > 0) {
        emit(T, "(");
        print_enter(T, f);
        print_text(T, ")");
        for (int32_t i = arity - 1; i >= 1; i--) {
          print_push(T, P_TERM, f + 1 + (size_t)i);
          print_text(T, ", ");
        }
        print_push(T, P_TERM, f + 1);
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

#include "term.h"
#include "arena.h"
#include "atoms.h"
#include "ctx.h"
#include "heap.h"
#include "io.h"
#include "mem.h"
#include <ctype.h>
#include <stdio.h>
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
  memcpy(permanent, args, (size_t)arity * sizeof(tterm_t *));
  t->as.str.args = permanent;
  return t;
}

// copies every argument but the last recursively and loops on that one
size_t heap_copy(trilog_t *T, tterm_t *t, size_t *rename, size_t cut_barrier) {
  size_t first = (size_t)-1, hole = (size_t)-1;
  for (;;) {
    size_t r;
    tterm_t *last = NULL;
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
      int32_t arity = t->as.str.arity;
      size_t args[arity];
      for (int32_t i = 0; i < arity - 1; i++)
        args[i] = heap_copy(T, t->as.str.args[i], rename, cut_barrier);
      args[arity - 1] = 0; // patched on the next iteration
      r = heap_new_struct(T, t->as.str.atom_id, arity, args);
      last = t->as.str.args[arity - 1];
      break;
    }
    }
    if (hole == (size_t)-1)
      first = r;
    else
      T->heap[hole].as.ref = r;
    if (!last)
      return first;
    hole = T->heap[r].as.ptr + (size_t)t->as.str.arity;
    t = last;
  }
}

size_t heap_copy_goal(trilog_t *T, tterm_t *t, size_t *rename,
                      size_t cut_barrier) {
  if (t->tag == T_ATOM && t->as.atom_id == atom_bang) {
    size_t barrier_arg[1] = {heap_new_int(T, (int64_t)cut_barrier)};
    return heap_new_struct(T, atom_cut, 1, barrier_arg);
  }
  if (t->tag == T_STR && t->as.str.arity == 2 &&
      is_transparent_functor(t->as.str.atom_id)) {
    size_t args[2] = {
        heap_copy_goal(T, t->as.str.args[0], rename, cut_barrier),
        heap_copy_goal(T, t->as.str.args[1], rename, cut_barrier)};
    return heap_new_struct(T, t->as.str.atom_id, 2, args);
  }
  return heap_copy(T, t, rename, cut_barrier);
}

size_t heap_rebake_cuts(trilog_t *T, size_t r, size_t cut_barrier) {
  r = heap_deref(T, r);
  if (T->heap[r].tag == TAG_ATOM && T->heap[r].as.atom_id == atom_bang) {
    size_t barrier_arg[1] = {heap_new_int(T, (int64_t)cut_barrier)};
    return heap_new_struct(T, atom_cut, 1, barrier_arg);
  }
  if (T->heap[r].tag == TAG_STR) {
    size_t f = T->heap[r].as.ptr;
    int32_t arity = T->heap[f].as.func.arity;
    int32_t id = T->heap[f].as.func.atom_id;
    if (arity == 2 && is_transparent_functor(id)) {
      size_t args[2] = {heap_rebake_cuts(T, f + 1, cut_barrier),
                        heap_rebake_cuts(T, f + 2, cut_barrier)};
      return heap_new_struct(T, id, 2, args);
    }
  }
  return r;
}

static int atom_needs_quote(const char *s) {
  if (!s[0])
    return 1;
  if (!strcmp(s, "[]") || !strcmp(s, "{}") || !strcmp(s, "!") ||
      !strcmp(s, ";"))
    return 0;
  if (islower((unsigned char)s[0])) {
    for (const char *p = s + 1; *p; p++)
      if (!isalnum((unsigned char)*p) && *p != '_')
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
    snprintf(buf, sizeof buf, "%c%lld", 'A' + (int)(i % 26),
             (long long)(i / 26));
  else
    snprintf(buf, sizeof buf, "%c", 'A' + (int)(i % 26));
  emit(T, buf);
  return 1;
}

// Cyclic terms (X = [X|_], no occurs-check by default) used to blow the
// C stack - a long acyclic list is safe since the list branch below
// walks its spine iteratively.
static void print_term_ex(trilog_t *T, size_t r, int flags, emit_fn emit) {
  if (T->print_depth >= MAX_PRINT_DEPTH) {
    emit(T, "...");
    return;
  }
  T->print_depth++;
  r = heap_deref(T, r);
  char buf[64];
  switch (T->heap[r].tag) {
  case TAG_REF:
    snprintf(buf, sizeof buf, "_G%zu", r);
    emit(T, buf);
    break;
  case TAG_ATOM:
    print_atom(T, atom_name(T, T->heap[r].as.atom_id), flags & PRINT_QUOTED,
               emit);
    break;
  case TAG_INT:
    snprintf(buf, sizeof buf, "%lld", (long long)T->heap[r].as.ival);
    emit(T, buf);
    break;
  case TAG_FLT:
    snprintf(buf, sizeof buf, "%g", T->heap[r].as.fval);
    if (!strpbrk(buf, ".eEnN")) // force a decimal point: 2.0, not 2
      strncat(buf, ".0", sizeof buf - strlen(buf) - 1);
    emit(T, buf);
    break;
  case TAG_STR: {
    size_t f = T->heap[r].as.ptr;
    int32_t arity = T->heap[f].as.func.arity;
    int32_t f_id = T->heap[f].as.func.atom_id;
    const char *name = atom_name(T, f_id);
    if (arity == 2 && f_id == atom_dot) {
      if (try_print_char_string(T, r, emit))
        break;
      emit(T, "[");
      size_t cell = r;
      for (int first = 1, n = 0;; first = 0, n++) {
        size_t cf = T->heap[cell].as.ptr;
        if (!first)
          emit(T, ", ");
        print_term_ex(T, cf + 1, flags, emit); // head
        size_t tail = heap_deref(T, cf + 2);
        if (T->heap[tail].tag == TAG_ATOM &&
            T->heap[tail].as.atom_id == atom_nil)
          break;
        if (T->heap[tail].tag == TAG_STR) {
          size_t tf = T->heap[tail].as.ptr;
          if (T->heap[tf].as.func.arity == 2 &&
              T->heap[tf].as.func.atom_id == atom_dot) {
            if (n + 1 >= MAX_PRINT_DEPTH) {
              emit(T, "|...");
              break;
            }
            cell = tail;
            continue;
          }
        }
        emit(T, "|");
        print_term_ex(T, tail, flags, emit);
        break;
      }
      emit(T, "]");
      break;
    }
    if ((flags & PRINT_NUMBERVARS) && print_var_name(T, f, emit))
      break;
    print_atom(T, name, flags & PRINT_QUOTED, emit);
    if (arity > 0) {
      emit(T, "(");
      for (int32_t i = 0; i < arity; i++) {
        if (i)
          emit(T, ", ");
        print_term_ex(T, f + 1 + i, flags, emit);
      }
      emit(T, ")");
    }
    break;
  }
  case TAG_FUNCTOR:
    break; // never a term in its own right
  }
  T->print_depth--;
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

static tterm_t *heap_to_template_rec(trilog_t *T, size_t r, int32_t *nseen) {
  size_t base = T->template_marks_len;
  tterm_t *first = NULL, **hole = &first;
  for (;;) {
    r = heap_deref(T, r);
    tterm_t *t = NULL;
    size_t next = (size_t)-1;
    int32_t arity = 0;
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
      arity = T->heap[f].as.func.arity;
      if (arity < 0 || T->template_cyclic) {
        T->template_cyclic = 1;
        t = tt_atom(T, "[]");
        break;
      }
      tterm_t *args[arity];
      template_mark(T, f);
      for (int32_t i = 0; i < arity - 1; i++)
        args[i] = heap_to_template_rec(T, f + 1 + (size_t)i, nseen);
      args[arity - 1] = NULL; // filled in on the next iteration
      t = tt_struct(T, atom_name(T, T->heap[f].as.func.atom_id), arity, args);
      next = f + (size_t)arity;
      break;
    }
    }
    *hole = t;
    if (next == (size_t)-1)
      break;
    hole = &t->as.str.args[arity - 1];
    r = next;
  }
  while (T->template_marks_len > base) {
    size_t f = T->template_marks[--T->template_marks_len];
    T->heap[f].as.func.arity = -1 - T->heap[f].as.func.arity;
  }
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

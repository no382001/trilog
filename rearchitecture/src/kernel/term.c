#include "term.h"
#include "arena.h"
#include "heap.h"
#include "io.h"
#include <ctype.h>
#include <stdio.h>
#include <string.h>

// Interned once here, not per call site - atom_intern is a linear scan.
static int32_t atom_bang, atom_cut, atom_dot, atom_nil, atom_comma,
    atom_semicolon, atom_arrow;

void term_init(void) {
  atom_bang = atom_intern("!");
  atom_cut = atom_intern("$$cut");
  atom_dot = atom_intern(".");
  atom_nil = atom_intern("[]");
  atom_comma = atom_intern(",");
  atom_semicolon = atom_intern(";");
  atom_arrow = atom_intern("->");
}

static int is_transparent_functor(int32_t id) {
  return id == atom_comma || id == atom_semicolon || id == atom_arrow;
}

static tterm_t *tt_new(ttag_t tag) {
  tterm_t *t = arena_alloc(sizeof(tterm_t));
  t->tag = tag;
  return t;
}

tterm_t *tt_var(int32_t slot) {
  tterm_t *t = tt_new(T_VAR);
  t->as.slot = slot;
  return t;
}

tterm_t *tt_atom(const char *name) {
  tterm_t *t = tt_new(T_ATOM);
  t->as.atom_id = atom_intern(name);
  return t;
}

tterm_t *tt_int(int64_t v) {
  tterm_t *t = tt_new(T_INT);
  t->as.ival = v;
  return t;
}

tterm_t *tt_flt(double v) {
  tterm_t *t = tt_new(T_FLT);
  t->as.fval = v;
  return t;
}

tterm_t *tt_struct(const char *name, int32_t arity, tterm_t **args) {
  tterm_t *t = tt_new(T_STR);
  t->as.str.atom_id = atom_intern(name);
  t->as.str.arity = arity;
  tterm_t **permanent = arena_alloc((size_t)arity * sizeof(tterm_t *));
  memcpy(permanent, args, (size_t)arity * sizeof(tterm_t *));
  t->as.str.args = permanent;
  return t;
}

size_t heap_copy(tterm_t *t, size_t *rename, size_t cut_barrier) {
  switch (t->tag) {
  case T_VAR:
    if (rename[t->as.slot] == (size_t)-1)
      rename[t->as.slot] = heap_new_var();
    return rename[t->as.slot];
  case T_ATOM:
    return heap_new_atom(t->as.atom_id);
  case T_INT:
    return heap_new_int(t->as.ival);
  case T_FLT:
    return heap_new_flt(t->as.fval);
  case T_STR: {
    int32_t arity = t->as.str.arity;
    size_t args[arity];
    for (int32_t i = 0; i < arity; i++)
      args[i] = heap_copy(t->as.str.args[i], rename, cut_barrier);
    return heap_new_struct(t->as.str.atom_id, arity, args);
  }
  }
  return (size_t)-1; // unreachable
}

size_t heap_copy_goal(tterm_t *t, size_t *rename, size_t cut_barrier) {
  if (t->tag == T_ATOM && t->as.atom_id == atom_bang) {
    size_t barrier_arg[1] = {heap_new_int((int64_t)cut_barrier)};
    return heap_new_struct(atom_cut, 1, barrier_arg);
  }
  if (t->tag == T_STR && t->as.str.arity == 2 &&
      is_transparent_functor(t->as.str.atom_id)) {
    size_t args[2] = {heap_copy_goal(t->as.str.args[0], rename, cut_barrier),
                      heap_copy_goal(t->as.str.args[1], rename, cut_barrier)};
    return heap_new_struct(t->as.str.atom_id, 2, args);
  }
  return heap_copy(t, rename, cut_barrier);
}

size_t heap_rebake_cuts(size_t r, size_t cut_barrier) {
  r = heap_deref(r);
  if (heap[r].tag == TAG_ATOM && heap[r].as.atom_id == atom_bang) {
    size_t barrier_arg[1] = {heap_new_int((int64_t)cut_barrier)};
    return heap_new_struct(atom_cut, 1, barrier_arg);
  }
  if (heap[r].tag == TAG_STR) {
    size_t f = heap[r].as.ptr;
    int32_t arity = heap[f].as.func.arity;
    int32_t id = heap[f].as.func.atom_id;
    if (arity == 2 && is_transparent_functor(id)) {
      size_t args[2] = {heap_rebake_cuts(f + 1, cut_barrier),
                        heap_rebake_cuts(f + 2, cut_barrier)};
      return heap_new_struct(id, 2, args);
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
  static const char *symbol_chars = "+-*/\\^<>=~:.?@#&$";
  int all_symbol = 1;
  for (const char *p = s; *p; p++)
    if (!strchr(symbol_chars, *p)) {
      all_symbol = 0;
      break;
    }
  return !all_symbol;
}

static void print_atom(const char *name, int quoted, emit_fn emit) {
  if (!quoted || !atom_needs_quote(name)) {
    emit(name);
    return;
  }
  emit("'");
  for (const char *p = name; *p; p++) {
    switch (*p) {
    case '\'':
      emit("\\'");
      break;
    case '\\':
      emit("\\\\");
      break;
    case '\n':
      emit("\\n");
      break;
    case '\t':
      emit("\\t");
      break;
    default: {
      char c[2] = {*p, '\0'};
      emit(c);
    }
    }
  }
  emit("'");
}

// A proper list of single-character atoms (what "abc" parses to) prints as
// "abc" for write/1 and writeq/1 alike.
#define MAX_PRINT_DEPTH 10000

static int try_print_char_string(size_t r, emit_fn emit) {
  size_t cell = r;
  for (int n = 0;; n++) {
    if (n >= MAX_PRINT_DEPTH)
      return 0; // too long, or cyclic: print as a capped list instead
    size_t cf = heap[cell].as.ptr;
    size_t head = heap_deref(cf + 1);
    if (heap[head].tag != TAG_ATOM)
      return 0;
    const char *name = atom_name(heap[head].as.atom_id);
    if (name[0] == '\0' || name[1] != '\0')
      return 0;
    size_t tail = heap_deref(cf + 2);
    if (heap[tail].tag == TAG_ATOM && heap[tail].as.atom_id == atom_nil)
      break;
    if (heap[tail].tag != TAG_STR)
      return 0;
    size_t tf = heap[tail].as.ptr;
    if (heap[tf].as.func.arity != 2 || heap[tf].as.func.atom_id != atom_dot)
      return 0;
    cell = tail;
  }
  emit("\"");
  for (cell = r;;) {
    size_t cf = heap[cell].as.ptr;
    char c = atom_name(heap[heap_deref(cf + 1)].as.atom_id)[0];
    switch (c) {
    case '"':
      emit("\\\"");
      break;
    case '\\':
      emit("\\\\");
      break;
    case '\n':
      emit("\\n");
      break;
    case '\t':
      emit("\\t");
      break;
    default: {
      char s[2] = {c, '\0'};
      emit(s);
    }
    }
    size_t tail = heap_deref(cf + 2);
    if (heap[tail].tag == TAG_ATOM && heap[tail].as.atom_id == atom_nil)
      break;
    cell = tail;
  }
  emit("\"");
  return 1;
}

// Cyclic terms (X = [X|_], no occurs-check by default) used to blow the
// C stack - a long acyclic list is safe since the list branch below
// walks its spine iteratively.
static int print_depth = 0;

static void print_term_ex(size_t r, int quoted, emit_fn emit) {
  if (print_depth >= MAX_PRINT_DEPTH) {
    emit("...");
    return;
  }
  print_depth++;
  r = heap_deref(r);
  char buf[64];
  switch (heap[r].tag) {
  case TAG_REF:
    snprintf(buf, sizeof buf, "_G%zu", r);
    emit(buf);
    break;
  case TAG_ATOM:
    print_atom(atom_name(heap[r].as.atom_id), quoted, emit);
    break;
  case TAG_INT:
    snprintf(buf, sizeof buf, "%ld", heap[r].as.ival);
    emit(buf);
    break;
  case TAG_FLT:
    snprintf(buf, sizeof buf, "%g", heap[r].as.fval);
    if (!strpbrk(buf, ".eEnN")) // force a decimal point: 2.0, not 2
      strncat(buf, ".0", sizeof buf - strlen(buf) - 1);
    emit(buf);
    break;
  case TAG_STR: {
    size_t f = heap[r].as.ptr;
    int32_t arity = heap[f].as.func.arity;
    int32_t f_id = heap[f].as.func.atom_id;
    const char *name = atom_name(f_id);
    if (arity == 2 && f_id == atom_dot) {
      if (try_print_char_string(r, emit))
        break;
      emit("[");
      size_t cell = r;
      for (int first = 1, n = 0;; first = 0, n++) {
        size_t cf = heap[cell].as.ptr;
        if (!first)
          emit(", ");
        print_term_ex(cf + 1, quoted, emit); // head
        size_t tail = heap_deref(cf + 2);
        if (heap[tail].tag == TAG_ATOM && heap[tail].as.atom_id == atom_nil)
          break;
        if (heap[tail].tag == TAG_STR) {
          size_t tf = heap[tail].as.ptr;
          if (heap[tf].as.func.arity == 2 &&
              heap[tf].as.func.atom_id == atom_dot) {
            if (n + 1 >= MAX_PRINT_DEPTH) {
              emit("|...");
              break;
            }
            cell = tail;
            continue;
          }
        }
        emit("|");
        print_term_ex(tail, quoted, emit);
        break;
      }
      emit("]");
      break;
    }
    print_atom(name, quoted, emit);
    if (arity > 0) {
      emit("(");
      for (int32_t i = 0; i < arity; i++) {
        if (i)
          emit(", ");
        print_term_ex(f + 1 + i, quoted, emit);
      }
      emit(")");
    }
    break;
  }
  case TAG_FUNCTOR:
    break; // never a term in its own right
  }
  print_depth--;
}

void print_term(size_t r) { print_term_ex(r, 0, io_write_str); }
void print_term_quoted(size_t r) { print_term_ex(r, 1, io_write_str); }
void print_term_via(size_t r, int quoted, emit_fn emit) {
  print_term_ex(r, quoted, emit);
}

static int template_cyclic = 0;

static tterm_t *heap_to_template_rec(size_t r, int32_t *nseen) {
  r = heap_deref(r);
  switch (heap[r].tag) {
  case TAG_REF: {
    size_t m = heap_alloc(1);
    heap[m].tag = TAG_FUNCTOR;
    heap[m].as.func.atom_id = -1;
    heap[m].as.func.arity = *nseen;
    heap_bind(r, m);
    return tt_var((*nseen)++);
  }
  case TAG_FUNCTOR:
    return tt_var(heap[r].as.func.arity);
  case TAG_ATOM:
    return tt_atom(atom_name(heap[r].as.atom_id));
  case TAG_INT:
    return tt_int(heap[r].as.ival);
  case TAG_FLT:
    return tt_flt(heap[r].as.fval);
  case TAG_STR: {
    size_t f = heap[r].as.ptr;
    int32_t arity = heap[f].as.func.arity;
    if (arity < 0 || template_cyclic) {
      template_cyclic = 1;
      return tt_atom("[]");
    }
    tterm_t *args[arity > 0 ? arity : 1];
    heap[f].as.func.arity = -1 - arity;
    for (int32_t i = 0; i < arity; i++)
      args[i] = heap_to_template_rec(f + 1 + i, nseen);
    heap[f].as.func.arity = arity;
    return tt_struct(atom_name(heap[f].as.func.atom_id), arity, args);
  }
  }
  return NULL;
}

// 0 if any of terms is cyclic.
int heap_terms_to_templates(size_t *terms, int32_t n, tterm_t **out,
                            int32_t *nvars_out) {
  size_t hmark = heap_mark(), tmark = trail_mark();
  int32_t nseen = 0;
  template_cyclic = 0;
  for (int32_t i = 0; i < n; i++)
    out[i] = heap_to_template_rec(terms[i], &nseen);
  trail_release(tmark);
  heap_release(hmark);
  *nvars_out =
      nseen > 0 ? nseen : 1; // heap_copy's rename table is never zero-sized
  return !template_cyclic;
}

// NULL if r is cyclic.
tterm_t *heap_to_template(size_t r, int32_t *nvars_out) {
  tterm_t *t;
  return heap_terms_to_templates(&r, 1, &t, nvars_out) ? t : NULL;
}

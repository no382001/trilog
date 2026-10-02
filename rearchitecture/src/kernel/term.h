#pragma once
#include <stddef.h>
#include <stdint.h>

typedef enum { T_VAR, T_ATOM, T_INT, T_FLT, T_STR } ttag_t;

typedef struct tterm {
  ttag_t tag;
  union {
    int32_t slot;    // T_VAR
    int32_t atom_id; // T_ATOM
    int64_t ival;    // T_INT
    double fval;     // T_FLT
    struct {
      int32_t atom_id;
      int32_t arity;
      struct tterm **args;
    } str; // T_STR
  } as;
} tterm_t;

void term_init(void);

tterm_t *tt_var(int32_t slot);
tterm_t *tt_atom(const char *name);
tterm_t *tt_int(int64_t v);
tterm_t *tt_flt(double v);
tterm_t *tt_struct(const char *name, int32_t arity, tterm_t **args);

size_t heap_copy(tterm_t *t, size_t *rename, size_t cut_barrier);
size_t heap_copy_goal(tterm_t *t, size_t *rename, size_t cut_barrier);
size_t heap_rebake_cuts(size_t r, size_t cut_barrier);

void print_term(size_t r);
void print_term_quoted(size_t r);
typedef void (*emit_fn)(const char *s);
void print_term_via(size_t r, int quoted, emit_fn emit);

tterm_t *heap_to_template(size_t r, int32_t *nvars_out);

int heap_terms_to_templates(size_t *terms, int32_t n, tterm_t **out,
                            int32_t *nvars_out);

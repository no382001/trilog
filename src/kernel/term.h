#pragma once
#include "trilog.h"
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

tterm_t *tt_var(trilog_t *T, int32_t slot);
tterm_t *tt_atom(trilog_t *T, const char *name);
tterm_t *tt_int(trilog_t *T, int64_t v);
tterm_t *tt_flt(trilog_t *T, double v);
tterm_t *tt_struct(trilog_t *T, const char *name, int32_t arity,
                   tterm_t **args);

size_t heap_copy(trilog_t *T, tterm_t *t, size_t *rename, size_t cut_barrier);
size_t heap_copy_goal(trilog_t *T, tterm_t *t, size_t *rename,
                      size_t cut_barrier);
size_t heap_rebake_cuts(trilog_t *T, size_t r, size_t cut_barrier);

void print_term(trilog_t *T, size_t r);
void print_term_quoted(trilog_t *T, size_t r);
typedef void (*emit_fn)(trilog_t *T, const char *s);
enum { PRINT_QUOTED = 1, PRINT_NUMBERVARS = 2 };
void print_term_via(trilog_t *T, size_t r, int flags, emit_fn emit);

tterm_t *heap_to_template(trilog_t *T, size_t r, int32_t *nvars_out);

int heap_terms_to_templates(trilog_t *T, size_t *terms, int32_t n,
                            tterm_t **out, int32_t *nvars_out);

#pragma once
#include "term.h"
#include <stddef.h>
#include <stdint.h>

typedef enum { IDX_ANY, IDX_ATOM, IDX_INT, IDX_STRUCT } idx_kind_t;
typedef struct {
  int32_t pred_id;
  int32_t pred_arity;
  idx_kind_t kind;
  int32_t atom_id;
  int64_t ival;
  int32_t arity;
} idx_key_t;

typedef struct {
  tterm_t *head;
  tterm_t **body;
  int32_t nbody;
  int32_t nvars;
  idx_key_t key;
} clause_t;

typedef struct {
  size_t goals;
  int32_t clause_idx;
  size_t heap_mark;
  size_t trail_mark;
  size_t cut_barrier;
  size_t active_catch;
} frame_t;

typedef struct {
  size_t heap_mark, trail_mark;
  size_t sp_at_entry;
  size_t catcher, recovery;
  size_t continuation;
  size_t outer_active_catch;
} catch_frame_t;

catch_frame_t *catch_stack_array(void);
size_t catch_stack_size(void);
void catch_stack_set_size(size_t n);

void solve_init(void);

void db_add(tterm_t *head, tterm_t **body, int32_t nbody, int32_t nvars,
            int mark_static);

typedef enum { QUERY_FALSE, QUERY_TRUE, QUERY_ERROR } query_result_t;

typedef int (*solution_fn)(void *ud, int has_more);

query_result_t run_query(tterm_t **goals, int32_t ngoals, int32_t nvars,
                         solution_fn on_solution, void *ud);

size_t query_binding(int32_t i);

size_t query_error_ball(void);

int op_lookup_infix(int32_t name_atom_id, int *pri, int *assoc_code);
int op_lookup_prefix(int32_t name_atom_id, int *pri, int *assoc_code);

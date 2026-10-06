#pragma once
#include "term.h"
#include "trilog.h"
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
  int32_t source; // atom of the file it was consulted from, -1 if asserted
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

#define PRED_HASH_SIZE 1024
typedef struct pred_bucket {
  int32_t pred_id, pred_arity;
  int32_t *indices;
  int32_t count, cap;
  int dynamic;
  int32_t foreign;
  struct pred_bucket *next;
} pred_bucket_t;

typedef struct {
  trilog_fn fn;
  void *ud;
  const char *types;
  int32_t nin, nout;
} foreign_t;

void db_unload(trilog_t *T, int32_t source);

bool foreign_register(trilog_t *T, const char *name, const char *types,
                      int32_t nin, int32_t nout, trilog_fn fn, void *ud);

typedef struct {
  int32_t pred_id;
  int32_t pred_arity;
} pred_decl_t;

typedef struct {
  int32_t pred_id;
  int32_t pred_arity;
} dyn_decl_t;

catch_frame_t *catch_stack_array(trilog_t *T);
size_t catch_stack_size(trilog_t *T);
void catch_stack_set_size(trilog_t *T, size_t n);

void db_add(trilog_t *T, tterm_t *head, tterm_t **body, int32_t nbody,
            int32_t nvars, int mark_static);

typedef enum { QUERY_FALSE, QUERY_TRUE, QUERY_ERROR } query_result_t;

typedef int (*solution_fn)(void *ud, int has_more);

query_result_t run_query(trilog_t *T, tterm_t **goals, int32_t ngoals,
                         int32_t nvars, solution_fn on_solution, void *ud);

size_t query_binding(trilog_t *T, int32_t i);

size_t query_error_ball(trilog_t *T);

int op_lookup_infix(trilog_t *T, int32_t name_atom_id, int *pri,
                    int *assoc_code);
int op_lookup_prefix(trilog_t *T, int32_t name_atom_id, int *pri,
                     int *assoc_code);

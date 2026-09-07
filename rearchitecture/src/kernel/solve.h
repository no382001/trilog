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

void solve_init(void);

void db_add(tterm_t *head, tterm_t **body, int32_t nbody, int32_t nvars);

void run_query(tterm_t **goals, int32_t ngoals, int32_t nvars, const char **varnames, int interactive);

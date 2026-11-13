#pragma once
#include "term.h"
#include "trilog.h"

tterm_t *module_head(trilog_t *T, tterm_t *h);
// Before a directive: a dynamic/1 declaration makes its predicates private,
// and the goal and the clauses loaded so far refer to private names.
void module_directive(trilog_t *T, tterm_t **slot);
// Renames the references to private predicates in the clauses loaded so far.
void module_patch(trilog_t *T);
// Around a nested consult.
void module_enter(trilog_t *T);
void module_leave(trilog_t *T);
// Frees every saved module state, after an unwind or at trilog_free.
void module_state_drop(trilog_t *T);

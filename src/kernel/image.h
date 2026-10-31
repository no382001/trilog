#pragma once
#include "solve.h"
#include "term.h"

typedef struct {
  tterm_t *head;
  tterm_t **body;
  int32_t nbody, nvars, source;
} image_clause_t;

typedef struct {
  const char *const *atoms;
  int32_t natoms;
  const image_clause_t *clauses;
  int32_t nclauses;
  const dyn_decl_t *dynamic;
  int32_t ndynamic;
} image_t;

extern const image_t *const trilog_image;

bool image_load(trilog_t *T, const image_t *img);
void image_dump_register(trilog_t *T);

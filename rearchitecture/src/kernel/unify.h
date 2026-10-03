#pragma once
#include <stddef.h>

int unify(size_t a, size_t b);

// the table only starts recording after many pairs
typedef struct {
  size_t *a, *b; // open addressing; a[i] == SIZE_MAX marks an empty slot
  size_t cap, len, steps;
} pair_visits;
void pair_visits_reset(pair_visits *v);
int pair_visits_seen(pair_visits *v, size_t fa, size_t fb);
int unify_with_occurs_check(size_t a, size_t b);

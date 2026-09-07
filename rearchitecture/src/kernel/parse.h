#pragma once
#include "term.h"
#include <stdbool.h>
#include <stdint.h>

void parse_init(void);

bool consult_file(const char *path);

bool parse_query(const char *src, tterm_t ***goals_out, int32_t *ngoals_out,
                 int32_t *nvars_out, const char ***varnames_out);

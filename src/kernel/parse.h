#pragma once
#include "term.h"
#include "trilog.h"
#include <stdbool.h>
#include <stdint.h>

bool consult_file(trilog_t *T, const char *path, int32_t *source);
bool consult_string(trilog_t *T, const char *text);

bool parse_query(trilog_t *T, const char *src, tterm_t ***goals_out,
                 int32_t *ngoals_out, int32_t *nvars_out,
                 const char ***varnames_out);

bool parse_term_from_string(trilog_t *T, const char *src, tterm_t **term_out,
                            int32_t *nvars_out, const char ***varnames_out);

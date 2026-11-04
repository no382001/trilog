#pragma once
#include "trilog.h"
#include <stdbool.h>

// Runs goal and prints its answers. Interactive asks for ; between answers;
// otherwise every answer is printed.
trilog_status_t toplevel_query(trilog_t *t, const char *goal, bool interactive);

// Reads and runs one query per line until end of input or halt/0,1, and
// returns the status of the last query.
trilog_status_t toplevel_repl(trilog_t *t);

void toplevel_print_uncaught(trilog_t *t);

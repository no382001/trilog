#include "heap.h"
#include "io.h"
#include "parse.h"
#include "solve.h"
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// One line = one query - no support yet for a query spanning multiple lines.
static void repl(void) {
  char line[8192];
  while (io_read_line(line, sizeof line)) {
    int blank = 1;
    for (char *p = line; *p; p++)
      if (!isspace((unsigned char)*p)) {
        blank = 0;
        break;
      }
    if (blank)
      continue;

    tterm_t **goals;
    int32_t ngoals, nvars;
    const char **names;
    if (!parse_query(line, &goals, &ngoals, &nvars, &names))
      continue;
    run_query(goals, ngoals, nvars, names, RUN_INTERACTIVE);
  }
}

int main(int argc, char **argv) {
  io_hooks_init_default();
  heap_init();
  solve_init();

  if (!consult_file("boot/core.pl"))
    return 1;

  const char *query = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-e") && i + 1 < argc) {
      query = argv[++i];
    } else {
      if (!consult_file(argv[i]))
        return 1;
    }
  }

  if (query) {
    tterm_t **goals;
    int32_t ngoals, nvars;
    const char **names;
    if (!parse_query(query, &goals, &ngoals, &nvars, &names))
      return 1;
    run_query(goals, ngoals, nvars, names, RUN_BATCH);
  } else {
    repl();
  }

  return 0;
}

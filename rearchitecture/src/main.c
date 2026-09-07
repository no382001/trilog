#define _POSIX_C_SOURCE 200809L
#include "heap.h"
#include "io.h"
#include "parse.h"
#include "solve.h"
#include "term.h"
#include <ctype.h>
#include <libgen.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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

static const char *usage = "Usage: trilog [options] [file...]\n"
                           "  -e GOAL   evaluate GOAL and exit\n"
                           "  -f        fast startup: skip ~/.trilog\n"
                           "  -v        verbose: echo startup consults\n"
                           "  -h        show this help\n";

static void resolve_core_path(const char *argv0, char *out, size_t out_size) {
  char exe[4096];
  char dir[4096];
  ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
  if (len > 0) {
    exe[len] = '\0';
    strncpy(dir, exe, sizeof(dir) - 1);
  } else {
    strncpy(dir, argv0, sizeof(dir) - 1);
  }
  dir[sizeof(dir) - 1] = '\0';
  snprintf(out, out_size, "%s/boot/core.pl", dirname(dir));
}

static void load_init_file(int verbose) {
  const char *home = getenv("HOME");
  if (!home)
    return;
  char path[4096];
  snprintf(path, sizeof path, "%s/.trilog", home);
  if (verbose) {
    char msg[4096 + 32];
    snprintf(msg, sizeof msg, "?- consult('%s').\n", path);
    io_write_str(msg);
  }
  FILE *f = fopen(path, "r");
  if (!f) {
    if (verbose)
      io_write_str("false.\n");
    return;
  }
  fclose(f);
  consult_file(path);
}

int main(int argc, char **argv) {
  io_hooks_init_default();

  int fast = 0, verbose = 0;
  const char *query = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-h")) {
      io_write_str(usage);
      return 0;
    }
    if (!strcmp(argv[i], "-f")) {
      fast = 1;
    } else if (!strcmp(argv[i], "-v")) {
      verbose = 1;
    } else if (!strcmp(argv[i], "-e") && i + 1 < argc) {
      query = argv[++i];
    }
  }

  heap_init();
  term_init();
  solve_init();
  parse_init();

  char core_path[4096];
  resolve_core_path(argv[0], core_path, sizeof core_path);
  if (verbose) {
    char msg[4096 + 32];
    snprintf(msg, sizeof msg, "?- consult('%s').\n", core_path);
    io_write_str(msg);
  }
  if (!consult_file(core_path))
    return 1;
  if (!fast)
    load_init_file(verbose);

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-f") || !strcmp(argv[i], "-v")) {
      continue;
    } else if (!strcmp(argv[i], "-e") && i + 1 < argc) {
      i++;
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

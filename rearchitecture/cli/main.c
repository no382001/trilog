#include "terminal.h"
#include "trilog.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static trilog_t *T;

static void print_term(FILE *out, trilog_term_t term) {
  char small[256];
  size_t n = trilog_format(T, term, 0, small, sizeof small);
  if (n < sizeof small) {
    fputs(small, out);
    return;
  }
  char *big = malloc(n + 1);
  if (!big) {
    fputs("...", out);
    return;
  }
  trilog_format(T, term, 0, big, n + 1);
  fputs(big, out);
  free(big);
}

static void print_uncaught(void) {
  fputs("uncaught exception: ", stderr);
  print_term(stderr, trilog_error_term(T));
  fputs("\n", stderr);
}

typedef struct {
  bool interactive;
  bool any_found;
  bool closed;
} toplevel_state;

static bool toplevel_solution(trilog_t *t, void *ud, bool has_more) {
  toplevel_state *st = ud;
  fputs(st->any_found ? "\n;  " : "   ", stdout);
  st->any_found = true;
  int n = trilog_binding_count(t);
  for (int i = 0; i < n; i++) {
    printf("%s%s = ", i ? ", " : "", trilog_binding_name(t, i));
    print_term(stdout, trilog_binding_value(t, i));
  }
  if (n == 0)
    fputs("true", stdout);
  if (has_more) {
    fflush(stdout);
    int key = st->interactive ? terminal_read_key() : ';';
    if (key == ';' || key == ' ')
      return true;
  }
  fputs(".\n", stdout);
  st->closed = true;
  return false;
}

static void toplevel_query(const char *goal, bool interactive) {
  toplevel_state st = {.interactive = interactive};
  switch (trilog_query(T, goal, toplevel_solution, &st)) {
  case TRILOG_TRUE:
    if (!st.closed)
      fputs(".\n", stdout);
    break;
  case TRILOG_FALSE:
    fputs("   false.\n", stdout);
    break;
  case TRILOG_ERROR:
    if (trilog_term_type(T, trilog_error_term(T)) != TRILOG_INVALID)
      print_uncaught();
    break;
  case TRILOG_HALT:
    exit(trilog_halt_code(T));
  case TRILOG_ABORTED:
    break;
  }
}

static bool batch_solution(trilog_t *t, void *ud, bool has_more) {
  (void)ud;
  (void)has_more;
  fputs("yes:", stdout);
  int n = trilog_binding_count(t);
  for (int i = 0; i < n; i++) {
    printf(" %s=", trilog_binding_name(t, i));
    print_term(stdout, trilog_binding_value(t, i));
  }
  fputs("\n", stdout);
  return true;
}

// One line, one query TODO: no support yet for a query spanning multiple lines.
static void repl(void) {
  bool interactive = terminal_stdin_is_tty();
  char line[8192];
  for (;;) {
    if (interactive) {
      fputs("?- ", stdout);
      fflush(stdout);
    }
    if (!fgets(line, sizeof line, stdin))
      break;
    line[strcspn(line, "\n")] = '\0';

    int blank = 1;
    for (char *p = line; *p; p++)
      if (!isspace((unsigned char)*p)) {
        blank = 0;
        break;
      }
    if (blank)
      continue;
    toplevel_query(line, interactive);
  }
}

static const char *usage = "Usage: trilog [options] [file...]\n"
                           "  -e GOAL   evaluate GOAL and exit\n"
                           "  -f        fast startup: skip ~/.trilog\n"
                           "  -v        verbose: echo startup consults\n"
                           "  -s        print resource-usage stats on exit\n"
                           "  -h        show this help\n";

static void print_exit_stats(void) {
  if (!T)
    return;
  trilog_usage_t u;
  trilog_usage(T, &u);
  fprintf(stderr, "heap_peak_cells=%zu\nheap_peak_bytes=%zu\n",
          u.heap_peak_cells, u.heap_peak_bytes);
}

// TODO: This probably should be NDEBUG or something
#ifdef TRILOG_EMBEDDED
// The release build bakes boot/ and lib/ into the binary
static void resolve_core_path(const char *argv0, char *out, size_t out_size) {
  (void)argv0;
  snprintf(out, out_size, "embedded:boot/core.pl");
}
#else
// The dev build reads boot/core.pl from next to the binary
static void resolve_core_path(const char *argv0, char *out, size_t out_size) {
  char dir[4096 - sizeof "/boot/core.pl"];
  char exe[4096];
  const char *self = terminal_executable_path(exe, sizeof exe) ? exe : argv0;
  size_t n = strlen(self);
  if (n >= sizeof dir)
    n = 0;
  memcpy(dir, self, n);
  dir[n] = '\0';
  char *sep = strrchr(dir, '/');
  char *bsep = strrchr(dir, '\\');
  if (bsep && (!sep || bsep > sep))
    sep = bsep;
  if (sep)
    *sep = '\0';
  else
    snprintf(dir, sizeof dir, ".");
  snprintf(out, out_size, "%s/boot/core.pl", dir);
}
#endif

static void load_init_file(int verbose) {
  const char *home = getenv("HOME");
  if (!home)
    return;
  char path[4096];
  snprintf(path, sizeof path, "%s/.trilog", home);
  if (verbose)
    printf("?- consult('%s').\n", path);
  FILE *f = fopen(path, "r");
  if (!f) {
    if (verbose)
      fputs("false.\n", stdout);
    return;
  }
  fclose(f);
  if (trilog_load_file(T, path) == TRILOG_HALT)
    exit(trilog_halt_code(T));
}

int main(int argc, char **argv) {
  int fast = 0, verbose = 0, exit_stats = 0;
  const char *query = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-h")) {
      fputs(usage, stdout);
      return 0;
    }
    if (!strcmp(argv[i], "-f")) {
      fast = 1;
    } else if (!strcmp(argv[i], "-v")) {
      verbose = 1;
    } else if (!strcmp(argv[i], "-s")) {
      exit_stats = 1;
    } else if (!strcmp(argv[i], "-e") && i + 1 < argc) {
      query = argv[++i];
    }
  }
  if (exit_stats)
    atexit(print_exit_stats);

  char core_path[4096];
  resolve_core_path(argv[0], core_path, sizeof core_path);
  if (verbose)
    printf("?- consult('%s').\n", core_path);
  T = trilog_new(&(trilog_config_t){.boot_path = core_path});
  if (!T)
    return 1;
  if (!fast)
    load_init_file(verbose);

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-f") || !strcmp(argv[i], "-v") ||
        !strcmp(argv[i], "-s")) {
      continue;
    } else if (!strcmp(argv[i], "-e") && i + 1 < argc) {
      i++;
    } else {
      trilog_status_t s = trilog_load_file(T, argv[i]);
      if (s == TRILOG_HALT)
        exit(trilog_halt_code(T));
      if (s != TRILOG_TRUE)
        return 1;
    }
  }

  if (query) {
    trilog_status_t s = trilog_query(T, query, batch_solution, NULL);
    if (s == TRILOG_HALT)
      exit(trilog_halt_code(T));
    if (s == TRILOG_ERROR) {
      if (trilog_term_type(T, trilog_error_term(T)) == TRILOG_INVALID)
        return 1;
      print_uncaught();
    }
  } else {
    repl();
  }

  return 0;
}

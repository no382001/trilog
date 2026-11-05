#include "toplevel.h"
#include "terminal.h"
#include <stdio.h>
#include <stdlib.h>

#ifndef TOPLEVEL_LINE_MAX
#define TOPLEVEL_LINE_MAX 8192
#endif

static size_t format_term(trilog_t *t, trilog_term_t *term, char *buf,
                          size_t cap) {
  return term ? trilog_format(t, *term, TRILOG_FORMAT_QUOTED, buf, cap)
              : trilog_format_answer(t, buf, cap);
}

static void print_formatted(trilog_t *t, FILE *out, trilog_term_t *term) {
  char small[256];
  size_t n = format_term(t, term, small, sizeof small);
  if (n < sizeof small) {
    fputs(small, out);
    return;
  }
  char *big = malloc(n + 1);
  if (!big) {
    fputs("...", out);
    return;
  }
  format_term(t, term, big, n + 1);
  fputs(big, out);
  free(big);
}

void toplevel_print_uncaught(trilog_t *t) {
  fputs("uncaught exception: ", stderr);
  trilog_term_t ball = trilog_error_term(t);
  print_formatted(t, stderr, &ball);
  fputs("\n", stderr);
}

typedef struct {
  bool interactive;
  bool any_found;
  bool closed;
  bool all; // `a` was pressed: print every remaining answer
} toplevel_state;

static int typed_ahead = EOF;

static bool toplevel_solution(trilog_t *t, void *ud, bool has_more) {
  toplevel_state *st = ud;
  fputs(st->any_found ? "\n;  " : "   ", stdout);
  st->any_found = true;
  print_formatted(t, stdout, NULL);
  if (has_more) {
    if (st->all)
      return true;
    fflush(stdout);
    int key = st->interactive ? terminal_read_key() : ';';
    if (key == 'a')
      st->all = true;
    if (key == ';' || key == ' ' || key == 'a')
      return true;
    if (key > ' ' && key != '.' && key < 127)
      typed_ahead = key;
    fputs("\n;  ... .\n", stdout);
    st->closed = true;
    return false;
  }
  fputs(".\n", stdout);
  st->closed = true;
  return false;
}

int toplevel_typed_ahead(void) {
  int c = typed_ahead;
  typed_ahead = EOF;
  return c;
}

trilog_status_t toplevel_query(trilog_t *t, const char *goal,
                               bool interactive) {
  toplevel_state st = {.interactive = interactive};
  trilog_status_t s = trilog_query(t, goal, toplevel_solution, &st);
  switch (s) {
  case TRILOG_TRUE:
    if (!st.closed)
      fputs(".\n", stdout);
    break;
  case TRILOG_FALSE:
    fputs("   false.\n", stdout);
    break;
  case TRILOG_ERROR:
    if (trilog_term_type(t, trilog_error_term(t)) != TRILOG_INVALID)
      toplevel_print_uncaught(t);
    break;
  case TRILOG_HALT:
  case TRILOG_ABORTED:
    break;
  }
  return s;
}

static bool tl_tty(trilog_t *t, void *ud, const trilog_value_t *in,
                   trilog_value_t *out) {
  (void)t, (void)ud, (void)in, (void)out;
  return terminal_stdin_is_tty();
}

static bool tl_key(trilog_t *t, void *ud, const trilog_value_t *in,
                   trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  fflush(stdout);
  out[0].i = terminal_read_key();
  return true;
}

static bool tl_raw(trilog_t *t, void *ud, const trilog_value_t *in,
                   trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  return terminal_raw(in[0].i != 0);
}

static bool tl_history_file(trilog_t *t, void *ud, const trilog_value_t *in,
                            trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  static char path[4096];
  if (!terminal_history_path(path, sizeof path))
    return false;
  out[0].a = path;
  return true;
}

static bool tl_read_line(trilog_t *t, void *ud, const trilog_value_t *in,
                         trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  static char line[TOPLEVEL_LINE_MAX];
  if (!terminal_read_line(line, sizeof line))
    return false;
  out[0].a = line;
  return true;
}

static bool stop_after_first(trilog_t *t, void *ud, bool has_more) {
  (void)t, (void)ud, (void)has_more;
  return false;
}

trilog_status_t toplevel_repl(trilog_t *t) {
  if (terminal_stdin_is_tty())
    printf("trilog %s\n", trilog_version());
  trilog_register(t, "$tl_tty", "", tl_tty, NULL);
  trilog_register(t, "$tl_key", ">i", tl_key, NULL);
  trilog_register(t, "$tl_read_line", ">a", tl_read_line, NULL);
  trilog_register(t, "$tl_raw", "i", tl_raw, NULL);
  trilog_register(t, "$tl_history_file", ">a", tl_history_file, NULL);
  trilog_status_t s = trilog_query(t, "use_module(library(toplevel)), toplevel",
                                   stop_after_first, NULL);
  if (s == TRILOG_ERROR &&
      trilog_term_type(t, trilog_error_term(t)) != TRILOG_INVALID)
    toplevel_print_uncaught(t);
  return s;
}

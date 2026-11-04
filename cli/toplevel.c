#include "toplevel.h"
#include "terminal.h"
#include <ctype.h>
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

// One line, one query TODO: no support yet for a query spanning multiple lines.
trilog_status_t toplevel_repl(trilog_t *t) {
  bool interactive = terminal_stdin_is_tty();
  if (interactive)
    printf("trilog %s\n", trilog_version());
  static char line[TOPLEVEL_LINE_MAX];
  trilog_status_t s = TRILOG_TRUE;
  for (;;) {
    if (interactive) {
      fputs("?- ", stdout);
      fflush(stdout);
    }
    size_t n = 0;
    if (typed_ahead != EOF) {
      line[n++] = (char)typed_ahead;
      putchar(typed_ahead);
      typed_ahead = EOF;
    }
    if (!terminal_read_line(line + n, sizeof line - n))
      break;

    int blank = 1;
    for (char *p = line; *p; p++)
      if (!isspace((unsigned char)*p)) {
        blank = 0;
        break;
      }
    if (blank)
      continue;
    s = toplevel_query(t, line, interactive);
    if (s == TRILOG_HALT)
      break;
  }
  return s;
}

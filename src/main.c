#define _POSIX_C_SOURCE 200809L
#include "platform_impl.h"
#include <getopt.h>
#include <libgen.h>
#include <termios.h>
#include <unistd.h>

#define CORE_PATH_MAX 8192

static void try_load_core(abclog_ctx_t *ctx, const char *argv0) {
  char exe[CORE_PATH_MAX];
  char dir[CORE_PATH_MAX];

  ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
  if (len > 0) {
    exe[len] = '\0';
    strncpy(dir, exe, sizeof(dir) - 1);
    dir[sizeof(dir) - 1] = '\0';
  } else {
    strncpy(dir, argv0, sizeof(dir) - 1);
    dir[sizeof(dir) - 1] = '\0';
  }
  dirname(dir);

  char path[CORE_PATH_MAX];
  strncpy(path, dir, sizeof(path) - 9);
  path[sizeof(path) - 9] = '\0';
  strcat(path, "/core.pl");

  if (io_file_exists(ctx, path))
    abclog_load_file(ctx, path);
}

static int read_key(void) {
  struct termios old, raw;
  tcgetattr(STDIN_FILENO, &old);
  raw = old;
  raw.c_lflag &= ~(ICANON | ECHO);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
  int c = getchar();
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &old);
  return c;
}

static void print_usage(abclog_ctx_t *ctx, const char *prog) {
  io_writef_err(
      ctx,
      "Usage: %s [-d] [-f <file>] [-e <expression>] [-q <file>] [-j <dir>]\n",
      prog);
  io_writef_err(ctx, "  -d            Enable debug mode\n");
  io_writef_err(ctx, "  -f <file>     Load clauses from file\n");
  io_writef_err(ctx, "  -e <expr>     Execute expression and exit\n");
  io_writef_err(ctx, "  -q <file>     Run quad tests from file\n");
  io_writef_err(ctx, "  -j <dir>      Write JUnit XML reports to directory\n");
  io_writef_err(ctx, "  -h            Show this help\n");
  io_writef_err(ctx, "\nInteractive commands:\n");
  io_writef_err(ctx, "  debug.        Toggle debug mode\n");
  io_writef_err(ctx, "  halt.         Exit the interpreter\n");
}

typedef struct {
  bool interactive;
  bool want_more; // true if user typed ; on the last solution
  bool first;     // true before any answer has been printed
  bool all;       // true if user pressed 'a' to emit all answers
} toplevel_state_t;

static bool toplevel_cb(abclog_ctx_t *ctx, env_t *env, void *ud,
                        bool has_more) {
  toplevel_state_t *st = ud;

  if (st->first) {
    io_write_str(ctx, "   ");
    st->first = false;
  } else {
    io_write_str(ctx, ";  ");
  }

  print_bindings(ctx, env);
  st->want_more = false;

  if (!st->interactive || !has_more) {
    io_write_str(ctx, ".\n");
    return false;
  }

  if (st->all) {
    io_write_str(ctx, "\n");
    st->want_more = true;
    return true;
  }

  int c = read_key();
  io_write_str(ctx, "\n");
  st->want_more = (c == ';' || c == 'a');
  st->all = (c == 'a');
  return st->want_more;
}

static void exec_query(abclog_ctx_t *ctx, char *query, bool interactive) {
  toplevel_state_t st = {
      .interactive = interactive, .want_more = false, .first = true};
  bool found = abclog_exec_query_multi(ctx, query, toplevel_cb, &st);
  if (!ctx->has_runtime_error && (!found || st.want_more))
    io_write_str(ctx, "false.\n");
  ctx->has_runtime_error = false;
}

static void process_line(abclog_ctx_t *ctx, char *line, bool *should_exit,
                         bool interactive) {
  line[strcspn(line, "\n")] = 0;
  if (strlen(line) == 0)
    return;
  if (strcmp(line, "halt.") == 0) {
    *should_exit = true;
    return;
  }

  if (strcmp(line, "debug.") == 0) {
    ctx->debug_enabled = !ctx->debug_enabled;
    io_writef(ctx, "Debug mode %s\n",
              ctx->debug_enabled ? "enabled" : "disabled");
    return;
  }

  parse_error_clear(ctx);
  ctx->input_line++;

  char *query = (strncmp(line, "?-", 2) == 0) ? line + 2 : line;
  exec_query(ctx, query, interactive);
}

static bool load_file(abclog_ctx_t *ctx, const char *filename) {
  return abclog_load_file(ctx, filename);
}

int main(int argc, char *argv[]) {
  abclog_ctx_t *ctx = malloc(ABCLOG_CTX_SIZE(TERM_POOL_BYTES));
  if (!ctx) {
    fprintf(stderr, "Fatal: failed to allocate abclog context\n");
    return 1;
  }
  abclog_ctx_init(ctx, TERM_POOL_BYTES);

  io_hooks_init_default(ctx);
  try_load_core(ctx, argv[0]);

  const char *input_file = NULL;
  const char *expression = NULL;
  const char *quad_file = NULL;
  const char *junit_dir = NULL;
  int opt;

  while ((opt = getopt(argc, argv, "df:e:q:j:h")) != -1) {
    switch (opt) {
    case 'd':
      ctx->debug_enabled = true;
      io_writef_err(ctx, "Debug mode enabled\n");
      break;
    case 'f':
      input_file = optarg;
      break;
    case 'e':
      expression = optarg;
      break;
    case 'q':
      quad_file = optarg;
      break;
    case 'j':
      junit_dir = optarg;
      break;
    case 'h':
      print_usage(ctx, argv[0]);
      return 0;
    default:
      print_usage(ctx, argv[0]);
      return 1;
    }
  }

  if (input_file) {
    if (!load_file(ctx, input_file)) {
      return 1;
    }
  }

  if (expression) {
    char line[1024];
    strncpy(line, expression, sizeof(line) - 1);
    bool should_exit = false;
    process_line(ctx, line, &should_exit, false);
    return parse_has_error(ctx) ? 1 : 0;
  }

  if (quad_file) {
    quad_results_t res;
    if (junit_dir)
      res = abclog_run_quad_file_junit(ctx, quad_file, junit_dir);
    else
      res = abclog_run_quad_file(ctx, quad_file);

    free(ctx);
    return res.failed > 0 ? 1 : 0;
  }

  char line[1024];
  bool interactive = isatty(STDIN_FILENO);
  bool should_exit = false;

  while (!should_exit) {
    if (interactive) {
      io_write_str(ctx, "?- ");
      fflush(stdout);
    }

    if (!fgets(line, sizeof(line), stdin))
      break;
    process_line(ctx, line, &should_exit, interactive);
  }

  free(ctx);
  return 0;
}
#include "../src/platform_impl.h"
#include <emscripten.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define WEB_OUT_SIZE    (64 * 1024)
#define INPUT_QUEUE_MAX 16
#define INPUT_LINE_MAX  4096

static prolog_ctx_t *g_ctx = NULL;
static char g_out[WEB_OUT_SIZE];
static int  g_out_pos = 0;

// input queue: js pushes lines, web_read_line consumes them
static char g_input_queue[INPUT_QUEUE_MAX][INPUT_LINE_MAX];
static int  g_input_head = 0;
static int  g_input_tail = 0;
static bool g_reading    = false;

static void web_write_str(prolog_ctx_t *ctx, const char *str, void *ud) {
  (void)ctx; (void)ud;
  int len = (int)strlen(str);
  int rem = WEB_OUT_SIZE - 1 - g_out_pos;
  if (len > rem) len = rem;
  memcpy(g_out + g_out_pos, str, (size_t)len);
  g_out_pos += len;
  g_out[g_out_pos] = '\0';
}

static void web_writef(prolog_ctx_t *ctx, const char *fmt, va_list args,
                       void *ud) {
  (void)ctx; (void)ud;
  int rem = WEB_OUT_SIZE - 1 - g_out_pos;
  if (rem <= 0) return;
  int n = vsnprintf(g_out + g_out_pos, (size_t)rem, fmt, args);
  if (n > 0) g_out_pos += (n < rem ? n : rem);
  g_out[g_out_pos] = '\0';
}

static char *web_read_line(prolog_ctx_t *ctx, char *buf, int size, void *ud) {
  (void)ctx; (void)ud;
  g_reading = true;
  while (g_input_head == g_input_tail)
    emscripten_sleep(10);
  g_reading = false;
  strncpy(buf, g_input_queue[g_input_head], size - 1);
  buf[size - 1] = '\0';
  g_input_head = (g_input_head + 1) % INPUT_QUEUE_MAX;
  return buf;
}

typedef struct { bool first; bool want_more; } web_cb_state_t;

static bool web_toplevel_cb(prolog_ctx_t *ctx, env_t *env, void *ud,
                            bool has_more) {
  web_cb_state_t *st = ud;
  st->want_more = false;
  io_write_str(ctx, st->first ? "   " : ";  ");
  st->first = false;
  print_bindings(ctx, env);
  if (!has_more) { io_write_str(ctx, ".\n"); return false; }
  io_write_str(ctx, "\n");
  st->want_more = true;
  return true;
}

EMSCRIPTEN_KEEPALIVE
void prolog_web_push_line(const char *line) {
  int next = (g_input_tail + 1) % INPUT_QUEUE_MAX;
  if (next == g_input_head) return; // full, drop
  strncpy(g_input_queue[g_input_tail], line, INPUT_LINE_MAX - 2);
  g_input_queue[g_input_tail][INPUT_LINE_MAX - 2] = '\0';
  int len = (int)strlen(g_input_queue[g_input_tail]);
  g_input_queue[g_input_tail][len]     = '\n';
  g_input_queue[g_input_tail][len + 1] = '\0';
  g_input_tail = next;
}

EMSCRIPTEN_KEEPALIVE
int prolog_web_is_reading(void) { return g_reading ? 1 : 0; }

// return and clear any buffered output produced so far (usable while blocked).
EMSCRIPTEN_KEEPALIVE
const char *prolog_web_take_output(void) {
  static char tmp[WEB_OUT_SIZE];
  memcpy(tmp, g_out, (size_t)(g_out_pos + 1));
  g_out_pos = 0;
  g_out[0]  = '\0';
  return tmp;
}

EMSCRIPTEN_KEEPALIVE
void prolog_web_init(void) {
  if (g_ctx) { free(g_ctx); g_ctx = NULL; }
  g_ctx = malloc(PROLOG_CTX_SIZE(TERM_POOL_BYTES));
  if (!g_ctx) return;
  prolog_ctx_init(g_ctx, TERM_POOL_BYTES);
  io_hooks_init_default(g_ctx);

  io_hooks_t hooks = {0};
  hooks.write_str  = web_write_str;
  hooks.writef     = web_writef;
  hooks.writef_err = web_writef;
  hooks.read_line  = web_read_line;
  io_hooks_set(g_ctx, &hooks);

  prolog_load_file(g_ctx, "/core.pl");
}

EMSCRIPTEN_KEEPALIVE
const char *prolog_web_eval(const char *query) {
  if (!g_ctx) return "error: not initialized\n";

  g_out_pos = 0;
  g_out[0]  = '\0';

  char buf[4096];
  strncpy(buf, query, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';
  char *qptr = (strncmp(buf, "?-", 2) == 0) ? buf + 2 : buf;

  web_cb_state_t st = {.first = true, .want_more = false};
  bool found = prolog_exec_query_multi(g_ctx, qptr, web_toplevel_cb, &st);

  if (!g_ctx->has_runtime_error && (!found || st.want_more))
    io_write_str(g_ctx, "false.\n");
  g_ctx->has_runtime_error = false;
  return g_out;
}

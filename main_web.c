#include "../src/platform_impl.h"
#include <emscripten.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define WEB_OUT_SIZE    (64 * 1024)
#define INPUT_QUEUE_MAX 16
#define INPUT_LINE_MAX  4096

static trilog_ctx_t *g_ctx = NULL;
static char g_out[WEB_OUT_SIZE];
static int  g_out_pos = 0;

// input queue: js pushes lines, web_read_line/web_read_char consume them
static char g_input_queue[INPUT_QUEUE_MAX][INPUT_LINE_MAX];
static int  g_input_head = 0;
static int  g_input_tail = 0;
static bool g_reading    = false;
static bool g_choosing   = false; // true while waiting for ; / Enter between solutions

static void web_write_str(trilog_ctx_t *ctx, const char *str, void *ud) {
  (void)ctx; (void)ud;
  int len = (int)strlen(str);
  int rem = WEB_OUT_SIZE - 1 - g_out_pos;
  if (len > rem) len = rem;
  memcpy(g_out + g_out_pos, str, (size_t)len);
  g_out_pos += len;
  g_out[g_out_pos] = '\0';
}

static void web_writef(trilog_ctx_t *ctx, const char *fmt, va_list args,
                       void *ud) {
  (void)ctx; (void)ud;
  int rem = WEB_OUT_SIZE - 1 - g_out_pos;
  if (rem <= 0) return;
  int n = vsnprintf(g_out + g_out_pos, (size_t)rem, fmt, args);
  if (n > 0) g_out_pos += (n < rem ? n : rem);
  g_out[g_out_pos] = '\0';
}

static char *web_read_line(trilog_ctx_t *ctx, char *buf, int size, void *ud) {
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

EMSCRIPTEN_KEEPALIVE
void trilog_web_push_line(const char *line) {
  int next = (g_input_tail + 1) % INPUT_QUEUE_MAX;
  if (next == g_input_head) return; // full, drop
  strncpy(g_input_queue[g_input_tail], line, INPUT_LINE_MAX - 2);
  g_input_queue[g_input_tail][INPUT_LINE_MAX - 2] = '\0';
  int len = (int)strlen(g_input_queue[g_input_tail]);
  g_input_queue[g_input_tail][len]     = '\n';
  g_input_queue[g_input_tail][len + 1] = '\0';
  g_input_tail = next;
}

// consume first char of the next queued entry; used during interactive answer prompt
static int web_read_char(trilog_ctx_t *ctx, void *ud) {
  (void)ctx; (void)ud;
  g_choosing = true;
  g_reading  = true;
  while (g_input_head == g_input_tail)
    emscripten_sleep(10);
  g_reading  = false;
  g_choosing = false;
  int c = (unsigned char)g_input_queue[g_input_head][0];
  g_input_head = (g_input_head + 1) % INPUT_QUEUE_MAX;
  return c ? c : '\n';
}

EMSCRIPTEN_KEEPALIVE
int trilog_web_is_reading(void)   { return g_reading   ? 1 : 0; }

EMSCRIPTEN_KEEPALIVE
int trilog_web_is_choosing(void)  { return g_choosing  ? 1 : 0; }

// return and clear any buffered output produced so far (usable while blocked).
EMSCRIPTEN_KEEPALIVE
const char *trilog_web_take_output(void) {
  static char tmp[WEB_OUT_SIZE];
  memcpy(tmp, g_out, (size_t)(g_out_pos + 1));
  g_out_pos = 0;
  g_out[0]  = '\0';
  return tmp;
}

EMSCRIPTEN_KEEPALIVE
void trilog_web_init(void) {
  if (g_ctx) { free(g_ctx); g_ctx = NULL; }
  g_ctx = malloc(TRILOG_CTX_SIZE(TERM_POOL_BYTES));
  if (!g_ctx) return;
  trilog_ctx_init(g_ctx, TERM_POOL_BYTES);
  io_hooks_init_default(g_ctx);

  io_hooks_t hooks = {0};
  hooks.write_str  = web_write_str;
  hooks.writef     = web_writef;
  hooks.writef_err = web_writef;
  hooks.read_line  = web_read_line;
  hooks.read_char  = web_read_char;
  io_hooks_set(g_ctx, &hooks);

  trilog_load_file(g_ctx, "/core.pl");
}

// yield callback: fires every n steps, lets js poll stats in real-time.
// uses emscripten_sleep(0) to yield to the browser event loop so js can
// read the stats buffer and update visualizations.
static bool web_yield_cb(trilog_ctx_t *ctx, int depth, void *ud) {
  (void)ud;
  (void)depth;
  (void)ctx;
  emscripten_sleep(0); // yield to browser
  return true;
}

EMSCRIPTEN_KEEPALIVE
void trilog_web_set_yield(int interval) {
  if (!g_ctx) return;
  if (interval <= 0) {
    trilog_set_yield(g_ctx, NULL, 0, NULL);
  } else {
    trilog_set_yield(g_ctx, web_yield_cb, interval, NULL);
  }
}

// stats snapshot: returns pointer to a static int array js can read.
// layout: [son_calls, unify_calls, unify_fails, backtracks,
//          terms_allocated, terms_peak, stack_peak]
static int g_stats_buf[7];

EMSCRIPTEN_KEEPALIVE
int *trilog_web_get_stats(void) {
  if (!g_ctx) return g_stats_buf;
  g_stats_buf[0] = g_ctx->stats.son_calls;
  g_stats_buf[1] = g_ctx->stats.unify_calls;
  g_stats_buf[2] = g_ctx->stats.unify_fails;
  g_stats_buf[3] = g_ctx->stats.backtracks;
  g_stats_buf[4] = g_ctx->stats.terms_allocated;
  g_stats_buf[5] = g_ctx->stats.terms_peak;
  g_stats_buf[6] = g_ctx->stats.stack_peak;
  return g_stats_buf;
}

// resource usage snapshot: [used, total] pairs for term_pool, string_pool,
// clauses, bindings, stack
static int g_usage_buf[10];

EMSCRIPTEN_KEEPALIVE
int *trilog_web_get_usage(void) {
  if (!g_ctx) return g_usage_buf;
  trilog_usage_t u = trilog_get_usage(g_ctx);
  g_usage_buf[0] = u.term_pool_used;
  g_usage_buf[1] = u.term_pool_total;
  g_usage_buf[2] = u.string_pool_used;
  g_usage_buf[3] = u.string_pool_total;
  g_usage_buf[4] = u.clauses_used;
  g_usage_buf[5] = u.clauses_total;
  g_usage_buf[6] = u.bindings_used;
  g_usage_buf[7] = u.bindings_total;
  g_usage_buf[8] = u.stack_peak;
  g_usage_buf[9] = u.stack_total;
  return g_usage_buf;
}

EMSCRIPTEN_KEEPALIVE
const char *trilog_web_eval(const char *query) {
  if (!g_ctx) return "error: not initialized\n";

  g_out_pos = 0;
  g_out[0]  = '\0';

  char buf[4096];
  strncpy(buf, query, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';

  exec_query_interactive(g_ctx, buf);
  return g_out;
}

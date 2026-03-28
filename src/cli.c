#include "platform_impl.h"

typedef struct {
  bool want_more;
  toplevel_state_t base;
} interactive_state_t;

static bool interactive_cb(trilog_ctx_t *ctx, env_t *env, void *ud,
                           bool has_more) {
  interactive_state_t *st = ud;
  st->want_more = false;

  io_write_str(ctx, st->base.first ? "   " : "\n;  ");
  st->base.first = false;
  print_bindings(ctx, env);

  if (!has_more) {
    io_write_str(ctx, ".\n");
    st->base.done = true;
    return false;
  }

  int c = io_read_char(ctx);
  st->want_more = (c == ';' || c == ' ');
  if (!st->want_more) {
    io_write_str(ctx, ".\n");
    st->base.done = true;
  }
  return st->want_more;
}

void exec_query_interactive(trilog_ctx_t *ctx, char *query) {
  char *qptr = (strncmp(query, "?-", 2) == 0) ? query + 2 : query;

  interactive_state_t st = {.base = {.first = true}};
  bool found = trilog_exec_query_multi(ctx, qptr, interactive_cb, &st);
  if (!ctx->has_runtime_error && (!found || st.want_more))
    io_write_str(ctx, "   false.\n");
  else if (found && !st.base.done)
    io_write_str(ctx, ".\n");
  ctx->has_runtime_error = false;
  ctx->term_pool_offset = 0;
  compact_perm_pool(ctx);
}

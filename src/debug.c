#include "platform_impl.h"

void debug(trilog_ctx_t *ctx, const char *fmt, ...) {
  if (!ctx->debug_enabled)
    return;
  va_list args;
  va_start(args, fmt);
  if (ctx->io_hooks.writef) {
    ctx->io_hooks.writef(ctx, fmt, args, ctx->io_hooks.userdata);
  }
  va_end(args);
}

void print_term_raw(trilog_ctx_t *ctx, term_t *t) {
  if (!t) {
    io_writef_err(ctx, "NULL");
    return;
  }

  switch (t->type) {
  case CONST:
    io_writef_err(ctx, "CONST(%s)", t->name);
    break;
  case VAR:
    if (t->name)
      io_writef_err(ctx, "VAR(%s,%d)", t->name, t->arity);
    else
      io_writef_err(ctx, "VAR(_G%d)", t->arity);
    break;
  case INT:
    io_writef_err(ctx, "INT(%s)", t->name);
    break;
  case FUNC:
    io_writef_err(ctx, "FUNC(%s,%d,[", t->name, t->arity);
    for (int i = 0; i < t->arity; i++) {
      if (i > 0)
        io_writef_err(ctx, ",");
      print_term_raw(ctx, t->args[i]);
    }
    io_writef_err(ctx, "])");
    break;
  default:
    assert(false && "Invalid term type");
  }
}

void debug_term_raw(trilog_ctx_t *ctx, term_t *t) {
  if (!ctx->debug_enabled)
    return;
  print_term_raw(ctx, t);
}
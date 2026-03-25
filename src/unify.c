#include "platform_impl.h"

bool unify(trilog_ctx_t *ctx, term_t *a, term_t *b, env_t *env) {
  assert(ctx != NULL && "Context is NULL");
  assert(env != NULL && "Environment is NULL");

  ctx->stats.unify_calls++;

  a = deref(env, a);
  b = deref(env, b);

  if (ctx->debug_enabled) {
    debug(ctx, "UNIFY: ");
    debug_term_raw(ctx, a);
    debug(ctx, " WITH ");
    debug_term_raw(ctx, b);
    debug(ctx, "\n");
  }

  if (!a || !b) {
    debug(ctx, "  -> FAIL (null)\n");
    ctx->stats.unify_fails++;
    return false;
  }

  if (a->type == VAR) {
    bind(ctx, env, a, b);
    debug(ctx, "  -> OK (bind var a)\n");
    return true;
  }
  if (b->type == VAR) {
    bind(ctx, env, b, a);
    debug(ctx, "  -> OK (bind var b)\n");
    return true;
  }

  if (a->type == CONST && b->type == CONST) {
    bool result = a->name == b->name;
    debug(ctx, "  -> %s (const=%s vs %s)\n", result ? "OK" : "FAIL", a->name,
          b->name);
    return result;
  }

  if (a->type == FUNC && b->type == FUNC) {
    if (a->name != b->name || a->arity != b->arity) {
      debug(ctx, "  -> FAIL (func mismatch: %s/%d vs %s/%d)\n", a->name,
            a->arity, b->name, b->arity);
      ctx->stats.unify_fails++;
      return false;
    }
    debug(ctx, "  -> checking %d args of %s\n", a->arity, a->name);
    for (int i = 0; i < a->arity; i++) {
      if (!unify(ctx, a->args[i], b->args[i], env)) {
        debug(ctx, "  -> FAIL at arg %d\n", i);
        ctx->stats.unify_fails++;
        return false;
      }
    }
    debug(ctx, "  -> OK (all args)\n");
    return true;
  }

  debug(ctx, "  -> FAIL (type mismatch: %d vs %d)\n", a->type, b->type);
  ctx->stats.unify_fails++;
  return false;
}
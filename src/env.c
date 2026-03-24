#include "platform_impl.h"

term_t *lookup(env_t *env, int var_id) {
  assert(env != NULL && "Environment is NULL");

  for (int i = env->count - 1; i >= 0; i--) {
    if (env->bindings[i].var_id == var_id) {
      return env->bindings[i].value;
    }
  }
  return NULL;
}

void bind(trilog_ctx_t *ctx, env_t *env, term_t *var, term_t *value) {
  assert(ctx != NULL && "Context is NULL");
  assert(env != NULL && "Environment is NULL");
  assert(var != NULL && "Var is NULL");
  assert(var->type == VAR && "bind called on non-VAR term");
  assert(value != NULL && "Value is NULL");
  assert(ctx->bind_count < MAX_BINDINGS && "Binding table full");

  if (ctx->debug_enabled) {
    if (var->name)
      debug(ctx, "  BIND: %s(%d) = ", var->name, var->arity);
    else
      debug(ctx, "  BIND: _G%d = ", var->arity);
    debug_term_raw(ctx, value);
    debug(ctx, "\n");
  }

  ctx->bindings[ctx->bind_count++] = (binding_t){
      .var_id = var->arity,
      .name = var->name, // already interned (or NULL for internal vars)
      .value = value,
  };
  env->count = ctx->bind_count;
}

term_t *deref(env_t *env, term_t *t) {
  assert(env != NULL && "Environment is NULL");

  while (t && t->type == VAR) {
    term_t *val = lookup(env, t->arity);
    if (!val)
      break;
    t = val;
  }
  return t;
}

term_t *substitute(trilog_ctx_t *ctx, env_t *env, term_t *t) {
  assert(ctx != NULL && "Context is NULL");
  assert(env != NULL && "Environment is NULL");

  if (!t)
    return NULL;
  t = deref(env, t);

  if (t->type == CONST || t->type == VAR || t->type == STRING)
    return t;

  if (t->type != FUNC)
    return t;

  term_t *args[MAX_ARGS];
  for (int i = 0; i < t->arity; i++) {
    args[i] = substitute(ctx, env, t->args[i]);
  }
  return make_func(ctx, t->name, args, t->arity);
}

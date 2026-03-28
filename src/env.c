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
      .name = var->name, // already interned (or null for internal vars)
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

// deep-copy a term into perm pool (for assert)
static term_t *copy_to_perm(trilog_ctx_t *ctx, term_t *t) {
  if (!t)
    return NULL;
  switch (t->type) {
  case CONST:
    return make_const(ctx, t->name);
  case INT: {
    int v = 0;
    term_as_int(t, &v);
    return make_int(ctx, v);
  }
  case VAR:
    return make_var(ctx, t->name, t->arity);
  case FUNC: {
    term_t *args[MAX_ARGS];
    for (int i = 0; i < t->arity; i++) {
      args[i] = copy_to_perm(ctx, t->args[i]);
      if (!args[i])
        return NULL;
    }
    return make_func(ctx, t->name, args, t->arity);
  }
  }
  return NULL;
}

// check if a term lives in the temp pool (would be reclaimed on rollback)
static bool term_is_temp(trilog_ctx_t *ctx, term_t *t) {
  char *p = (char *)t;
  return p >= ctx->term_pool && p < ctx->term_pool + ctx->term_pool_perm;
}

// check if a term (in its current form) contains any VAR whose var_id
// is bound in [from, to) — i.e. would be affected by reclaiming that range.
bool term_refs_range(env_t *env, term_t *t, int from, int to) {
  if (!t)
    return false;
  if (t->type == VAR) {
    for (int i = from; i < to; i++) {
      if (env->bindings[i].var_id == t->arity)
        return true;
    }
    return false;
  }
  if (t->type != FUNC)
    return false;
  for (int i = 0; i < t->arity; i++) {
    if (term_refs_range(env, t->args[i], from, to))
      return true;
  }
  return false;
}

term_t *substitute(trilog_ctx_t *ctx, env_t *env, term_t *t) {
  assert(ctx != NULL && "Context is NULL");
  assert(env != NULL && "Environment is NULL");

  if (!t)
    return NULL;
  t = deref(env, t);
  if (!t)
    return NULL;

  if (t->type == CONST || t->type == VAR) {
    if (ctx->alloc_permanent && term_is_temp(ctx, t))
      return copy_to_perm(ctx, t);
    return t;
  }

  if (t->type != FUNC)
    return t;

  term_t *args[MAX_ARGS];
  bool changed = false;
  for (int i = 0; i < t->arity; i++) {
    args[i] = substitute(ctx, env, t->args[i]);
    if (!args[i])
      return NULL;
    if (args[i] != t->args[i])
      changed = true;
  }
  if (!changed) {
    if (ctx->alloc_permanent && term_is_temp(ctx, t))
      return copy_to_perm(ctx, t);
    return t;
  }
  return make_func(ctx, t->name, args, t->arity);
}

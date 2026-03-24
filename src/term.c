#include "platform_impl.h"

void *term_alloc(trilog_ctx_t *ctx, size_t size) {
  size = (size + 7) & ~7; // 8-byte align
  if (ctx->alloc_permanent) {
    int new_perm = ctx->term_pool_perm - (int)size;
    assert(new_perm >= ctx->term_pool_offset && "Term pool exhausted (perm)");
    ctx->term_pool_perm = new_perm;
    void *ptr = ctx->term_pool + new_perm;
    memset(ptr, 0, size);
    return ptr;
  }
  assert(ctx->term_pool_offset + (int)size <= ctx->term_pool_perm &&
         "Term pool exhausted");
  void *ptr = ctx->term_pool + ctx->term_pool_offset;
  memset(ptr, 0, size);
  ctx->term_pool_offset += (int)size;
  return ptr;
}

void ctx_reset_terms(trilog_ctx_t *ctx) {
  ctx->term_pool_offset = 0;
  ctx->term_pool_perm = ctx->term_pool_size;
  ctx->string_pool_offset = 0;
}

const char *intern_name(trilog_ctx_t *ctx, const char *name) {
  assert(ctx != NULL && "Context is NULL");
  assert(name != NULL && "Name is NULL");

  int len = strlen(name);

  // search for existing copy in string pool
  int i = 0;
  while (i < ctx->string_pool_offset) {
    if (strcmp(&ctx->string_pool[i], name) == 0)
      return &ctx->string_pool[i];
    i += strlen(&ctx->string_pool[i]) + 1;
  }

  assert(ctx->string_pool_offset + len + 1 <= MAX_STRING_POOL &&
         "String pool exhausted");

  char *dest = &ctx->string_pool[ctx->string_pool_offset];
  memcpy(dest, name, len + 1);
  ctx->string_pool_offset += len + 1;
  return dest;
}

term_t *make_const(trilog_ctx_t *ctx, const char *name) {
  assert(name != NULL && "Constant name cannot be NULL");
  term_t *t = term_alloc(ctx, sizeof(term_t)); // no args
  t->type = CONST;
  t->name = intern_name(ctx, name);
  return t;
}

term_t *make_var(trilog_ctx_t *ctx, const char *name, int var_id) {
  term_t *t = term_alloc(ctx, sizeof(term_t)); // no args
  t->type = VAR;
  if (name)
    t->name = intern_name(ctx, name);
  t->arity = var_id; // var_id stored in arity field for VAR terms
  return t;
}

term_t *make_func(trilog_ctx_t *ctx, const char *name, term_t **args,
                  int arity) {
  assert(name != NULL && "Functor name cannot be NULL");
  assert(arity >= 0 && "Functor arity cannot be negative");
  term_t *t = term_alloc(ctx, sizeof(term_t) + arity * sizeof(term_t *));
  t->type = FUNC;
  t->name = intern_name(ctx, name);
  t->arity = arity;
  for (int i = 0; i < arity; i++)
    t->args[i] = args[i];
  return t;
}

term_t *make_string(trilog_ctx_t *ctx, const char *str) {
  assert(ctx != NULL && "Context is NULL");
  assert(str != NULL && "String cannot be NULL");

  term_t *t = term_alloc(ctx, sizeof(term_t)); // no args
  t->type = STRING;
  t->name = intern_name(ctx, "");

  int len = strlen(str);
  assert(ctx->string_pool_offset + len + 1 <= MAX_STRING_POOL &&
         "String pool exhausted");

  t->string_data = &ctx->string_pool[ctx->string_pool_offset];
  strcpy(t->string_data, str);
  ctx->string_pool_offset += len + 1;

  return t;
}

// make_term: backward compat wrapper (used in a few places in builtins)
term_t *make_term(trilog_ctx_t *ctx, term_type type, const char *name,
                  term_t **args, int arity) {
  assert(ctx != NULL && "Context is NULL");
  assert(name != NULL && "Term name cannot be NULL");
  assert(arity >= 0 && arity <= MAX_ARGS && "Invalid arity");
  assert((type == CONST || type == VAR || type == FUNC || type == STRING) &&
         "Invalid term type");

  if (type == CONST)
    return make_const(ctx, name);
  if (type == VAR)
    return make_var(ctx, name, arity);
  if (type == FUNC)
    return make_func(ctx, name, args, arity);
  // STRING fallback
  term_t *t = term_alloc(ctx, sizeof(term_t));
  t->type = STRING;
  t->name = intern_name(ctx, "");
  return t;
}

term_t *rename_vars_mapped(trilog_ctx_t *ctx, term_t *t, var_id_map_t *map) {
  if (!t)
    return NULL;
  if (t->type == CONST || t->type == STRING)
    return t;
  if (t->type == VAR) {
    int old_id = t->arity;
    for (int i = 0; i < map->count; i++) {
      if (map->entries[i].old_id == old_id)
        return make_var(ctx, NULL, map->entries[i].new_id);
    }
    int new_id = ctx->var_counter++;
    assert(map->count < MAX_CLAUSE_VARS && "Too many variables in clause");
    map->entries[map->count].old_id = old_id;
    map->entries[map->count].new_id = new_id;
    map->count++;
    return make_var(ctx, NULL, new_id);
  }
  assert(t->type == FUNC && "Invalid term type in rename_vars_mapped");
  term_t *args[MAX_ARGS];
  for (int i = 0; i < t->arity; i++)
    args[i] = rename_vars_mapped(ctx, t->args[i], map);
  return make_func(ctx, t->name, args, t->arity);
}

term_t *rename_vars(trilog_ctx_t *ctx, term_t *t) {
  var_id_map_t map = {0};
  return rename_vars_mapped(ctx, t, &map);
}

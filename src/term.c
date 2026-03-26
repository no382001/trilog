#include "platform_impl.h"

//****
//* allocation and interning
//****

void *term_alloc(trilog_ctx_t *ctx, size_t size) {
  size = (size + 7) & ~7; // 8-byte align
  if (ctx->alloc_permanent) {
    int new_perm = ctx->term_pool_perm - (int)size;
    if (new_perm < ctx->term_pool_offset) {
      ctx_runtime_error(ctx, "term pool exhausted (perm)");
      return NULL;
    }
    ctx->term_pool_perm = new_perm;
    void *ptr = ctx->term_pool + new_perm;
    memset(ptr, 0, size);
    return ptr;
  }
  if (ctx->term_pool_offset + (int)size > ctx->term_pool_perm) {
    ctx_runtime_error(ctx, "term pool exhausted");
    return NULL;
  }
  void *ptr = ctx->term_pool + ctx->term_pool_offset;
  memset(ptr, 0, size);
  ctx->term_pool_offset += (int)size;
  if (ctx->term_pool_offset > ctx->term_pool_peak)
    ctx->term_pool_peak = ctx->term_pool_offset;
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

  if (ctx->string_pool_offset + len + 1 > MAX_STRING_POOL) {
    ctx_runtime_error(ctx, "string pool exhausted");
    return name;
  }

  char *dest = &ctx->string_pool[ctx->string_pool_offset];
  if (dest != name)
    memcpy(dest, name, len + 1);
  ctx->string_pool_offset += len + 1;
  return dest;
}

//****
//* term constructors
//****

term_t *make_const(trilog_ctx_t *ctx, const char *name) {
  assert(name != NULL && "Constant name cannot be NULL");
  term_t *t = term_alloc(ctx, sizeof(term_t)); // no args
  if (!t)
    return NULL;
  t->type = CONST;
  t->name = intern_name(ctx, name);
  return t;
}

term_t *make_var(trilog_ctx_t *ctx, const char *name, int var_id) {
  term_t *t = term_alloc(ctx, sizeof(term_t)); // no args
  if (!t)
    return NULL;
  t->type = VAR;
  if (name)
    t->name = intern_name(ctx, name);
  t->arity = var_id; // var_id stored in arity field for var terms
  return t;
}

term_t *make_func(trilog_ctx_t *ctx, const char *name, term_t **args,
                  int arity) {
  assert(name != NULL && "Functor name cannot be NULL");
  assert(arity >= 0 && "Functor arity cannot be negative");
  term_t *t = term_alloc(ctx, sizeof(term_t) + arity * sizeof(term_t *));
  if (!t)
    return NULL;
  t->type = FUNC;
  t->name = intern_name(ctx, name);
  t->arity = arity;
  for (int i = 0; i < arity; i++)
    t->args[i] = args[i];
  return t;
}

// make_term: backward compat wrapper (used in a few places in builtins)
term_t *make_term(trilog_ctx_t *ctx, term_type type, const char *name,
                  term_t **args, int arity) {
  assert(ctx != NULL && "Context is NULL");
  assert(name != NULL && "Term name cannot be NULL");
  assert(arity >= 0 && arity <= MAX_ARGS && "Invalid arity");
  assert((type == CONST || type == VAR || type == FUNC) && "Invalid term type");

  if (type == CONST)
    return make_const(ctx, name);
  if (type == VAR)
    return make_var(ctx, name, arity);
  return make_func(ctx, name, args, arity);
}

//****
//* variable renaming
//****

term_t *rename_vars_mapped(trilog_ctx_t *ctx, term_t *t, var_id_map_t *map) {
  if (!t)
    return NULL;
  if (t->type == CONST)
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

//****
//* perm pool compaction
//****

static term_t *copy_term_into_pool(trilog_ctx_t *ctx, term_t *t) {
  if (!t)
    return NULL;
  switch (t->type) {
  case CONST:
    return make_const(ctx, t->name);
  case VAR:
    return make_var(ctx, t->name, t->arity);
  case FUNC: {
    term_t *args[MAX_ARGS];
    for (int i = 0; i < t->arity; i++) {
      args[i] = copy_term_into_pool(ctx, t->args[i]);
      if (!args[i])
        return NULL;
    }
    return make_func(ctx, t->name, args, t->arity);
  }
  }
  return NULL;
}

static void patch_term_ptrs(term_t *t, int perm_start) {
  if (!t || t->type != FUNC)
    return;
  for (int i = 0; i < t->arity; i++) {
    if (t->args[i]) {
      t->args[i] = (term_t *)((char *)t->args[i] - perm_start);
      patch_term_ptrs(t->args[i], perm_start);
    }
  }
}

void compact_perm_pool(trilog_ctx_t *ctx) {
  if (ctx->term_pool_offset != 0)
    return;
  int perm_start = ctx->term_pool_perm;
  int perm_used = ctx->term_pool_size - perm_start;
  if (perm_used <= 0)
    return;
  if (perm_used * 2 > ctx->term_pool_size)
    return;

  // phase 1: copy perm region into staging area at bottom of buffer
  memcpy(ctx->term_pool, ctx->term_pool + perm_start, (size_t)perm_used);
  ctx->term_pool_offset = perm_used; // protect staging from perm allocs

  // phase 2: adjust clause-level pointers into staging area
  for (int i = 0; i < ctx->db_count; i++) {
    clause_t *c = &ctx->database[i];
    if (c->body != NULL) {
      term_t **staging_body = (term_t **)((char *)c->body - perm_start);
      for (int j = 0; j < c->body_count; j++)
        if (staging_body[j])
          staging_body[j] = (term_t *)((char *)staging_body[j] - perm_start);
      c->body = staging_body;
    }
    if (c->head)
      c->head = (term_t *)((char *)c->head - perm_start);
  }

  // phase 3: fix internal args[] pointers within staging area
  for (int i = 0; i < ctx->db_count; i++) {
    clause_t *c = &ctx->database[i];
    if (c->head)
      patch_term_ptrs(c->head, perm_start);
    if (c->body != NULL)
      for (int j = 0; j < c->body_count; j++)
        if (c->body[j])
          patch_term_ptrs(c->body[j], perm_start);
  }

  // phase 4: reset perm and rebuild from staging
  ctx->term_pool_perm = ctx->term_pool_size;
  ctx->alloc_permanent = true;
  for (int i = 0; i < ctx->db_count; i++) {
    clause_t *c = &ctx->database[i];
    if (c->head) {
      c->head = copy_term_into_pool(ctx, c->head);
      if (!c->head) {
        ctx->alloc_permanent = false;
        ctx->term_pool_offset = 0;
        return;
      }
    }
    if (c->body_count > 0) {
      term_t **nb =
          (term_t **)term_alloc(ctx, (size_t)c->body_count * sizeof(term_t *));
      if (!nb) {
        ctx->alloc_permanent = false;
        ctx->term_pool_offset = 0;
        return;
      }
      for (int j = 0; j < c->body_count; j++) {
        nb[j] = c->body ? copy_term_into_pool(ctx, c->body[j]) : NULL;
        if (!nb[j]) {
          ctx->alloc_permanent = false;
          ctx->term_pool_offset = 0;
          return;
        }
      }
      c->body = nb;
    } else {
      c->body = NULL;
    }
  }
  ctx->alloc_permanent = false;

  // phase 5: clear staging
  ctx->term_pool_offset = 0;
}

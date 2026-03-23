#include "platform_impl.h"

bool ffi_register_builtin(abclog_ctx_t *ctx, const char *name, int arity,
                          builtin_handler_t handler, void *userdata) {
  if (!ctx || !name || !handler)
    return false;

  if (ctx->custom_builtin_count >= MAX_CUSTOM_BUILTINS)
    return false;

  if (strlen(name) >= MAX_NAME)
    return false;

  custom_builtin_t *cb = &ctx->custom_builtins[ctx->custom_builtin_count];
  strncpy(cb->name, name, MAX_NAME - 1);
  cb->name[MAX_NAME - 1] = '\0';
  cb->arity = arity;
  cb->handler = handler;
  cb->userdata = userdata;

  ctx->custom_builtin_count++;
  return true;
}

void ffi_clear_builtins(abclog_ctx_t *ctx) {
  if (!ctx)
    return;
  ctx->custom_builtin_count = 0;
}

custom_builtin_t *ffi_get_builtin_userdata(abclog_ctx_t *ctx, term_t *goal) {
  if (!ctx || !goal)
    return NULL;

  goal = deref(&(env_t){0}, goal);

  const char *name = goal->name;
  int arity = (goal->type == CONST)  ? 0
              : (goal->type == FUNC) ? goal->arity
                                     : -1;

  if (arity < 0)
    return NULL;

  for (int i = 0; i < ctx->custom_builtin_count; i++) {
    custom_builtin_t *cb = &ctx->custom_builtins[i];
    if (strcmp(name, cb->name) == 0 &&
        (cb->arity == -1 || arity == cb->arity)) {
      return cb;
    }
  }

  return NULL;
}

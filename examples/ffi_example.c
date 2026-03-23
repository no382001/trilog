#include "../src/abclog.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static builtin_result_t custom_hello(abclog_ctx_t *ctx, term_t *goal, env_t *env) {
  (void)goal;
  (void)env;
  io_write_str(ctx, "Hello from custom builtin!\n");
  return BUILTIN_OK;
}

static builtin_result_t custom_double(abclog_ctx_t *ctx, term_t *goal, env_t *env) {
  // double(X, Y) - unifies Y with 2*X
  if (goal->arity != 2)
    return BUILTIN_FAIL;

  term_t *x = deref(env, goal->args[0]);

  // parse X as integer
  char *end;
  long val = strtol(x->name, &end, 10);
  if (*end != '\0')
    return BUILTIN_FAIL;

  // create result term
  char buf[32];
  snprintf(buf, sizeof(buf), "%ld", val * 2);
  term_t *result = make_const(ctx, buf);

  // unify with second argument
  return unify(ctx, goal->args[1], result, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

typedef struct {
  int counter;
  const char *prefix;
} counter_data_t;

static builtin_result_t custom_count(abclog_ctx_t *ctx, term_t *goal, env_t *env) {
  (void)goal;
  (void)env;

  // get userdata from the builtin registration
  custom_builtin_t *cb = ffi_get_builtin_userdata(ctx, goal);
  if (!cb || !cb->userdata)
    return -1;

  counter_data_t *data = (counter_data_t *)cb->userdata;
  data->counter++;

  char buf[256];
  snprintf(buf, sizeof(buf), "%s: count = %d\n", data->prefix, data->counter);
  io_write_str(ctx, buf);

  return BUILTIN_OK;
}

typedef struct {
  FILE *output_file;
} custom_io_data_t;

static void custom_write_str(abclog_ctx_t *ctx, const char *str, void *userdata) {
  (void)ctx;
  custom_io_data_t *data = (custom_io_data_t *)userdata;
  if (data && data->output_file) {
    fprintf(data->output_file, "[CUSTOM] %s", str);
  } else {
    printf("%s", str);
  }
}

int main() {
  abclog_ctx_t *ctx = malloc(ABCLOG_CTX_SIZE(TERM_POOL_BYTES));
  if (!ctx)
    return 1;
  abclog_ctx_init(ctx, TERM_POOL_BYTES);
  io_hooks_init_default(ctx);

  ffi_register_builtin(ctx, "hello", 0, custom_hello, NULL);
  ffi_register_builtin(ctx, "double", 2, custom_double, NULL);

  counter_data_t counter = {.counter = 0, .prefix = "Counter"};
  ffi_register_builtin(ctx, "count", 0, custom_count, &counter);

  ctx->input_ptr = "?- hello.";
  ctx->input_start = ctx->input_ptr;
  ctx->input_ptr += 3; // skip "?- "

  goal_stmt_t goals = {0};
  term_t *goal = parse_term(ctx);
  goals.goals[goals.count++] = goal;

  env_t env = {0};
  if (solve(ctx, &goals, &env)) {
    printf("success!\n");
  }

  ctx->input_ptr = "?- double(5, X).";
  ctx->input_start = ctx->input_ptr;
  ctx->input_ptr += 3;
  ctx_reset_terms(ctx);

  goals = (goal_stmt_t){0};
  goal = parse_term(ctx);
  goals.goals[goals.count++] = goal;

  env = (env_t){0};
  if (solve(ctx, &goals, &env)) {
    printf("X = ");
    print_term(ctx, env.bindings[0].value, &env, true);
    printf("\n");
  }

  for (int i = 0; i < 3; i++) {
    ctx->input_ptr = "?- count.";
    ctx->input_start = ctx->input_ptr;
    ctx->input_ptr += 3;
    ctx_reset_terms(ctx);

    goals = (goal_stmt_t){0};
    goal = parse_term(ctx);
    goals.goals[goals.count++] = goal;

    env = (env_t){0};
    solve(ctx, &goals, &env);
  }

  FILE *log_file = fopen("/tmp/abclog_output.log", "w");
  custom_io_data_t io_data = {.output_file = log_file};

  io_hooks_t custom_hooks = {0};
  custom_hooks.write_str = custom_write_str;
  custom_hooks.userdata = &io_data;
  io_hooks_set(ctx, &custom_hooks);

  ctx->input_ptr = "?- hello.";
  ctx->input_start = ctx->input_ptr;
  ctx->input_ptr += 3;
  ctx_reset_terms(ctx);

  goals = (goal_stmt_t){0};
  goal = parse_term(ctx);
  goals.goals[goals.count++] = goal;

  env = (env_t){0};
  solve(ctx, &goals, &env);

  fclose(log_file);

  free(ctx);
  return 0;
}

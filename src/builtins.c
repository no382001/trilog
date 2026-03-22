#include "platform_impl.h"

typedef struct {
  const char *op;
  int (*fn)(int, int);
} arith_op_t;

static int arith_add(int a, int b) { return a + b; }
static int arith_sub(int a, int b) { return a - b; }
static int arith_mul(int a, int b) { return a * b; }
static int arith_div(int a, int b) { return b ? a / b : 0; }
static int arith_mod(int a, int b) {
  if (!b)
    return 0;
  int r = a % b;
  // ISO: result has sign of divisor
  if (r != 0 && (r ^ b) < 0)
    r += b;
  return r;
}
static int arith_max(int a, int b) { return a > b ? a : b; }
static int arith_min(int a, int b) { return a < b ? a : b; }
static int arith_bor(int a, int b) { return a | b; }
static int arith_band(int a, int b) { return a & b; }
static int arith_xor(int a, int b) { return a ^ b; }
static int arith_shr(int a, int b) { return (int)((unsigned)a >> b); }
static int arith_shl(int a, int b) { return (int)((unsigned)a << b); }

static const arith_op_t arith_ops[] = {
    {"+", arith_add},    {"-", arith_sub},   {"*", arith_mul},
    {"/", arith_div},    {"mod", arith_mod}, {"//", arith_div},
    {"max", arith_max},  {"min", arith_min}, {"\\/", arith_bor},
    {"/\\", arith_band}, {"xor", arith_xor}, {">>", arith_shr},
    {"<<", arith_shl},   {NULL, NULL}};

static void throw_error(prolog_ctx_t *ctx, term_t *error_type,
                        const char *context) {
  term_t *ctx_atom = make_const(ctx, context);
  term_t *args[2] = {error_type, ctx_atom};
  term_t *err = make_func(ctx, "error", args, 2);
  ctx->thrown_ball = err;
  ctx->has_runtime_error = true;
  // set readable string (prefix-compatible with existing quad tests)
  const char *etype = error_type->name;
  if (error_type->type == FUNC)
    snprintf(ctx->runtime_error, MAX_ERROR_MSG, "%s in %s", etype, context);
  else
    snprintf(ctx->runtime_error, MAX_ERROR_MSG, "%s in %s", etype, context);
}

static void throw_instantiation_error(prolog_ctx_t *ctx, const char *context) {
  throw_error(ctx, make_const(ctx, "instantiation_error"), context);
}

static void throw_type_error(prolog_ctx_t *ctx, const char *expected,
                             term_t *got, const char *context)
    __attribute__((unused));
static void throw_type_error(prolog_ctx_t *ctx, const char *expected,
                             term_t *got, const char *context) {
  term_t *targs[2] = {make_const(ctx, expected), got};
  term_t *te = make_func(ctx, "type_error", targs, 2);
  throw_error(ctx, te, context);
}

static void throw_evaluation_error(prolog_ctx_t *ctx, const char *kind,
                                   const char *context) {
  term_t *kargs[1] = {make_const(ctx, kind)};
  term_t *ee = make_func(ctx, "evaluation_error", kargs, 1);
  throw_error(ctx, ee, context);
}

static void throw_evaluable_error(prolog_ctx_t *ctx, const char *name,
                                  int arity, const char *context) {
  char arity_buf[16];
  snprintf(arity_buf, sizeof(arity_buf), "%d", arity);
  term_t *slash_args[2] = {make_const(ctx, name), make_const(ctx, arity_buf)};
  term_t *indicator = make_func(ctx, "/", slash_args, 2);
  term_t *targs[2] = {make_const(ctx, "evaluable"), indicator};
  term_t *te = make_func(ctx, "type_error", targs, 2);
  term_t *ctx_atom = make_const(ctx, context);
  term_t *err_args[2] = {te, ctx_atom};
  ctx->thrown_ball = make_func(ctx, "error", err_args, 2);
  ctx->has_runtime_error = true;
  snprintf(ctx->runtime_error, MAX_ERROR_MSG, "type_error(evaluable, %s/%d)",
           name, arity);
}

static bool eval_arith(prolog_ctx_t *ctx, term_t *t, env_t *env, int *result,
                       const char *pred) {
  t = deref(env, t);

  if (term_as_int(t, result))
    return true;

  if (t->type == VAR) {
    throw_instantiation_error(ctx, pred);
    return false;
  }

  if (t->type == FUNC && t->arity == 1) {
    int val;
    if (!eval_arith(ctx, t->args[0], env, &val, pred))
      return false;
    if (strcmp(t->name, "-") == 0) {
      *result = -val;
      return true;
    }
    if (strcmp(t->name, "abs") == 0) {
      *result = val < 0 ? -val : val;
      return true;
    }
    if (strcmp(t->name, "\\") == 0) {
      *result = ~val;
      return true;
    }
    // Unknown unary operator
    throw_evaluable_error(ctx, t->name, 1, pred);
    return false;
  }

  if (t->type == FUNC && t->arity == 2) {
    int left, right;
    if (!eval_arith(ctx, t->args[0], env, &left, pred))
      return false;
    if (!eval_arith(ctx, t->args[1], env, &right, pred))
      return false;

    if (right == 0 &&
        (strcmp(t->name, "/") == 0 || strcmp(t->name, "//") == 0 ||
         strcmp(t->name, "mod") == 0)) {
      throw_evaluation_error(ctx, "zero_divisor", pred);
      return false;
    }

    for (const arith_op_t *op = arith_ops; op->op; op++) {
      if (strcmp(t->name, op->op) == 0) {
        bool overflow = false;
        if (strcmp(t->name, "+") == 0)
          overflow = __builtin_add_overflow(left, right, result);
        else if (strcmp(t->name, "-") == 0)
          overflow = __builtin_sub_overflow(left, right, result);
        else if (strcmp(t->name, "*") == 0)
          overflow = __builtin_mul_overflow(left, right, result);
        else
          *result = op->fn(left, right);
        if (overflow) {
          throw_evaluation_error(ctx, "int_overflow", pred);
          return false;
        }
        return true;
      }
    }
  }

  // Unknown functor or non-numeric atom: type_error(evaluable, Name/Arity)
  if (t->type == CONST || t->type == FUNC) {
    int arity = (t->type == FUNC) ? t->arity : 0;
    throw_evaluable_error(ctx, t->name, arity, pred);
  }
  return false;
}

typedef struct {
  const char *name;
  int arity; // -1 means any arity, 0 for CONST
  builtin_result_t (*handler)(prolog_ctx_t *ctx, term_t *goal, env_t *env);
} builtin_t;

static builtin_result_t builtin_true(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  (void)ctx;
  (void)goal;
  (void)env;
  return BUILTIN_OK;
}

static builtin_result_t builtin_fail(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  (void)ctx;
  (void)goal;
  (void)env;
  return BUILTIN_FAIL;
}

static builtin_result_t builtin_is(prolog_ctx_t *ctx, term_t *goal,
                                   env_t *env) {
  int result;
  if (!eval_arith(ctx, goal->args[1], env, &result, "is/2"))
    return ctx->has_runtime_error ? BUILTIN_ERROR : BUILTIN_FAIL;
  char buf[32];
  snprintf(buf, sizeof(buf), "%d", result);
  term_t *result_term = make_const(ctx, buf);
  return unify(ctx, goal->args[0], result_term, env) ? BUILTIN_OK
                                                     : BUILTIN_FAIL;
}

static builtin_result_t builtin_unify(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  return unify(ctx, goal->args[0], goal->args[1], env) ? BUILTIN_OK
                                                       : BUILTIN_FAIL;
}

static builtin_result_t builtin_not_unify(prolog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  int old_count = env->count;
  bool unified = unify(ctx, goal->args[0], goal->args[1], env);
  env->count = ctx->bind_count = old_count;
  return unified ? -1 : 1;
}

static bool terms_identical(term_t *a, term_t *b, env_t *env) {
  a = deref(env, a);
  b = deref(env, b);
  if (a == b)
    return true;
  if (a->type != b->type)
    return false;
  if (a->type == VAR)
    return a->arity == b->arity;
  if (a->type == STRING)
    return strcmp(a->string_data, b->string_data) == 0;
  if (a->name != b->name)
    return false;
  if (a->arity != b->arity)
    return false;
  for (int i = 0; i < a->arity; i++) {
    if (!terms_identical(a->args[i], b->args[i], env))
      return false;
  }
  return true;
}

static builtin_result_t builtin_struct_eq(prolog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  (void)ctx;
  return terms_identical(goal->args[0], goal->args[1], env) ? BUILTIN_OK
                                                            : BUILTIN_FAIL;
}

static builtin_result_t builtin_struct_neq(prolog_ctx_t *ctx, term_t *goal,
                                           env_t *env) {
  (void)ctx;
  return terms_identical(goal->args[0], goal->args[1], env) ? BUILTIN_FAIL
                                                            : BUILTIN_OK;
}

// ISO standard order: var < number < atom < string < compound
// within same type: var by id, number by value, atom/string lexicographic,
// compound by arity then functor then args left-to-right
static int term_order(term_t *a, term_t *b, env_t *env) {
  a = deref(env, a);
  b = deref(env, b);
  if (a == b)
    return 0;

  // type ordering ranks
  static const int rank[] = {
      [CONST] = 2, // will split into number(1) vs atom(2) below
      [VAR] = 0,
      [FUNC] = 4,
      [STRING] = 3,
  };

  int ra = rank[a->type], rb = rank[b->type];

  // split CONST into number vs atom
  int ia, ib;
  bool a_num = (a->type == CONST && term_as_int(a, &ia));
  bool b_num = (b->type == CONST && term_as_int(b, &ib));
  if (a_num)
    ra = 1;
  if (b_num)
    rb = 1;

  if (ra != rb)
    return ra < rb ? -1 : 1;

  // same type category
  if (a->type == VAR)
    return a->arity < b->arity ? -1 : (a->arity > b->arity ? 1 : 0);

  if (a_num && b_num)
    return ia < ib ? -1 : (ia > ib ? 1 : 0);

  if (a->type == STRING)
    return strcmp(a->string_data, b->string_data);

  if (a->type == CONST)
    return a->name == b->name ? 0 : strcmp(a->name, b->name);

  // compound: arity first, then functor, then args
  if (a->arity != b->arity)
    return a->arity < b->arity ? -1 : 1;
  if (a->name != b->name) {
    int cmp = strcmp(a->name, b->name);
    if (cmp != 0)
      return cmp;
  }
  for (int i = 0; i < a->arity; i++) {
    int cmp = term_order(a->args[i], b->args[i], env);
    if (cmp != 0)
      return cmp;
  }
  return 0;
}

static builtin_result_t builtin_compare(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  int cmp = term_order(goal->args[1], goal->args[2], env);
  const char *ord = cmp < 0 ? "<" : (cmp > 0 ? ">" : "=");
  return unify(ctx, goal->args[0], make_const(ctx, ord), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_lt(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  return term_order(goal->args[0], goal->args[1], env) < 0 ? BUILTIN_OK
                                                           : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_gt(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  return term_order(goal->args[0], goal->args[1], env) > 0 ? BUILTIN_OK
                                                           : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_le(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  return term_order(goal->args[0], goal->args[1], env) <= 0 ? BUILTIN_OK
                                                            : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_ge(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  return term_order(goal->args[0], goal->args[1], env) >= 0 ? BUILTIN_OK
                                                            : BUILTIN_FAIL;
}

#define ARITH_CMP_BUILTIN(name, op, pred)                                      \
  static builtin_result_t name(prolog_ctx_t *ctx, term_t *goal, env_t *env) {  \
    int left, right;                                                           \
    if (!eval_arith(ctx, goal->args[0], env, &left, pred))                     \
      return ctx->has_runtime_error ? BUILTIN_ERROR : BUILTIN_NOT_HANDLED;     \
    if (!eval_arith(ctx, goal->args[1], env, &right, pred))                    \
      return ctx->has_runtime_error ? BUILTIN_ERROR : BUILTIN_NOT_HANDLED;     \
    return left op right ? BUILTIN_OK : BUILTIN_FAIL;                          \
  }

ARITH_CMP_BUILTIN(builtin_lt, <, "</2")
ARITH_CMP_BUILTIN(builtin_gt, >, ">/2")
ARITH_CMP_BUILTIN(builtin_le, <=, "=</2")
ARITH_CMP_BUILTIN(builtin_ge, >=, ">=/2")
ARITH_CMP_BUILTIN(builtin_arith_eq, ==, "=:=/2")
ARITH_CMP_BUILTIN(builtin_arith_ne, !=, "=\\=/2")

#undef ARITH_CMP_BUILTIN

static builtin_result_t builtin_cut(prolog_ctx_t *ctx, term_t *goal,
                                    env_t *env) {
  (void)ctx;
  (void)goal;
  (void)env;
  return BUILTIN_CUT;
}

static builtin_result_t builtin_stats(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  (void)goal;
  (void)env;
  io_writef(ctx, "terms: %d allocated, %d peak, %d bytes used\n",
            ctx->stats.terms_allocated, ctx->stats.terms_peak,
            ctx->term_pool_offset);
  io_writef(ctx, "unify: %d calls, %d fails\n", ctx->stats.unify_calls,
            ctx->stats.unify_fails);
  io_writef(ctx, "solve: %d son calls, %d backtracks\n", ctx->stats.son_calls,
            ctx->stats.backtracks);
  io_writef(ctx, "string pool: %d / %d bytes\n", ctx->string_pool_offset,
            MAX_STRING_POOL);
  return BUILTIN_OK;
}

typedef struct {
  prolog_ctx_t *ctx;
  term_t *template;
  term_t *list;
  int count;
} findall_state_t;

static bool findall_callback(prolog_ctx_t *ctx, env_t *env, void *userdata,
                             bool has_more) {
  (void)has_more;
  findall_state_t *state = userdata;
  term_t *val = substitute(ctx, env, state->template);
  term_t *args[2] = {val, state->list};
  state->list = make_func(ctx, ".", args, 2);
  state->count++;
  ctx->term_pool_floor = ctx->term_pool_offset;
  return true;
}

static term_t *reverse_list(prolog_ctx_t *ctx, term_t *list) {
  term_t *result = make_const(ctx, "[]");
  while (is_cons(list)) {
    term_t *args[2] = {list->args[0], result};
    result = make_func(ctx, ".", args, 2);
    list = list->args[1];
  }
  return result;
}

static int collect_solutions(prolog_ctx_t *ctx, term_t *goal, env_t *env,
                             bool fail_on_empty) {
  term_t *template = deref(env, goal->args[0]);
  term_t *query = deref(env, goal->args[1]);
  term_t *result_var = goal->args[2];

  // strip existential quantifier: _^Goal -> Goal
  while (query->type == FUNC && strcmp(query->name, "^") == 0 &&
         query->arity == 2)
    query = deref(env, query->args[1]);

  // goal must be instantiated and callable
  if (query->type == VAR) {
    throw_instantiation_error(ctx, "findall/3");
    return BUILTIN_ERROR;
  }
  if (query->type != FUNC && query->type != CONST) {
    throw_type_error(ctx, "callable", query, "findall/3");
    return BUILTIN_ERROR;
  }

  var_id_map_t _map = {0};
  template = rename_vars_mapped(ctx, substitute(ctx, env, template), &_map);
  query = rename_vars_mapped(ctx, substitute(ctx, env, query), &_map);

  goal_stmt_t goals = goals_alloc(ctx, 1);
  goals.goals[goals.count++] = query;

  findall_state_t state = {.ctx = ctx,
                           .template = template,
                           .list = make_const(ctx, "[]"),
                           .count = 0};

  int bind_save = ctx->bind_count;
  int floor_save = ctx->term_pool_floor;
  int bfloor_save = ctx->bind_floor;
  ctx->bind_floor = MAX_BINDINGS; // disable LCO inside findall
  env_t query_env = {.bindings = ctx->bindings, .count = ctx->bind_count};
  solve_all(ctx, &goals, &query_env, findall_callback, &state);
  ctx->bind_count = bind_save;
  ctx->term_pool_floor = floor_save;
  ctx->bind_floor = bfloor_save;

  if (fail_on_empty && state.count == 0)
    return BUILTIN_FAIL;

  term_t *result = reverse_list(ctx, state.list);
  return unify(ctx, result_var, result, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_findall(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  return collect_solutions(ctx, goal, env, false);
}

static builtin_result_t builtin_bagof(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  return collect_solutions(ctx, goal, env, true);
}

static int list_to_array(env_t *env, term_t *list, term_t **arr, int max);
static term_t *array_to_list(prolog_ctx_t *ctx, term_t **arr, int n);

static builtin_result_t builtin_setof(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  // collect like bagof, then sort+dedup the result
  term_t *template = deref(env, goal->args[0]);
  term_t *query = deref(env, goal->args[1]);
  term_t *result_var = goal->args[2];

  while (query->type == FUNC && strcmp(query->name, "^") == 0 &&
         query->arity == 2)
    query = deref(env, query->args[1]);

  if (query->type == VAR) {
    throw_instantiation_error(ctx, "setof/3");
    return BUILTIN_ERROR;
  }
  if (query->type != FUNC && query->type != CONST) {
    throw_type_error(ctx, "callable", query, "setof/3");
    return BUILTIN_ERROR;
  }

  var_id_map_t _map = {0};
  template = rename_vars_mapped(ctx, substitute(ctx, env, template), &_map);
  query = rename_vars_mapped(ctx, substitute(ctx, env, query), &_map);

  goal_stmt_t goals = goals_alloc(ctx, 1);
  goals.goals[goals.count++] = query;

  findall_state_t state = {.ctx = ctx,
                           .template = template,
                           .list = make_const(ctx, "[]"),
                           .count = 0};

  int bind_save = ctx->bind_count;
  int floor_save = ctx->term_pool_floor;
  int bfloor_save = ctx->bind_floor;
  ctx->bind_floor = MAX_BINDINGS; // disable LCO inside setof
  env_t query_env = {.bindings = ctx->bindings, .count = ctx->bind_count};
  solve_all(ctx, &goals, &query_env, findall_callback, &state);
  ctx->bind_count = bind_save;
  ctx->term_pool_floor = floor_save;
  ctx->bind_floor = bfloor_save;

  if (state.count == 0)
    return BUILTIN_FAIL;

  // sort and deduplicate
  term_t *elems[MAX_LIST_LIT];
  int n =
      list_to_array(env, reverse_list(ctx, state.list), elems, MAX_LIST_LIT);
  if (n < 0)
    return BUILTIN_FAIL;
  for (int i = 1; i < n; i++) {
    term_t *key = elems[i];
    int j = i - 1;
    while (j >= 0 && term_order(elems[j], key, env) > 0) {
      elems[j + 1] = elems[j];
      j--;
    }
    elems[j + 1] = key;
  }
  int out = 0;
  for (int i = 0; i < n; i++) {
    if (i == 0 || term_order(elems[i], elems[out - 1], env) != 0)
      elems[out++] = elems[i];
  }
  return unify(ctx, result_var, array_to_list(ctx, elems, out), env)
             ? BUILTIN_OK
             : BUILTIN_FAIL;
}

static bool not_found_callback(prolog_ctx_t *ctx, env_t *env, void *userdata,
                               bool has_more) {
  (void)ctx;
  (void)env;
  (void)has_more;
  *(bool *)userdata = true;
  return false;
}

static builtin_result_t builtin_throw(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  term_t *ball = deref(env, goal->args[0]);
  ctx->thrown_ball = ball;
  ctx->has_runtime_error = true;
  // extract readable string from error(Type, _) if ISO form
  if (ball->type == FUNC && strcmp(ball->name, "error") == 0 &&
      ball->arity == 2) {
    snprintf(ctx->runtime_error, MAX_ERROR_MSG, "%s", ball->args[0]->name);
  } else {
    snprintf(ctx->runtime_error, MAX_ERROR_MSG, "unhandled exception");
  }
  return BUILTIN_ERROR;
}

static bool is_integer_str(const char *s);

static bool check_callable(prolog_ctx_t *ctx, term_t *t, const char *pred) {
  if (t->type == VAR) {
    throw_instantiation_error(ctx, pred);
    return false;
  }
  if (t->type == CONST && is_integer_str(t->name)) {
    throw_type_error(ctx, "callable", t, pred);
    return false;
  }
  return true;
}

static builtin_result_t builtin_once(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  term_t *inner = deref(env, goal->args[0]);
  if (!check_callable(ctx, inner, "once/1"))
    return BUILTIN_ERROR;
  goal_stmt_t goals = goals_alloc(ctx, 1);
  goals.goals[goals.count++] = inner;
  if (solve(ctx, &goals, env))
    return BUILTIN_OK;
  return ctx->has_runtime_error ? BUILTIN_ERROR : BUILTIN_FAIL;
}

static builtin_result_t builtin_not(prolog_ctx_t *ctx, term_t *goal,
                                    env_t *env) {
  term_t *inner = deref(env, goal->args[0]);
  if (!check_callable(ctx, inner, "\\+/1"))
    return BUILTIN_ERROR;
  goal_stmt_t goals = goals_alloc(ctx, 1);
  goals.goals[goals.count++] = inner;
  int env_mark = env->count;
  bool found = false;
  solve_all(ctx, &goals, env, not_found_callback, &found);
  env->count = ctx->bind_count = env_mark;
  if (ctx->has_runtime_error)
    return BUILTIN_ERROR;
  return found ? BUILTIN_FAIL : BUILTIN_OK;
}

static bool is_integer_str(const char *s) {
  if (*s == '-')
    s++;
  if (!*s)
    return false;
  while (*s)
    if (!isdigit((unsigned char)*s++))
      return false;
  return true;
}

static builtin_result_t builtin_var(prolog_ctx_t *ctx, term_t *goal,
                                    env_t *env) {
  (void)ctx;
  return deref(env, goal->args[0])->type == VAR ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_nonvar(prolog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  (void)ctx;
  return deref(env, goal->args[0])->type != VAR ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_atom(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST && !is_integer_str(t->name)) ? BUILTIN_OK
                                                        : BUILTIN_FAIL;
}

static builtin_result_t builtin_integer(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST && is_integer_str(t->name)) ? BUILTIN_OK
                                                       : BUILTIN_FAIL;
}

static builtin_result_t builtin_is_list(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  while (is_cons(t))
    t = deref(env, t->args[1]);
  return is_nil(t) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_nl(prolog_ctx_t *ctx, term_t *goal,
                                   env_t *env) {
  (void)goal;
  (void)env;
  io_write_str(ctx, "\n");
  return BUILTIN_OK;
}

static builtin_result_t builtin_flush_output(prolog_ctx_t *ctx, term_t *goal,
                                             env_t *env) {
  (void)goal;
  (void)env;
  (void)ctx;
  fflush(stdout);
  return BUILTIN_OK;
}

static builtin_result_t builtin_clear(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  (void)goal;
  (void)env;
  io_write_str(ctx, "\033[2J\033[H");
  return BUILTIN_OK;
}

static builtin_result_t builtin_write(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  io_write_term(ctx, deref(env, goal->args[0]), env);
  return BUILTIN_OK;
}

static builtin_result_t builtin_writeln(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  io_write_term(ctx, deref(env, goal->args[0]), env);
  io_write_str(ctx, "\n");
  return BUILTIN_OK;
}

static builtin_result_t builtin_writeq(prolog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  io_write_term_quoted(ctx, deref(env, goal->args[0]), env);
  return BUILTIN_OK;
}

static const char *resolve_filename(prolog_ctx_t *ctx, term_t *arg, char *buf,
                                    size_t bufsz) {
  const char *filename = NULL;
  if (arg->type == STRING)
    filename = arg->string_data;
  else if (arg->type == CONST)
    filename = arg->name;
  else
    return NULL;

  if (filename[0] != '/' && ctx->load_dir[0] != '\0') {
    snprintf(buf, bufsz, "%s/%s", ctx->load_dir, filename);
    return buf;
  }
  return filename;
}

// consult/1: load file as independent unit, tracked for make/0
static builtin_result_t builtin_consult(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  char resolved[MAX_FILE_PATH];
  const char *filename = resolve_filename(ctx, deref(env, goal->args[0]),
                                          resolved, sizeof(resolved));
  if (!filename)
    return BUILTIN_FAIL;
  return prolog_load_file(ctx, filename) ? BUILTIN_OK : BUILTIN_FAIL;
}

// include/1: textual inclusion — only valid as a file directive,
// clauses are owned by the including file, not tracked for make/0
static builtin_result_t builtin_include(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  if (ctx->include_depth == 0) {
    io_writef(ctx, "Error: include/1 is only valid as a file directive\n");
    return BUILTIN_FAIL;
  }
  char resolved[MAX_FILE_PATH];
  const char *filename = resolve_filename(ctx, deref(env, goal->args[0]),
                                          resolved, sizeof(resolved));
  if (!filename)
    return BUILTIN_FAIL;
  // include_depth >= 1 here, so prolog_load_file won't track this file for
  // make/0
  return prolog_load_file(ctx, filename) ? BUILTIN_OK : BUILTIN_FAIL;
}

static const char *term_atom_str(const term_t *t) {
  if (!t)
    return NULL;
  if (t->type == STRING)
    return t->string_data;
  if (t->type == CONST)
    return t->name;
  return NULL;
}

static builtin_result_t builtin_compound(prolog_ctx_t *ctx, term_t *goal,
                                         env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == FUNC) ? BUILTIN_OK : BUILTIN_FAIL;
}
static builtin_result_t builtin_callable(prolog_ctx_t *ctx, term_t *goal,
                                         env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST || t->type == FUNC) ? BUILTIN_OK : BUILTIN_FAIL;
}
static builtin_result_t builtin_number(prolog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST && is_integer_str(t->name)) ? BUILTIN_OK
                                                       : BUILTIN_FAIL;
}
static builtin_result_t builtin_atomic(prolog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST || t->type == STRING) ? BUILTIN_OK : BUILTIN_FAIL;
}
static builtin_result_t builtin_string(prolog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == STRING) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_atom_length(prolog_ctx_t *ctx, term_t *goal,
                                            env_t *env) {
  term_t *a = deref(env, goal->args[0]);
  if (a->type == VAR) {
    throw_instantiation_error(ctx, "atom_length/2");
    return BUILTIN_ERROR;
  }
  const char *s = term_atom_str(a);
  if (!s) {
    throw_type_error(ctx, "atom", a, "atom_length/2");
    return BUILTIN_ERROR;
  }
  char buf[16];
  snprintf(buf, sizeof(buf), "%d", (int)strlen(s));
  return unify(ctx, goal->args[1], make_const(ctx, buf), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static builtin_result_t builtin_atom_concat(prolog_ctx_t *ctx, term_t *goal,
                                            env_t *env) {
  term_t *a = deref(env, goal->args[0]);
  term_t *b = deref(env, goal->args[1]);
  term_t *c = deref(env, goal->args[2]);
  const char *sa = term_atom_str(a);
  const char *sb = term_atom_str(b);
  const char *sc = term_atom_str(c);

  if (sa && sb) {
    char buf[MAX_NAME];
    int r = snprintf(buf, sizeof(buf), "%s%s", sa, sb);
    if (r < 0 || r >= (int)sizeof(buf))
      return BUILTIN_FAIL;
    return unify(ctx, goal->args[2], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  if (sc && sa && b->type == VAR) {
    size_t la = strlen(sa), lc = strlen(sc);
    if (lc < la || strncmp(sc, sa, la) != 0)
      return BUILTIN_FAIL;
    return unify(ctx, goal->args[1], make_const(ctx, sc + la), env)
               ? BUILTIN_OK
               : BUILTIN_FAIL;
  }
  if (sc && sb && a->type == VAR) {
    size_t lb = strlen(sb), lc = strlen(sc);
    if (lc < lb || strcmp(sc + lc - lb, sb) != 0)
      return BUILTIN_FAIL;
    char buf[MAX_NAME];
    size_t la = lc - lb;
    if (la >= MAX_NAME)
      return BUILTIN_FAIL;
    strncpy(buf, sc, la);
    buf[la] = '\0';
    return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  return BUILTIN_FAIL;
}

// sub_atom(+Atom, ?Before, ?Length, ?After, ?SubAtom)
// generates or verifies substrings; backtracks over all solutions
static builtin_result_t builtin_sub_atom(prolog_ctx_t *ctx, term_t *goal,
                                         env_t *env) {
  term_t *atom_t = deref(env, goal->args[0]);
  if (atom_t->type == VAR) {
    throw_instantiation_error(ctx, "sub_atom/5");
    return BUILTIN_ERROR;
  }
  const char *s = term_atom_str(atom_t);
  if (!s) {
    throw_type_error(ctx, "atom", atom_t, "sub_atom/5");
    return BUILTIN_ERROR;
  }
  int len = (int)strlen(s);

  // try every (before, sub_len) combination — use choice point via solve_all
  // but since we're a C builtin we enumerate and assert each solution
  // via a small helper: just try them all and return the first matching one.
  // For full backtracking, a proper approach would need multi-solution support
  // in builtins; here we collect all matches and build a disjunction.
  // Simple approach: iterate and unify greedily (returns first match only).
  // Full backtracking over sub_atom requires the caller to use findall.

  term_t *bef_t = deref(env, goal->args[1]);
  term_t *lng_t = deref(env, goal->args[2]);
  term_t *sub_t = deref(env, goal->args[4]);

  int bef_fixed = -1, lng_fixed = -1;
  if (term_as_int(bef_t, &bef_fixed) && bef_fixed < 0)
    return BUILTIN_FAIL;
  if (term_as_int(lng_t, &lng_fixed) && lng_fixed < 0)
    return BUILTIN_FAIL;

  // When Sub is bound, avoid interning every possible substring
  const char *sub_str = NULL;
  if (sub_t->type != VAR)
    sub_str = term_atom_str(sub_t);
  if (sub_str) {
    int sub_len = (int)strlen(sub_str);
    if (lng_fixed >= 0 && lng_fixed != sub_len)
      return BUILTIN_FAIL;
    for (int b = (bef_fixed >= 0 ? bef_fixed : 0);
         b <= (bef_fixed >= 0 ? bef_fixed : len - sub_len); b++) {
      if (b + sub_len > len)
        break;
      if (strncmp(s + b, sub_str, (size_t)sub_len) != 0)
        continue;
      int a = len - b - sub_len;
      char num[16];
      int env_mark = env->count;
      snprintf(num, sizeof(num), "%d", b);
      term_t *bef_v = make_const(ctx, num);
      snprintf(num, sizeof(num), "%d", sub_len);
      term_t *lng_v = make_const(ctx, num);
      snprintf(num, sizeof(num), "%d", a);
      term_t *aft_v = make_const(ctx, num);
      if (unify(ctx, goal->args[1], bef_v, env) &&
          unify(ctx, goal->args[2], lng_v, env) &&
          unify(ctx, goal->args[3], aft_v, env))
        return BUILTIN_OK;
      env->count = ctx->bind_count = env_mark;
    }
    return BUILTIN_FAIL;
  }

  for (int b = (bef_fixed >= 0 ? bef_fixed : 0);
       b <= (bef_fixed >= 0 ? bef_fixed : len); b++) {
    for (int l = (lng_fixed >= 0 ? lng_fixed : 0);
         l <= (lng_fixed >= 0 ? lng_fixed : len - b); l++) {
      if (b + l > len)
        break;
      int a = len - b - l;
      char sub_buf[MAX_NAME];
      if (l >= MAX_NAME)
        continue;
      strncpy(sub_buf, s + b, (size_t)l);
      sub_buf[l] = '\0';

      char num[16];
      int env_mark = env->count;
      snprintf(num, sizeof(num), "%d", b);
      term_t *bef_v = make_const(ctx, num);
      snprintf(num, sizeof(num), "%d", l);
      term_t *lng_v = make_const(ctx, num);
      snprintf(num, sizeof(num), "%d", a);
      term_t *aft_v = make_const(ctx, num);
      term_t *sub_v = make_const(ctx, sub_buf);

      if (unify(ctx, goal->args[1], bef_v, env) &&
          unify(ctx, goal->args[2], lng_v, env) &&
          unify(ctx, goal->args[3], aft_v, env) &&
          unify(ctx, goal->args[4], sub_v, env))
        return BUILTIN_OK;
      env->count = ctx->bind_count = env_mark;
    }
    if (bef_fixed >= 0 && lng_fixed >= 0)
      break;
  }
  return BUILTIN_FAIL;
}

static term_t *str_to_char_list(prolog_ctx_t *ctx, const char *s) {
  term_t *list = make_const(ctx, "[]");
  for (int i = (int)strlen(s) - 1; i >= 0; i--) {
    char ch[2] = {s[i], '\0'};
    term_t *args[2] = {make_const(ctx, ch), list};
    list = make_func(ctx, ".", args, 2);
  }
  return list;
}

static term_t *str_to_code_list(prolog_ctx_t *ctx, const char *s) {
  term_t *list = make_const(ctx, "[]");
  for (int i = (int)strlen(s) - 1; i >= 0; i--) {
    char code[8];
    snprintf(code, sizeof(code), "%d", (unsigned char)s[i]);
    term_t *args[2] = {make_const(ctx, code), list};
    list = make_func(ctx, ".", args, 2);
  }
  return list;
}

static bool char_list_to_str(env_t *env, term_t *list, char *buf, int max) {
  int n = 0;
  while (is_cons(list)) {
    const char *cs = term_atom_str(deref(env, list->args[0]));
    if (!cs || cs[1] != '\0' || n >= max - 1)
      return false;
    buf[n++] = cs[0];
    list = deref(env, list->args[1]);
  }
  if (!is_nil(list))
    return false;
  buf[n] = '\0';
  return true;
}

static bool code_list_to_str(env_t *env, term_t *list, char *buf, int max) {
  int n = 0;
  while (is_cons(list)) {
    int c;
    if (!term_as_int(deref(env, list->args[0]), &c) || c < 0 || c > 255 ||
        n >= max - 1)
      return false;
    buf[n++] = (char)c;
    list = deref(env, list->args[1]);
  }
  if (!is_nil(list))
    return false;
  buf[n] = '\0';
  return true;
}

static builtin_result_t builtin_atom_chars(prolog_ctx_t *ctx, term_t *goal,
                                           env_t *env) {
  term_t *atom = deref(env, goal->args[0]);
  term_t *list = deref(env, goal->args[1]);
  if (atom->type != VAR) {
    const char *s = term_atom_str(atom);
    if (!s) {
      throw_type_error(ctx, "atom", atom, "atom_chars/2");
      return BUILTIN_ERROR;
    }
    return unify(ctx, goal->args[1], str_to_char_list(ctx, s), env)
               ? BUILTIN_OK
               : BUILTIN_FAIL;
  }
  if (list->type == VAR) {
    throw_instantiation_error(ctx, "atom_chars/2");
    return BUILTIN_ERROR;
  }
  char buf[MAX_NAME] = {0};
  if (!char_list_to_str(env, list, buf, MAX_NAME))
    return BUILTIN_FAIL;
  return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static builtin_result_t builtin_atom_codes(prolog_ctx_t *ctx, term_t *goal,
                                           env_t *env) {
  term_t *atom = deref(env, goal->args[0]);
  term_t *list = deref(env, goal->args[1]);
  if (atom->type != VAR) {
    const char *s = term_atom_str(atom);
    if (!s) {
      throw_type_error(ctx, "atom", atom, "atom_codes/2");
      return BUILTIN_ERROR;
    }
    return unify(ctx, goal->args[1], str_to_code_list(ctx, s), env)
               ? BUILTIN_OK
               : BUILTIN_FAIL;
  }
  if (list->type == VAR) {
    throw_instantiation_error(ctx, "atom_codes/2");
    return BUILTIN_ERROR;
  }
  char buf[MAX_NAME] = {0};
  if (!code_list_to_str(env, list, buf, MAX_NAME))
    return BUILTIN_FAIL;
  return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static builtin_result_t builtin_char_code(prolog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  term_t *ch = deref(env, goal->args[0]);
  term_t *code = deref(env, goal->args[1]);
  if (ch->type == VAR && code->type == VAR) {
    throw_instantiation_error(ctx, "char_code/2");
    return BUILTIN_ERROR;
  }
  if (ch->type != VAR) {
    const char *s = term_atom_str(ch);
    if (!s || s[1] != '\0') {
      throw_type_error(ctx, "character", ch, "char_code/2");
      return BUILTIN_ERROR;
    }
    char buf[8];
    snprintf(buf, sizeof(buf), "%d", (unsigned char)s[0]);
    return unify(ctx, goal->args[1], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  int c;
  if (!term_as_int(code, &c)) {
    throw_type_error(ctx, "integer", code, "char_code/2");
    return BUILTIN_ERROR;
  }
  if (c < 0 || c > 255)
    return BUILTIN_FAIL;
  char buf[2] = {(char)c, '\0'};
  return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static builtin_result_t builtin_atom_number(prolog_ctx_t *ctx, term_t *goal,
                                            env_t *env) {
  term_t *atom = deref(env, goal->args[0]);
  term_t *num = deref(env, goal->args[1]);
  if (atom->type != VAR) {
    const char *s = term_atom_str(atom);
    if (!s || !is_integer_str(s))
      return BUILTIN_FAIL;
    return unify(ctx, goal->args[1], make_const(ctx, s), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
  }
  if (num->type != VAR) {
    if (!is_integer_str(num->name))
      return BUILTIN_FAIL;
    return unify(ctx, goal->args[0], make_const(ctx, num->name), env)
               ? BUILTIN_OK
               : BUILTIN_FAIL;
  }
  return BUILTIN_FAIL;
}

static builtin_result_t builtin_number_codes(prolog_ctx_t *ctx, term_t *goal,
                                             env_t *env) {
  term_t *num = deref(env, goal->args[0]);
  term_t *list = deref(env, goal->args[1]);
  if (num->type != VAR) {
    if (!is_integer_str(num->name)) {
      throw_type_error(ctx, "number", num, "number_codes/2");
      return BUILTIN_ERROR;
    }
    return unify(ctx, goal->args[1], str_to_code_list(ctx, num->name), env)
               ? BUILTIN_OK
               : BUILTIN_FAIL;
  }
  if (list->type == VAR) {
    throw_instantiation_error(ctx, "number_codes/2");
    return BUILTIN_ERROR;
  }
  char buf[MAX_NAME] = {0};
  if (!code_list_to_str(env, list, buf, MAX_NAME) || !is_integer_str(buf))
    return BUILTIN_FAIL;
  return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static builtin_result_t builtin_number_chars(prolog_ctx_t *ctx, term_t *goal,
                                             env_t *env) {
  term_t *num = deref(env, goal->args[0]);
  term_t *list = deref(env, goal->args[1]);
  if (num->type != VAR) {
    if (!is_integer_str(num->name)) {
      throw_type_error(ctx, "number", num, "number_chars/2");
      return BUILTIN_ERROR;
    }
    return unify(ctx, goal->args[1], str_to_char_list(ctx, num->name), env)
               ? BUILTIN_OK
               : BUILTIN_FAIL;
  }
  if (list->type == VAR) {
    throw_instantiation_error(ctx, "number_chars/2");
    return BUILTIN_ERROR;
  }
  char buf[MAX_NAME] = {0};
  if (!char_list_to_str(env, list, buf, MAX_NAME) || !is_integer_str(buf))
    return BUILTIN_FAIL;
  return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static builtin_result_t builtin_functor(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  term_t *term = deref(env, goal->args[0]);
  term_t *name = goal->args[1];
  term_t *arity = goal->args[2];
  term_t *n = deref(env, name);
  term_t *a = deref(env, arity);
  if (term->type == VAR && n->type == VAR) {
    throw_instantiation_error(ctx, "functor/3");
    return BUILTIN_ERROR;
  }
  if (term->type != VAR) {
    const char *fname;
    int ar;
    if (term->type == CONST || term->type == STRING) {
      fname = term_atom_str(term);
      ar = 0;
    } else if (term->type == FUNC) {
      fname = term->name;
      ar = term->arity;
    } else {
      return BUILTIN_FAIL;
    }
    char ar_buf[8];
    snprintf(ar_buf, sizeof(ar_buf), "%d", ar);
    return (unify(ctx, name, make_const(ctx, fname), env) &&
            unify(ctx, arity, make_const(ctx, ar_buf), env))
               ? 1
               : -1;
  }
  // compose: functor(X, Name, Arity)
  if (n->type == VAR || a->type == VAR) {
    throw_instantiation_error(ctx, "functor/3");
    return BUILTIN_ERROR;
  }
  int ar;
  if (!term_as_int(a, &ar)) {
    throw_type_error(ctx, "integer", a, "functor/3");
    return BUILTIN_ERROR;
  }
  if (ar < 0 || ar > MAX_ARGS) {
    throw_type_error(ctx, "integer", a, "functor/3");
    return BUILTIN_ERROR;
  }
  // name must be atom when arity > 0; atomic when arity == 0
  if (ar > 0 && n->type != CONST) {
    throw_type_error(ctx, "atom", n, "functor/3");
    return BUILTIN_ERROR;
  }
  if (n->type != CONST && n->type != STRING) {
    throw_type_error(ctx, "atomic", n, "functor/3");
    return BUILTIN_ERROR;
  }
  const char *fname = term_atom_str(n);
  if (!fname)
    return BUILTIN_FAIL;
  term_t *t;
  if (ar == 0) {
    t = make_const(ctx, fname);
  } else {
    term_t *args[MAX_ARGS];
    for (int i = 0; i < ar; i++) {
      args[i] = make_var(ctx, NULL, ctx->var_counter++);
    }
    t = make_func(ctx, fname, args, ar);
  }
  return unify(ctx, goal->args[0], t, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_arg(prolog_ctx_t *ctx, term_t *goal,
                                    env_t *env) {
  term_t *n = deref(env, goal->args[0]);
  term_t *term = deref(env, goal->args[1]);
  if (n->type == VAR) {
    throw_instantiation_error(ctx, "arg/3");
    return BUILTIN_ERROR;
  }
  if (term->type == VAR) {
    throw_instantiation_error(ctx, "arg/3");
    return BUILTIN_ERROR;
  }
  if (term->type != FUNC) {
    throw_type_error(ctx, "compound", term, "arg/3");
    return BUILTIN_ERROR;
  }
  int idx;
  if (!term_as_int(n, &idx)) {
    throw_type_error(ctx, "integer", n, "arg/3");
    return BUILTIN_ERROR;
  }
  if (idx < 1 || idx > term->arity)
    return BUILTIN_FAIL;
  return unify(ctx, goal->args[2], term->args[idx - 1], env) ? BUILTIN_OK
                                                             : BUILTIN_FAIL;
}

static builtin_result_t builtin_univ(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  term_t *term = deref(env, goal->args[0]);
  term_t *list = deref(env, goal->args[1]);
  if (term->type != VAR) {
    term_t *result;
    if (term->type == CONST || term->type == STRING) {
      term_t *args[2] = {term, make_const(ctx, "[]")};
      result = make_func(ctx, ".", args, 2);
    } else if (term->type == FUNC) {
      result = make_const(ctx, "[]");
      for (int i = term->arity - 1; i >= 0; i--) {
        term_t *args[2] = {term->args[i], result};
        result = make_func(ctx, ".", args, 2);
      }
      term_t *args[2] = {make_const(ctx, term->name), result};
      result = make_func(ctx, ".", args, 2);
    } else {
      return BUILTIN_FAIL;
    }
    return unify(ctx, goal->args[1], result, env) ? BUILTIN_OK : BUILTIN_FAIL;
  }
  // list -> term
  if (list->type == VAR) {
    throw_instantiation_error(ctx, "=../2");
    return BUILTIN_ERROR;
  }
  term_t *cur = deref(env, list);
  if (!is_cons(cur)) {
    throw_type_error(ctx, "list", list, "=../2");
    return BUILTIN_ERROR;
  }
  term_t *head = deref(env, cur->args[0]);
  if (head->type == VAR) {
    throw_instantiation_error(ctx, "=../2");
    return BUILTIN_ERROR;
  }
  cur = deref(env, cur->args[1]);
  // head must be atom when list has args; must be atomic when arity 0
  if (is_cons(cur) && head->type != CONST) {
    throw_type_error(ctx, "atom", head, "=../2");
    return BUILTIN_ERROR;
  }
  if (!is_cons(cur) && !is_nil(cur)) {
    throw_type_error(ctx, "list", list, "=../2");
    return BUILTIN_ERROR;
  }
  const char *fname = term_atom_str(head);
  if (!fname)
    return BUILTIN_FAIL;
  term_t *args[MAX_ARGS];
  int ar = 0;
  while (is_cons(cur)) {
    if (ar >= MAX_ARGS)
      return BUILTIN_FAIL;
    args[ar++] = deref(env, cur->args[0]);
    cur = deref(env, cur->args[1]);
  }
  if (!is_nil(cur)) {
    throw_type_error(ctx, "list", list, "=../2");
    return BUILTIN_ERROR;
  }
  term_t *result =
      (ar == 0) ? make_const(ctx, fname) : make_func(ctx, fname, args, ar);
  return unify(ctx, goal->args[0], result, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_copy_term(prolog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  term_t *orig = substitute(ctx, env, deref(env, goal->args[0]));
  term_t *copy = rename_vars(ctx, orig);
  return unify(ctx, goal->args[1], copy, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static void flatten_body(env_t *env, term_t *body, clause_t *c) {
  while (body->type == FUNC && strcmp(body->name, ",") == 0 &&
         body->arity == 2 && c->body_count < MAX_GOALS - 1) {
    c->body[c->body_count++] = deref(env, body->args[0]);
    body = deref(env, body->args[1]);
  }
  c->body[c->body_count++] = body;
}

static builtin_result_t builtin_assertz(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  if (ctx->db_count >= MAX_CLAUSES)
    return BUILTIN_FAIL;
  ctx->alloc_permanent = true;
  term_t *arg = substitute(ctx, env, deref(env, goal->args[0]));
  clause_t *c = &ctx->database[ctx->db_count];
  c->body_count = 0;
  if (arg->type == FUNC && strcmp(arg->name, ":-") == 0 && arg->arity == 2) {
    c->head = deref(env, arg->args[0]);
    flatten_body(env, deref(env, arg->args[1]), c);
  } else {
    c->head = arg;
  }
  ctx->alloc_permanent = false;
  ctx->db_count++;
  ctx->db_dirty = true;
  return BUILTIN_OK;
}

static builtin_result_t builtin_asserta(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  if (ctx->db_count >= MAX_CLAUSES)
    return BUILTIN_FAIL;
  for (int i = ctx->db_count; i > 0; i--)
    ctx->database[i] = ctx->database[i - 1];
  ctx->db_count++;
  ctx->alloc_permanent = true;
  term_t *arg = substitute(ctx, env, deref(env, goal->args[0]));
  clause_t *c = &ctx->database[0];
  c->body_count = 0;
  if (arg->type == FUNC && strcmp(arg->name, ":-") == 0 && arg->arity == 2) {
    c->head = deref(env, arg->args[0]);
    flatten_body(env, deref(env, arg->args[1]), c);
  } else {
    c->head = arg;
  }
  ctx->alloc_permanent = false;
  ctx->db_dirty = true;
  return BUILTIN_OK;
}

// Build a conjunction term from a clause body array (for retract matching).
static term_t *body_to_term(prolog_ctx_t *ctx, term_t **body, int n) {
  if (n == 0)
    return make_const(ctx, "true");
  term_t *result = body[n - 1];
  for (int i = n - 2; i >= 0; i--) {
    term_t *args[2] = {body[i], result};
    result = make_func(ctx, ",", args, 2);
  }
  return result;
}

static builtin_result_t builtin_retract(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  term_t *arg = deref(env, goal->args[0]);
  bool has_body =
      (arg->type == FUNC && strcmp(arg->name, ":-") == 0 && arg->arity == 2);
  term_t *head_pat = has_body ? deref(env, arg->args[0]) : arg;
  term_t *body_pat = has_body ? deref(env, arg->args[1]) : NULL;

  for (int i = 0; i < ctx->db_count; i++) {
    int env_mark = env->count;
    int trm_save = ctx->term_pool_offset;
    var_id_map_t map = {0};
    term_t *rhead = rename_vars_mapped(ctx, ctx->database[i].head, &map);
    bool ok = unify(ctx, head_pat, rhead, env);
    if (ok && body_pat) {
      term_t *rbody =
          body_to_term(ctx, ctx->database[i].body, ctx->database[i].body_count);
      rbody = rename_vars_mapped(ctx, rbody, &map);
      ok = unify(ctx, body_pat, rbody, env);
    }
    if (ok) {
      for (int j = i; j < ctx->db_count - 1; j++)
        ctx->database[j] = ctx->database[j + 1];
      ctx->db_count--;
      ctx->db_dirty = true;
      return BUILTIN_OK;
    }
    env->count = ctx->bind_count = env_mark;
    ctx->term_pool_offset = trm_save;
  }
  return BUILTIN_FAIL;
}

static builtin_result_t builtin_retractall(prolog_ctx_t *ctx, term_t *goal,
                                           env_t *env) {
  term_t *head_pat = deref(env, goal->args[0]);
  int i = 0;
  while (i < ctx->db_count) {
    int env_mark = env->count;
    int trm_save = ctx->term_pool_offset;
    bool matched =
        unify(ctx, head_pat, rename_vars(ctx, ctx->database[i].head), env);
    env->count = ctx->bind_count = env_mark;
    ctx->term_pool_offset = trm_save;
    if (matched) {
      for (int j = i; j < ctx->db_count - 1; j++)
        ctx->database[j] = ctx->database[j + 1];
      ctx->db_count--;
      ctx->db_dirty = true;
    } else {
      i++;
    }
  }
  return BUILTIN_OK;
}

static builtin_result_t builtin_succ(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  term_t *x = deref(env, goal->args[0]);
  term_t *y = deref(env, goal->args[1]);
  char buf[16];
  int n;
  if (x->type != VAR) {
    if (!term_as_int(x, &n) || n < 0)
      return BUILTIN_FAIL;
    snprintf(buf, sizeof(buf), "%d", n + 1);
    return unify(ctx, goal->args[1], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  if (y->type != VAR) {
    if (!term_as_int(y, &n) || n < 1)
      return BUILTIN_FAIL;
    snprintf(buf, sizeof(buf), "%d", n - 1);
    return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  return BUILTIN_FAIL;
}

static builtin_result_t builtin_plus(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  term_t *x = deref(env, goal->args[0]);
  term_t *y = deref(env, goal->args[1]);
  term_t *z = deref(env, goal->args[2]);
  char buf[16];
  int nx, ny, nz;
  if (x->type != VAR && y->type != VAR) {
    if (!term_as_int(x, &nx) || !term_as_int(y, &ny))
      return BUILTIN_FAIL;
    snprintf(buf, sizeof(buf), "%d", nx + ny);
    return unify(ctx, goal->args[2], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  if (x->type != VAR && z->type != VAR) {
    if (!term_as_int(x, &nx) || !term_as_int(z, &nz))
      return BUILTIN_FAIL;
    snprintf(buf, sizeof(buf), "%d", nz - nx);
    return unify(ctx, goal->args[1], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  if (y->type != VAR && z->type != VAR) {
    if (!term_as_int(y, &ny) || !term_as_int(z, &nz))
      return BUILTIN_FAIL;
    snprintf(buf, sizeof(buf), "%d", nz - ny);
    return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  return BUILTIN_FAIL;
}

static int list_to_array(env_t *env, term_t *list, term_t **arr, int max) {
  int n = 0;
  list = deref(env, list);
  while (is_cons(list)) {
    if (n >= max)
      return -1;
    arr[n++] = deref(env, list->args[0]);
    list = deref(env, list->args[1]);
  }
  return is_nil(list) ? n : -1;
}

static term_t *array_to_list(prolog_ctx_t *ctx, term_t **arr, int n) {
  term_t *list = make_const(ctx, "[]");
  for (int i = n - 1; i >= 0; i--) {
    term_t *args[2] = {arr[i], list};
    list = make_func(ctx, ".", args, 2);
  }
  return list;
}

static builtin_result_t builtin_msort(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  term_t *elems[MAX_LIST_LIT];
  int n = list_to_array(env, goal->args[0], elems, MAX_LIST_LIT);
  if (n < 0)
    return BUILTIN_FAIL;
  // insertion sort by term_order
  for (int i = 1; i < n; i++) {
    term_t *key = elems[i];
    int j = i - 1;
    while (j >= 0 && term_order(elems[j], key, env) > 0) {
      elems[j + 1] = elems[j];
      j--;
    }
    elems[j + 1] = key;
  }
  return unify(ctx, goal->args[1], array_to_list(ctx, elems, n), env)
             ? BUILTIN_OK
             : BUILTIN_FAIL;
}

static builtin_result_t builtin_sort(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  term_t *elems[MAX_LIST_LIT];
  int n = list_to_array(env, goal->args[0], elems, MAX_LIST_LIT);
  if (n < 0)
    return BUILTIN_FAIL;
  // insertion sort
  for (int i = 1; i < n; i++) {
    term_t *key = elems[i];
    int j = i - 1;
    while (j >= 0 && term_order(elems[j], key, env) > 0) {
      elems[j + 1] = elems[j];
      j--;
    }
    elems[j + 1] = key;
  }
  // remove duplicates
  int out = 0;
  for (int i = 0; i < n; i++) {
    if (i == 0 || term_order(elems[i], elems[out - 1], env) != 0)
      elems[out++] = elems[i];
  }
  return unify(ctx, goal->args[1], array_to_list(ctx, elems, out), env)
             ? BUILTIN_OK
             : BUILTIN_FAIL;
}

#define BCAP_SIZE 4096
typedef struct {
  io_hooks_t saved;
  char buf[BCAP_SIZE];
  int pos;
} bcap_t;

static void bcap_write_str(prolog_ctx_t *ctx, const char *str, void *ud) {
  (void)ctx;
  bcap_t *c = ud;
  int len = (int)strlen(str);
  int rem = BCAP_SIZE - c->pos - 1;
  if (len > rem)
    len = rem;
  if (len > 0) {
    memcpy(c->buf + c->pos, str, len);
    c->pos += len;
    c->buf[c->pos] = '\0';
  }
}

static void bcap_writef(prolog_ctx_t *ctx, const char *fmt, va_list args,
                        void *ud) {
  (void)ctx;
  bcap_t *c = ud;
  int rem = BCAP_SIZE - c->pos - 1;
  if (rem > 0) {
    int n = vsnprintf(c->buf + c->pos, rem, fmt, args);
    if (n > 0) {
      c->pos += (n >= rem ? rem : n);
      c->buf[c->pos] = '\0';
    }
  }
}

static void bcap_start(prolog_ctx_t *ctx, bcap_t *c) {
  c->saved = ctx->io_hooks;
  c->pos = 0;
  c->buf[0] = '\0';
  ctx->io_hooks.write_str = bcap_write_str;
  ctx->io_hooks.writef = bcap_writef;
  ctx->io_hooks.writef_err = bcap_writef;
  ctx->io_hooks.userdata = c;
}

static void bcap_end(prolog_ctx_t *ctx, bcap_t *c) { ctx->io_hooks = c->saved; }

static term_t *make_stream_term(prolog_ctx_t *ctx, int id) {
  char buf[16];
  snprintf(buf, sizeof(buf), "%d", id);
  term_t *n = make_const(ctx, buf);
  term_t *args[1] = {n};
  return make_func(ctx, "$stream", args, 1);
}

static bool get_stream_id(env_t *env, term_t *t, int *id) {
  t = deref(env, t);
  if (!t || t->type != FUNC || strcmp(t->name, "$stream") != 0 || t->arity != 1)
    return false;
  return term_as_int(t->args[0], id);
}

// stream write helpers — redirect ctx io hooks to a file stream
typedef struct {
  io_hooks_t saved;
  prolog_ctx_t *ctx;
  void *file_handle;
} scap_t;

static void scap_write_str(prolog_ctx_t *ctx, const char *str, void *ud) {
  (void)ctx;
  scap_t *c = ud;
  io_file_write(c->ctx, c->file_handle, str);
}

static void scap_writef(prolog_ctx_t *ctx, const char *fmt, va_list args,
                        void *ud) {
  (void)ctx;
  scap_t *c = ud;
  char buf[4096];
  vsnprintf(buf, sizeof(buf), fmt, args);
  io_file_write(c->ctx, c->file_handle, buf);
}

static void scap_start(prolog_ctx_t *ctx, scap_t *c, void *file_handle) {
  c->saved = ctx->io_hooks;
  c->ctx = ctx;
  c->file_handle = file_handle;
  ctx->io_hooks.write_str = scap_write_str;
  ctx->io_hooks.writef = scap_writef;
  ctx->io_hooks.writef_err = scap_writef;
  ctx->io_hooks.userdata = c;
}

static void scap_end(prolog_ctx_t *ctx, scap_t *c) { ctx->io_hooks = c->saved; }

// resolve stream arg: NULL = user_output, (void*)-1 = error, else file handle
static void *resolve_output_stream(prolog_ctx_t *ctx, env_t *env, term_t *arg) {
  arg = deref(env, arg);
  if (arg && arg->type == CONST &&
      (strcmp(arg->name, "user_output") == 0 || strcmp(arg->name, "user") == 0))
    return NULL;
  int id;
  if (!get_stream_id(env, arg, &id))
    return (void *)-1;
  if (id < 0 || id >= MAX_OPEN_STREAMS || !ctx->open_streams[id])
    return (void *)-1;
  return ctx->open_streams[id];
}

static builtin_result_t builtin_nl1(prolog_ctx_t *ctx, term_t *goal,
                                    env_t *env) {
  void *h = resolve_output_stream(ctx, env, goal->args[0]);
  if (h == (void *)-1)
    return BUILTIN_FAIL;
  if (!h)
    io_write_str(ctx, "\n");
  else
    io_file_write(ctx, h, "\n");
  return BUILTIN_OK;
}

static builtin_result_t builtin_write2(prolog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  void *h = resolve_output_stream(ctx, env, goal->args[0]);
  if (h == (void *)-1)
    return BUILTIN_FAIL;
  term_t *term = deref(env, goal->args[1]);
  if (!h) {
    io_write_term(ctx, term, env);
  } else {
    scap_t cap;
    scap_start(ctx, &cap, h);
    io_write_term(ctx, term, env);
    scap_end(ctx, &cap);
  }
  return BUILTIN_OK;
}

static builtin_result_t builtin_writeln2(prolog_ctx_t *ctx, term_t *goal,
                                         env_t *env) {
  void *h = resolve_output_stream(ctx, env, goal->args[0]);
  if (h == (void *)-1)
    return BUILTIN_FAIL;
  term_t *term = deref(env, goal->args[1]);
  if (!h) {
    io_write_term(ctx, term, env);
    io_write_str(ctx, "\n");
  } else {
    scap_t cap;
    scap_start(ctx, &cap, h);
    io_write_term(ctx, term, env);
    scap_end(ctx, &cap);
    io_file_write(ctx, h, "\n");
  }
  return BUILTIN_OK;
}

static builtin_result_t builtin_writeq2(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  void *h = resolve_output_stream(ctx, env, goal->args[0]);
  if (h == (void *)-1)
    return BUILTIN_FAIL;
  term_t *term = deref(env, goal->args[1]);
  if (!h) {
    io_write_term_quoted(ctx, term, env);
  } else {
    scap_t cap;
    scap_start(ctx, &cap, h);
    io_write_term_quoted(ctx, term, env);
    scap_end(ctx, &cap);
  }
  return BUILTIN_OK;
}

static builtin_result_t builtin_with_output_to(prolog_ctx_t *ctx, term_t *goal,
                                               env_t *env) {
  term_t *sink = deref(env, goal->args[0]);
  term_t *g = deref(env, goal->args[1]);

  if (!sink || sink->type != FUNC || sink->arity != 1)
    return BUILTIN_FAIL;

  const char *sname = sink->name;
  bool is_atom = strcmp(sname, "atom") == 0;
  bool is_string = strcmp(sname, "string") == 0;
  bool is_codes = strcmp(sname, "codes") == 0;
  bool is_chars = strcmp(sname, "chars") == 0;
  if (!is_atom && !is_string && !is_codes && !is_chars)
    return BUILTIN_FAIL;

  bcap_t cap;
  bcap_start(ctx, &cap);
  goal_stmt_t cn = goals_alloc(ctx, 1);
  cn.goals[cn.count++] = g;
  bool ok = solve(ctx, &cn, env);
  bcap_end(ctx, &cap);

  if (!ok)
    return BUILTIN_FAIL;

  term_t *result;
  if (is_string) {
    result = make_string(ctx, cap.buf);
  } else if (is_codes) {
    int len = (int)strlen(cap.buf);
    result = make_const(ctx, "[]");
    for (int i = len - 1; i >= 0; i--) {
      char nb[8];
      snprintf(nb, sizeof(nb), "%d", (unsigned char)cap.buf[i]);
      term_t *a2[2] = {make_const(ctx, nb), result};
      result = make_func(ctx, ".", a2, 2);
    }
  } else if (is_chars) {
    int len = (int)strlen(cap.buf);
    result = make_const(ctx, "[]");
    for (int i = len - 1; i >= 0; i--) {
      char cb[2] = {cap.buf[i], '\0'};
      term_t *a2[2] = {make_const(ctx, cb), result};
      result = make_func(ctx, ".", a2, 2);
    }
  } else {
    result = make_const(ctx, cap.buf);
  }

  return unify(ctx, sink->args[0], result, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_to_atom(prolog_ctx_t *ctx, term_t *goal,
                                             env_t *env) {
  term_t *term_arg = deref(env, goal->args[0]);
  term_t *atom_arg = deref(env, goal->args[1]);

  // atom → term direction
  if (term_arg->type == VAR && atom_arg->type != VAR) {
    const char *str =
        (atom_arg->type == STRING) ? atom_arg->string_data : atom_arg->name;
    if (!str)
      return BUILTIN_FAIL;

    char *sp = ctx->input_ptr, *ss = ctx->input_start;
    int sl = ctx->input_line, sv = ctx->clause_var_count;

    ctx->input_ptr = (char *)str;
    ctx->input_start = (char *)str;
    ctx->input_line = 1;
    ctx->clause_var_count = 0;
    parse_error_clear(ctx);
    term_t *parsed = parse_term(ctx);
    bool is_eof = ctx->error.error_is_eof;
    // check for trailing non-whitespace input
    char *after = ctx->input_ptr;
    while (isspace((unsigned char)*after))
      after++;
    bool has_trailing = (*after != '\0');
    ctx->input_ptr = sp;
    ctx->input_start = ss;
    ctx->input_line = sl;
    ctx->clause_var_count = sv;

    if (!parsed || parse_has_error(ctx) || has_trailing) {
      parse_error_clear(ctx);
      if (is_eof) {
        term_t *eof = make_const(ctx, "end_of_file");
        term_t *se_args[1] = {eof};
        throw_error(ctx, make_func(ctx, "syntax_error", se_args, 1),
                    "term_to_atom/2");
        return BUILTIN_ERROR;
      }
      return BUILTIN_FAIL;
    }
    return unify(ctx, term_arg, parsed, env) ? BUILTIN_OK : BUILTIN_FAIL;
  }

  // term → atom direction
  bcap_t cap;
  bcap_start(ctx, &cap);
  print_term(ctx, term_arg, env, true);
  bcap_end(ctx, &cap);

  return unify(ctx, atom_arg, make_const(ctx, cap.buf), env) ? BUILTIN_OK
                                                             : BUILTIN_FAIL;
}

static builtin_result_t builtin_atom_to_term(prolog_ctx_t *ctx, term_t *goal,
                                             env_t *env) {
  term_t *atom_arg = deref(env, goal->args[0]);
  const char *str =
      (atom_arg->type == STRING) ? atom_arg->string_data : atom_arg->name;
  if (!str)
    return BUILTIN_FAIL;

  // save parser state
  char *sp = ctx->input_ptr, *ss = ctx->input_start;
  int sl = ctx->input_line, sv = ctx->clause_var_count;
  struct {
    const char *name;
    int var_id;
  } saved_vars[MAX_CLAUSE_VARS];
  memcpy(saved_vars, ctx->clause_vars, sizeof(saved_vars));

  ctx->input_ptr = (char *)str;
  ctx->input_start = (char *)str;
  ctx->input_line = 1;
  ctx->clause_var_count = 0;
  parse_error_clear(ctx);
  term_t *parsed = parse_term(ctx);
  bool is_eof = ctx->error.error_is_eof;
  // check for trailing non-whitespace input
  char *after = ctx->input_ptr;
  while (isspace((unsigned char)*after))
    after++;
  bool has_trailing = (*after != '\0');

  // build bindings list before restoring
  term_t *bindings = make_const(ctx, "[]");
  for (int i = ctx->clause_var_count - 1; i >= 0; i--) {
    const char *vname = ctx->clause_vars[i].name;
    if (!vname || strcmp(vname, "_") == 0)
      continue;
    term_t *vt = make_var(ctx, vname, ctx->clause_vars[i].var_id);
    term_t *eq[2] = {make_const(ctx, vname), vt};
    term_t *pair = make_func(ctx, "=", eq, 2);
    term_t *cell[2] = {pair, bindings};
    bindings = make_func(ctx, ".", cell, 2);
  }

  ctx->input_ptr = sp;
  ctx->input_start = ss;
  ctx->input_line = sl;
  ctx->clause_var_count = sv;
  memcpy(ctx->clause_vars, saved_vars, sizeof(saved_vars));

  if (!parsed || parse_has_error(ctx) || has_trailing) {
    parse_error_clear(ctx);
    if (is_eof) {
      term_t *eof = make_const(ctx, "end_of_file");
      term_t *se_args[1] = {eof};
      throw_error(ctx, make_func(ctx, "syntax_error", se_args, 1),
                  "atom_to_term/3");
      return BUILTIN_ERROR;
    }
    return BUILTIN_FAIL;
  }
  if (!unify(ctx, goal->args[1], parsed, env))
    return BUILTIN_FAIL;
  return unify(ctx, goal->args[2], bindings, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_open(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  term_t *path_t = deref(env, goal->args[0]);
  term_t *mode_t = deref(env, goal->args[1]);
  if (!path_t || !mode_t || mode_t->type != CONST)
    return BUILTIN_FAIL;

  const char *path =
      (path_t->type == STRING) ? path_t->string_data : path_t->name;
  if (!path)
    return BUILTIN_FAIL;

  const char *fmode;
  if (strcmp(mode_t->name, "read") == 0)
    fmode = "r";
  else if (strcmp(mode_t->name, "write") == 0)
    fmode = "w";
  else if (strcmp(mode_t->name, "append") == 0)
    fmode = "a";
  else
    return BUILTIN_FAIL;

  int slot = -1;
  for (int i = 0; i < MAX_OPEN_STREAMS; i++) {
    if (!ctx->open_streams[i]) {
      slot = i;
      break;
    }
  }
  if (slot < 0)
    return BUILTIN_FAIL;

  void *handle = io_file_open(ctx, path, fmode);
  if (!handle)
    return BUILTIN_FAIL;

  ctx->open_streams[slot] = handle;
  return unify(ctx, goal->args[2], make_stream_term(ctx, slot), env)
             ? BUILTIN_OK
             : BUILTIN_FAIL;
}

static builtin_result_t builtin_close(prolog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  int id;
  if (!get_stream_id(env, goal->args[0], &id))
    return BUILTIN_FAIL;
  if (id < 0 || id >= MAX_OPEN_STREAMS || !ctx->open_streams[id])
    return BUILTIN_FAIL;
  io_file_close(ctx, ctx->open_streams[id]);
  ctx->open_streams[id] = NULL;
  return BUILTIN_OK;
}

static builtin_result_t builtin_read_line_to_atom(prolog_ctx_t *ctx,
                                                  term_t *goal, env_t *env) {
  char line[1024];
  char *r;

  term_t *stream_arg = deref(env, goal->args[0]);
  bool is_user = stream_arg && stream_arg->type == CONST &&
                 (strcmp(stream_arg->name, "user_input") == 0 ||
                  strcmp(stream_arg->name, "user") == 0);
  if (is_user) {
    r = io_read_line(ctx, line, sizeof(line));
  } else {
    int id;
    if (!get_stream_id(env, stream_arg, &id))
      return BUILTIN_FAIL;
    if (id < 0 || id >= MAX_OPEN_STREAMS || !ctx->open_streams[id])
      return BUILTIN_FAIL;
    r = io_file_read_line(ctx, ctx->open_streams[id], line, sizeof(line));
  }
  term_t *result;
  if (!r) {
    result = make_const(ctx, "end_of_file");
  } else {
    line[strcspn(line, "\n")] = '\0';
    result = make_const(ctx, line);
  }

  return unify(ctx, goal->args[1], result, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_get_char(prolog_ctx_t *ctx, term_t *goal,
                                         env_t *env) {
  int c = io_read_char(ctx);
  term_t *result;
  if (c == -1) {
    result = make_const(ctx, "end_of_file");
  } else {
    char buf[2] = {(char)c, '\0'};
    result = make_const(ctx, buf);
  }
  return unify(ctx, goal->args[0], result, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_read_term(prolog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  int id;
  if (!get_stream_id(env, goal->args[0], &id))
    return BUILTIN_FAIL;
  if (id < 0 || id >= MAX_OPEN_STREAMS || !ctx->open_streams[id])
    return BUILTIN_FAIL;

  char clause_buf[BCAP_SIZE] = {0};
  char line[1024];

  while (io_file_read_line(ctx, ctx->open_streams[id], line, sizeof(line))) {
    line[strcspn(line, "\n")] = '\0';
    strip_line_comment(line);
    char *trimmed = line;
    while (*trimmed == ' ' || *trimmed == '\t')
      trimmed++;
    if (*trimmed == '\0' && clause_buf[0] == '\0')
      continue;
    if (clause_buf[0] != '\0' && *trimmed != '\0')
      strncat(clause_buf, " ", sizeof(clause_buf) - strlen(clause_buf) - 1);
    strncat(clause_buf, trimmed, sizeof(clause_buf) - strlen(clause_buf) - 1);
    if (has_complete_clause(clause_buf))
      break;
  }

  if (clause_buf[0] == '\0')
    return unify(ctx, goal->args[1], make_const(ctx, "end_of_file"), env)
               ? BUILTIN_OK
               : BUILTIN_FAIL;

  // strip terminating dot
  int len = (int)strlen(clause_buf);
  while (len > 0 && (clause_buf[len - 1] == ' ' || clause_buf[len - 1] == '\t'))
    len--;
  if (len > 0 && clause_buf[len - 1] == '.')
    len--;
  clause_buf[len] = '\0';

  char *sp = ctx->input_ptr, *ss = ctx->input_start;
  int sl = ctx->input_line, sv = ctx->clause_var_count;

  ctx->input_ptr = clause_buf;
  ctx->input_start = clause_buf;
  ctx->input_line = 1;
  ctx->clause_var_count = 0;
  parse_error_clear(ctx);
  term_t *parsed = parse_term(ctx);

  ctx->input_ptr = sp;
  ctx->input_start = ss;
  ctx->input_line = sl;
  ctx->clause_var_count = sv;

  if (!parsed || parse_has_error(ctx))
    return BUILTIN_FAIL;
  return unify(ctx, goal->args[1], parsed, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_make(prolog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  (void)goal;
  (void)env;
  if (ctx->make_file_count == 0)
    return BUILTIN_OK; // no files tracked yet

  // check which files have changed since they were loaded
  int changed = 0;
  for (int i = 0; i < ctx->make_file_count; i++) {
    long long cur = io_file_mtime(ctx, ctx->make_files[i].path);
    if (cur == -1LL || cur != ctx->make_files[i].mtime)
      changed++;
  }

  if (changed == 0) {
    io_writef(ctx, "%% make: nothing to reload\n");
    return BUILTIN_OK;
  }

  // snapshot file list before resetting pools
  int count = ctx->make_file_count;
  char snapshot[MAX_MAKE_FILES][MAX_FILE_PATH];
  for (int i = 0; i < count; i++) {
    strncpy(snapshot[i], ctx->make_files[i].path, MAX_FILE_PATH - 1);
    snapshot[i][MAX_FILE_PATH - 1] = '\0';
  }

  // roll back to the state captured before the first consult
  ctx->db_count = ctx->make_db_mark;
  ctx->term_pool_offset = ctx->make_term_mark;
  ctx->string_pool_offset = ctx->make_string_mark;
  ctx->make_file_count = 0;

  for (int i = 0; i < count; i++)
    prolog_load_file(ctx, snapshot[i]);

  io_writef(ctx, "%% make: reloaded %d file(s) (%d changed)\n", count, changed);
  return BUILTIN_OK;
}

// dynamic/1: declaration hint — no-op (all predicates are dynamic here)
static builtin_result_t builtin_dynamic(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  (void)goal;
  (void)env;
  return BUILTIN_OK;
}

// abolish/1: remove all clauses for a predicate indicator Name/Arity
static builtin_result_t builtin_abolish(prolog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  term_t *ind = deref(env, goal->args[0]);
  if (ind->type == VAR) {
    throw_instantiation_error(ctx, "abolish/1");
    return BUILTIN_ERROR;
  }
  if (ind->type != FUNC || strcmp(ind->name, "/") != 0 || ind->arity != 2) {
    throw_type_error(ctx, "predicate_indicator", ind, "abolish/1");
    return BUILTIN_ERROR;
  }
  term_t *n = deref(env, ind->args[0]);
  term_t *a = deref(env, ind->args[1]);
  if (n->type == VAR || a->type == VAR) {
    throw_instantiation_error(ctx, "abolish/1");
    return BUILTIN_ERROR;
  }
  const char *name = term_atom_str(n);
  int arity;
  if (!name || !term_as_int(a, &arity)) {
    throw_type_error(ctx, "predicate_indicator", ind, "abolish/1");
    return BUILTIN_ERROR;
  }
  int i = 0;
  while (i < ctx->db_count) {
    clause_t *c = &ctx->database[i];
    const char *cn = (c->head->type == FUNC) ? c->head->name : c->head->name;
    int ca = (c->head->type == FUNC) ? c->head->arity : 0;
    if (strcmp(cn, name) == 0 && ca == arity) {
      for (int j = i; j < ctx->db_count - 1; j++)
        ctx->database[j] = ctx->database[j + 1];
      ctx->db_count--;
    } else {
      i++;
    }
  }
  return BUILTIN_OK;
}

// current_prolog_flag/2
static builtin_result_t builtin_current_prolog_flag(prolog_ctx_t *ctx,
                                                    term_t *goal, env_t *env) {
  term_t *flag = deref(env, goal->args[0]);
  if (flag->type == VAR) {
    throw_instantiation_error(ctx, "current_prolog_flag/2");
    return BUILTIN_ERROR;
  }
  const char *fname = term_atom_str(flag);
  if (!fname) {
    throw_type_error(ctx, "atom", flag, "current_prolog_flag/2");
    return BUILTIN_ERROR;
  }
  char buf[32];
  const char *val = NULL;
  if (strcmp(fname, "bounded") == 0)
    val = "true";
  else if (strcmp(fname, "max_integer") == 0) {
    snprintf(buf, sizeof(buf), "%d", 2147483647);
    val = buf;
  } else if (strcmp(fname, "min_integer") == 0) {
    snprintf(buf, sizeof(buf), "%d", (int)-2147483647 - 1);
    val = buf;
  } else if (strcmp(fname, "integer_rounding_function") == 0)
    val = "toward_zero";
  else if (strcmp(fname, "max_arity") == 0) {
    snprintf(buf, sizeof(buf), "%d", MAX_ARGS);
    val = buf;
  } else {
    throw_type_error(ctx, "prolog_flag", flag, "current_prolog_flag/2");
    return BUILTIN_ERROR;
  }
  return unify(ctx, goal->args[1], make_const(ctx, val), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static const builtin_t builtins[] = {
    {"true", 0, builtin_true},
    {"fail", 0, builtin_fail},
    {"!", 0, builtin_cut},
    {"stats", 0, builtin_stats},
    {"make", 0, builtin_make},
    {"nl", 0, builtin_nl},
    {"flush_output", 0, builtin_flush_output},
    {"clear", 0, builtin_clear},
    {"nl", 1, builtin_nl1},
    {"is", 2, builtin_is},
    {"=", 2, builtin_unify},
    {"\\=", 2, builtin_not_unify},
    {"==", 2, builtin_struct_eq},
    {"\\==", 2, builtin_struct_neq},
    {"@<", 2, builtin_term_lt},
    {"@>", 2, builtin_term_gt},
    {"@=<", 2, builtin_term_le},
    {"@>=", 2, builtin_term_ge},
    {"<", 2, builtin_lt},
    {">", 2, builtin_gt},
    {"=<", 2, builtin_le},
    {">=", 2, builtin_ge},
    {"=:=", 2, builtin_arith_eq},
    {"=\\=", 2, builtin_arith_ne},
    {"throw", 1, builtin_throw},
    {"once", 1, builtin_once},
    {"\\+", 1, builtin_not},
    {"var", 1, builtin_var},
    {"nonvar", 1, builtin_nonvar},
    {"atom", 1, builtin_atom},
    {"integer", 1, builtin_integer},
    {"is_list", 1, builtin_is_list},
    {"write", 1, builtin_write},
    {"write", 2, builtin_write2},
    {"writeln", 1, builtin_writeln},
    {"writeln", 2, builtin_writeln2},
    {"writeq", 1, builtin_writeq},
    {"writeq", 2, builtin_writeq2},
    {"consult", 1, builtin_consult},
    {"include", 1, builtin_include},
    {"findall", 3, builtin_findall},
    {"bagof", 3, builtin_bagof},
    {"setof", 3, builtin_setof},
    {"compare", 3, builtin_compare},
    {"compound", 1, builtin_compound},
    {"callable", 1, builtin_callable},
    {"number", 1, builtin_number},
    {"atomic", 1, builtin_atomic},
    {"string", 1, builtin_string},
    {"atom_length", 2, builtin_atom_length},
    {"atom_concat", 3, builtin_atom_concat},
    {"sub_atom", 5, builtin_sub_atom},
    {"atom_chars", 2, builtin_atom_chars},
    {"atom_codes", 2, builtin_atom_codes},
    {"char_code", 2, builtin_char_code},
    {"atom_number", 2, builtin_atom_number},
    {"number_codes", 2, builtin_number_codes},
    {"number_chars", 2, builtin_number_chars},
    {"functor", 3, builtin_functor},
    {"arg", 3, builtin_arg},
    {"=..", 2, builtin_univ},
    {"copy_term", 2, builtin_copy_term},
    {"assertz", 1, builtin_assertz},
    {"assert", 1, builtin_assertz},
    {"asserta", 1, builtin_asserta},
    {"retract", 1, builtin_retract},
    {"retractall", 1, builtin_retractall},
    {"dynamic", 1, builtin_dynamic},
    {"abolish", 1, builtin_abolish},
    {"current_prolog_flag", 2, builtin_current_prolog_flag},
    {"succ", 2, builtin_succ},
    {"plus", 3, builtin_plus},
    {"msort", 2, builtin_msort},
    {"sort", 2, builtin_sort},
    {"with_output_to", 2, builtin_with_output_to},
    {"term_to_atom", 2, builtin_term_to_atom},
    {"atom_to_term", 3, builtin_atom_to_term},
    {"open", 3, builtin_open},
    {"close", 1, builtin_close},
    {"read_line_to_atom", 2, builtin_read_line_to_atom},
    {"get_char", 1, builtin_get_char},
    {"read_term", 2, builtin_read_term},
    {NULL, 0, NULL}};

builtin_result_t try_builtin(prolog_ctx_t *ctx, term_t *goal, env_t *env) {
  goal = deref(env, goal);

  const char *name = goal->name;
  int arity = (goal->type == CONST)  ? 0
              : (goal->type == FUNC) ? goal->arity
                                     : -1;

  if (arity < 0)
    return BUILTIN_NOT_HANDLED;

  for (int i = 0; i < ctx->custom_builtin_count; i++) {
    custom_builtin_t *cb = &ctx->custom_builtins[i];
    if (strcmp(name, cb->name) == 0 &&
        (cb->arity == -1 || arity == cb->arity)) {
      return cb->handler(ctx, goal, env);
    }
  }

  for (const builtin_t *b = builtins; b->name; b++) {
    if (strcmp(name, b->name) == 0 && arity == b->arity) {
      return b->handler(ctx, goal, env);
    }
  }

  return BUILTIN_NOT_HANDLED;
}

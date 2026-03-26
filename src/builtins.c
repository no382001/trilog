#include "platform_impl.h"

//****
//* builtin handler table
//****

typedef struct {
  const char *name;
  int arity; // -1 means any arity, 0 for const
  builtin_result_t (*handler)(trilog_ctx_t *ctx, term_t *goal, env_t *env);
} builtin_t;

//****
//* control flow and unification
//****

static builtin_result_t builtin_true(trilog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  (void)ctx;
  (void)goal;
  (void)env;
  return BUILTIN_OK;
}

static builtin_result_t builtin_fail(trilog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  (void)ctx;
  (void)goal;
  (void)env;
  return BUILTIN_FAIL;
}

static builtin_result_t builtin_unify(trilog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  return unify(ctx, goal->args[0], goal->args[1], env) ? BUILTIN_OK
                                                       : BUILTIN_FAIL;
}

static builtin_result_t builtin_not_unify(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_struct_eq(trilog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  (void)ctx;
  return terms_identical(goal->args[0], goal->args[1], env) ? BUILTIN_OK
                                                            : BUILTIN_FAIL;
}

static builtin_result_t builtin_struct_neq(trilog_ctx_t *ctx, term_t *goal,
                                           env_t *env) {
  (void)ctx;
  return terms_identical(goal->args[0], goal->args[1], env) ? BUILTIN_FAIL
                                                            : BUILTIN_OK;
}

//****
//* term ordering and comparison
//****

// iso standard order: var < number < atom < compound
// within same type: var by id, number by value, atom lexicographic,
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
  };

  int ra = rank[a->type], rb = rank[b->type];

  // split const into number vs atom
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

static builtin_result_t builtin_compare(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  int cmp = term_order(goal->args[1], goal->args[2], env);
  const char *ord = cmp < 0 ? "<" : (cmp > 0 ? ">" : "=");
  return unify(ctx, goal->args[0], make_const(ctx, ord), env) ? BUILTIN_OK
                                                              : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_lt(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  return term_order(goal->args[0], goal->args[1], env) < 0 ? BUILTIN_OK
                                                           : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_gt(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  return term_order(goal->args[0], goal->args[1], env) > 0 ? BUILTIN_OK
                                                           : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_le(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  return term_order(goal->args[0], goal->args[1], env) <= 0 ? BUILTIN_OK
                                                            : BUILTIN_FAIL;
}

static builtin_result_t builtin_term_ge(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  return term_order(goal->args[0], goal->args[1], env) >= 0 ? BUILTIN_OK
                                                            : BUILTIN_FAIL;
}

static builtin_result_t builtin_cut(trilog_ctx_t *ctx, term_t *goal,
                                    env_t *env) {
  (void)ctx;
  (void)goal;
  (void)env;
  return BUILTIN_CUT;
}

static builtin_result_t builtin_stats(trilog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  (void)goal;
  (void)env;
  io_writef(ctx, "term pool: %d / %d bytes (peak %d)\n", ctx->term_pool_offset,
            ctx->term_pool_perm, ctx->term_pool_peak);
  io_writef(ctx, "perm pool: %d / %d bytes\n",
            ctx->term_pool_size - ctx->term_pool_perm, ctx->term_pool_size);
  io_writef(ctx, "unify: %d calls, %d fails\n", ctx->stats.unify_calls,
            ctx->stats.unify_fails);
  io_writef(ctx, "solve: %d son calls, %d backtracks\n", ctx->stats.son_calls,
            ctx->stats.backtracks);
  io_writef(ctx, "string pool: %d / %d bytes\n", ctx->string_pool_offset,
            MAX_STRING_POOL);
  return BUILTIN_OK;
}

//****
//* solution collection (findall, bagof, setof)
//****

typedef struct {
  trilog_ctx_t *ctx;
  term_t *template;
  term_t *list;
  int count;
} findall_state_t;

static bool findall_callback(trilog_ctx_t *ctx, env_t *env, void *userdata,
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

static term_t *reverse_list(trilog_ctx_t *ctx, term_t *list) {
  term_t *result = make_const(ctx, "[]");
  while (is_cons(list)) {
    term_t *args[2] = {list->args[0], result};
    result = make_func(ctx, ".", args, 2);
    list = list->args[1];
  }
  return result;
}

static int collect_solutions(trilog_ctx_t *ctx, term_t *goal, env_t *env,
                             bool fail_on_empty) {
  term_t *template = deref(env, goal->args[0]);
  term_t *query = deref(env, goal->args[1]);
  term_t *result_var = goal->args[2];

  // strip existential quantifier: _^goal -> goal
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
  ctx->bind_floor = MAX_BINDINGS; // disable lco inside findall
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

static builtin_result_t builtin_findall(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  return collect_solutions(ctx, goal, env, false);
}

static builtin_result_t builtin_bagof(trilog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  return collect_solutions(ctx, goal, env, true);
}

static int list_to_array(env_t *env, term_t *list, term_t **arr, int max);
static term_t *array_to_list(trilog_ctx_t *ctx, term_t **arr, int n);

static builtin_result_t builtin_setof(trilog_ctx_t *ctx, term_t *goal,
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
  ctx->bind_floor = MAX_BINDINGS; // disable lco inside setof
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

static bool not_found_callback(trilog_ctx_t *ctx, env_t *env, void *userdata,
                               bool has_more) {
  (void)ctx;
  (void)env;
  (void)has_more;
  *(bool *)userdata = true;
  return false;
}

//****
//* exceptions and meta-predicates
//****

static builtin_result_t builtin_throw(trilog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  term_t *ball = deref(env, goal->args[0]);
  ctx->thrown_ball = ball;
  ctx->has_runtime_error = true;
  // extract readable string from error(type, _) if iso form
  if (ball->type == FUNC && strcmp(ball->name, "error") == 0 &&
      ball->arity == 2) {
    snprintf(ctx->runtime_error, MAX_ERROR_MSG, "%s", ball->args[0]->name);
  } else {
    snprintf(ctx->runtime_error, MAX_ERROR_MSG, "unhandled exception");
  }
  return BUILTIN_ERROR;
}

static bool is_integer_str(const char *s);

static bool check_callable(trilog_ctx_t *ctx, term_t *t, const char *pred) {
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

static builtin_result_t builtin_once(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_not(trilog_ctx_t *ctx, term_t *goal,
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

//****
//* type checking predicates
//****

static builtin_result_t builtin_var(trilog_ctx_t *ctx, term_t *goal,
                                    env_t *env) {
  (void)ctx;
  return deref(env, goal->args[0])->type == VAR ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_nonvar(trilog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  (void)ctx;
  return deref(env, goal->args[0])->type != VAR ? BUILTIN_OK : BUILTIN_FAIL;
}

static builtin_result_t builtin_atom(trilog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST && !is_integer_str(t->name)) ? BUILTIN_OK
                                                        : BUILTIN_FAIL;
}

static builtin_result_t builtin_integer(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST && is_integer_str(t->name)) ? BUILTIN_OK
                                                       : BUILTIN_FAIL;
}

static builtin_result_t builtin_is_list(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  while (is_cons(t))
    t = deref(env, t->args[1]);
  return is_nil(t) ? BUILTIN_OK : BUILTIN_FAIL;
}

//****
//* i/o builtins
//****

static builtin_result_t builtin_nl(trilog_ctx_t *ctx, term_t *goal,
                                   env_t *env) {
  (void)goal;
  (void)env;
  io_write_str(ctx, "\n");
  return BUILTIN_OK;
}

static builtin_result_t builtin_flush_output(trilog_ctx_t *ctx, term_t *goal,
                                             env_t *env) {
  (void)goal;
  (void)env;
  (void)ctx;
#ifndef TRILOG_FREESTANDING // todo: i really dont like this here
  fflush(stdout);
#endif
  return BUILTIN_OK;
}

static builtin_result_t builtin_clear(trilog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  (void)goal;
  (void)env;
  io_write_str(ctx, "\033[2J\033[H");
  return BUILTIN_OK;
}

static builtin_result_t builtin_write(trilog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  io_write_term(ctx, deref(env, goal->args[0]), env);
  return BUILTIN_OK;
}

static builtin_result_t builtin_writeln(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  io_write_term(ctx, deref(env, goal->args[0]), env);
  io_write_str(ctx, "\n");
  return BUILTIN_OK;
}

static builtin_result_t builtin_writeq(trilog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  io_write_term_quoted(ctx, deref(env, goal->args[0]), env);
  return BUILTIN_OK;
}

//****
//* file loading (consult, include)
//****

static const char *resolve_filename(trilog_ctx_t *ctx, term_t *arg, char *buf,
                                    size_t bufsz) {
  const char *filename = NULL;
  if (arg->type == CONST)
    filename = arg->name;
  else
    return NULL;

  if (filename[0] != '/' && ctx->load_dir[0] != '\0') {
    snprintf(buf, bufsz, "%s/%s", ctx->load_dir, filename);
    return buf;
  }
  return filename;
}

// [f1, f2, ...] as a goal: consult each file in the list.
// [] succeeds immediately; '.'(H, T) consults H then iterates T.
static builtin_result_t builtin_nil_goal(trilog_ctx_t *ctx, term_t *goal,
                                         env_t *env) {
  (void)ctx;
  (void)goal;
  (void)env;
  return BUILTIN_OK;
}

static builtin_result_t builtin_list_goal(trilog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  term_t *list = goal;
  while (is_cons(list)) {
    term_t *h = deref(env, list->args[0]);
    if (h->type == VAR) {
      throw_instantiation_error(ctx, "[...] goal");
      return BUILTIN_ERROR;
    }
    if (h->type != CONST) {
      throw_type_error(ctx, "atom", h, "[...] goal");
      return BUILTIN_ERROR;
    }
    int dummy;
    if (term_as_int(h, &dummy)) {
      throw_type_error(ctx, "atom", h, "[...] goal");
      return BUILTIN_ERROR;
    }
    char resolved[MAX_FILE_PATH];
    const char *filename = resolve_filename(ctx, h, resolved, sizeof(resolved));
    if (!filename)
      return BUILTIN_FAIL;
    if (!trilog_load_file(ctx, filename))
      return BUILTIN_FAIL;
    list = deref(env, list->args[1]);
  }
  if (!is_nil(list)) {
    throw_type_error(ctx, "list", list, "[...] goal");
    return BUILTIN_ERROR;
  }
  return BUILTIN_OK;
}

// consult/1: load file as independent unit, tracked for make/0
static builtin_result_t builtin_consult(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  char resolved[MAX_FILE_PATH];
  const char *filename = resolve_filename(ctx, deref(env, goal->args[0]),
                                          resolved, sizeof(resolved));
  if (!filename)
    return BUILTIN_FAIL;
  return trilog_load_file(ctx, filename) ? BUILTIN_OK : BUILTIN_FAIL;
}

// include/1: textual inclusion — only valid as a file directive,
// clauses are owned by the including file, not tracked for make/0
static builtin_result_t builtin_include(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  if (ctx->include_depth == 0) {
    io_writef(
        ctx,
        "Error: include/1 is only valid as a file directive\n"); // todo: should
                                                                 // i throw
                                                                 // instead?
    return BUILTIN_FAIL;
  }
  char resolved[MAX_FILE_PATH];
  const char *filename = resolve_filename(ctx, deref(env, goal->args[0]),
                                          resolved, sizeof(resolved));
  if (!filename)
    return BUILTIN_FAIL;
  // include_depth >= 1 here, so trilog_load_file won't track this file for
  // make/0
  return trilog_load_file(ctx, filename) ? BUILTIN_OK : BUILTIN_FAIL;
}

static const char *term_atom_str(const term_t *t) {
  if (!t)
    return NULL;
  if (t->type == CONST)
    return t->name;
  return NULL;
}

static builtin_result_t builtin_compound(trilog_ctx_t *ctx, term_t *goal,
                                         env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == FUNC) ? BUILTIN_OK : BUILTIN_FAIL;
}
static builtin_result_t builtin_callable(trilog_ctx_t *ctx, term_t *goal,
                                         env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST || t->type == FUNC) ? BUILTIN_OK : BUILTIN_FAIL;
}
static builtin_result_t builtin_number(trilog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST && is_integer_str(t->name)) ? BUILTIN_OK
                                                       : BUILTIN_FAIL;
}
static builtin_result_t builtin_atomic(trilog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  (void)ctx;
  term_t *t = deref(env, goal->args[0]);
  return (t->type == CONST) ? BUILTIN_OK : BUILTIN_FAIL;
}
static builtin_result_t builtin_string(trilog_ctx_t *ctx, term_t *goal,
                                       env_t *env) {
  (void)ctx;
  (void)env;
  (void)goal;
  return BUILTIN_FAIL;
}

//****
//* atom and string manipulation
//****

static builtin_result_t builtin_atom_length(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_atom_concat(trilog_ctx_t *ctx, term_t *goal,
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

// sub_atom(+atom, ?before, ?length, ?after, ?subatom)
// generates or verifies substrings; backtracks over all solutions
static builtin_result_t builtin_sub_atom(trilog_ctx_t *ctx, term_t *goal,
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
  // but since we're a c builtin we enumerate and assert each solution
  // via a small helper: just try them all and return the first matching one.
  // for full backtracking, a proper approach would need multi-solution support
  // in builtins; here we collect all matches and build a disjunction.
  // simple approach: iterate and unify greedily (returns first match only).
  // full backtracking over sub_atom requires the caller to use findall.

  term_t *bef_t = deref(env, goal->args[1]);
  term_t *lng_t = deref(env, goal->args[2]);
  term_t *sub_t = deref(env, goal->args[4]);

  int bef_fixed = -1, lng_fixed = -1;
  if (term_as_int(bef_t, &bef_fixed) && bef_fixed < 0)
    return BUILTIN_FAIL;
  if (term_as_int(lng_t, &lng_fixed) && lng_fixed < 0)
    return BUILTIN_FAIL;

  // when sub is bound, avoid interning every possible substring
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

static term_t *str_to_char_list(trilog_ctx_t *ctx, const char *s) {
  term_t *list = make_const(ctx, "[]");
  for (int i = (int)strlen(s) - 1; i >= 0; i--) {
    char ch[2] = {s[i], '\0'};
    term_t *args[2] = {make_const(ctx, ch), list};
    list = make_func(ctx, ".", args, 2);
  }
  return list;
}

static term_t *str_to_code_list(trilog_ctx_t *ctx, const char *s) {
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

static builtin_result_t builtin_atom_chars(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_atom_codes(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_char_code(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_atom_number(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_number_codes(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_number_chars(trilog_ctx_t *ctx, term_t *goal,
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

//****
//* term decomposition (functor, arg, univ, copy_term)
//****

static builtin_result_t builtin_functor(trilog_ctx_t *ctx, term_t *goal,
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
    if (term->type == CONST) {
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
  // compose: functor(x, name, arity)
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
  if (n->type != CONST) {
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

static builtin_result_t builtin_arg(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_univ(trilog_ctx_t *ctx, term_t *goal,
                                     env_t *env) {
  term_t *term = deref(env, goal->args[0]);
  term_t *list = deref(env, goal->args[1]);
  if (term->type != VAR) {
    term_t *result;
    if (term->type == CONST) {
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

static builtin_result_t builtin_copy_term(trilog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  term_t *orig = substitute(ctx, env, deref(env, goal->args[0]));
  term_t *copy = rename_vars(ctx, orig);
  return unify(ctx, goal->args[1], copy, env) ? BUILTIN_OK : BUILTIN_FAIL;
}

//****
//* database modification (assert, retract)
//****

static bool is_declared_dynamic(trilog_ctx_t *ctx, const char *name,
                                int arity) {
  for (int i = 0; i < ctx->dynamic_pred_count; i++)
    if (ctx->dynamic_preds[i].arity == arity &&
        strcmp(ctx->dynamic_preds[i].name, name) == 0)
      return true;
  return false;
}

// returns true if predicate has file-loaded clauses and no dynamic declaration
static bool is_static_procedure(trilog_ctx_t *ctx, const char *name,
                                int arity) {
  if (is_declared_dynamic(ctx, name, arity))
    return false;
  for (int i = 0; i < ctx->db_count; i++) {
    clause_t *c = &ctx->database[i];
    if (c->source_file == -1)
      continue;
    int ca = (c->head->type == FUNC) ? c->head->arity : 0;
    if (strcmp(c->head->name, name) == 0 && ca == arity)
      return true;
  }
  return false;
}

static void throw_static_proc_error(trilog_ctx_t *ctx, const char *name,
                                    int arity, const char *context) {
  char buf[16];
  snprintf(buf, sizeof(buf), "%d", arity);
  term_t *n = make_const(ctx, name);
  term_t *a = make_const(ctx, buf);
  term_t *ind_args[2] = {n, a};
  term_t *ind = make_func(ctx, "/", ind_args, 2);
  throw_permission_error(ctx, "modify", "static_procedure", ind, context);
}

static void flatten_body(env_t *env, term_t *body, clause_t *c) {
  while (body->type == FUNC && strcmp(body->name, ",") == 0 &&
         body->arity == 2 && c->body_count < MAX_GOALS - 1) {
    c->body[c->body_count++] = deref(env, body->args[0]);
    body = deref(env, body->args[1]);
  }
  c->body[c->body_count++] = body;
}

static builtin_result_t builtin_assertz(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  if (ctx->db_count >= MAX_CLAUSES)
    return BUILTIN_FAIL;
  term_t *clause_raw = deref(env, goal->args[0]);
  term_t *head_raw =
      (clause_raw->type == FUNC && strcmp(clause_raw->name, ":-") == 0 &&
       clause_raw->arity == 2)
          ? deref(env, clause_raw->args[0])
          : clause_raw;
  if (head_raw->type != VAR) {
    int pa = (head_raw->type == FUNC) ? head_raw->arity : 0;
    if (is_static_procedure(ctx, head_raw->name, pa)) {
      throw_static_proc_error(ctx, head_raw->name, pa, "assertz/1");
      return BUILTIN_ERROR;
    }
  }
  ctx->alloc_permanent = true;
  term_t *arg = substitute(ctx, env, clause_raw);
  clause_t *c = &ctx->database[ctx->db_count];
  c->body_count = 0;
  if (arg->type == FUNC && strcmp(arg->name, ":-") == 0 && arg->arity == 2) {
    c->head = deref(env, arg->args[0]);
    flatten_body(env, deref(env, arg->args[1]), c);
  } else {
    c->head = arg;
  }
  ctx->alloc_permanent = false;
  c->source_file = -1;
  ctx->db_count++;
  ctx->db_dirty = true;
  return BUILTIN_OK;
}

static builtin_result_t builtin_asserta(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  if (ctx->db_count >= MAX_CLAUSES)
    return BUILTIN_FAIL;
  term_t *clause_raw = deref(env, goal->args[0]);
  term_t *head_raw =
      (clause_raw->type == FUNC && strcmp(clause_raw->name, ":-") == 0 &&
       clause_raw->arity == 2)
          ? deref(env, clause_raw->args[0])
          : clause_raw;
  if (head_raw->type != VAR) {
    int pa = (head_raw->type == FUNC) ? head_raw->arity : 0;
    if (is_static_procedure(ctx, head_raw->name, pa)) {
      throw_static_proc_error(ctx, head_raw->name, pa, "asserta/1");
      return BUILTIN_ERROR;
    }
  }
  for (int i = ctx->db_count; i > 0; i--)
    ctx->database[i] = ctx->database[i - 1];
  ctx->db_count++;
  ctx->alloc_permanent = true;
  term_t *arg = substitute(ctx, env, clause_raw);
  clause_t *c = &ctx->database[0];
  c->body_count = 0;
  if (arg->type == FUNC && strcmp(arg->name, ":-") == 0 && arg->arity == 2) {
    c->head = deref(env, arg->args[0]);
    flatten_body(env, deref(env, arg->args[1]), c);
  } else {
    c->head = arg;
  }
  c->source_file = -1;
  ctx->alloc_permanent = false;
  ctx->db_dirty = true;
  return BUILTIN_OK;
}

// build a conjunction term from a clause body array (for retract matching).
static term_t *body_to_term(trilog_ctx_t *ctx, term_t **body, int n) {
  if (n == 0)
    return make_const(ctx, "true");
  term_t *result = body[n - 1];
  for (int i = n - 2; i >= 0; i--) {
    term_t *args[2] = {body[i], result};
    result = make_func(ctx, ",", args, 2);
  }
  return result;
}

static builtin_result_t builtin_retract(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  term_t *arg = deref(env, goal->args[0]);
  bool has_body =
      (arg->type == FUNC && strcmp(arg->name, ":-") == 0 && arg->arity == 2);
  term_t *head_pat = has_body ? deref(env, arg->args[0]) : arg;
  term_t *body_pat = has_body ? deref(env, arg->args[1]) : NULL;
  if (head_pat->type != VAR) {
    int pa = (head_pat->type == FUNC) ? head_pat->arity : 0;
    if (is_static_procedure(ctx, head_pat->name, pa)) {
      throw_static_proc_error(ctx, head_pat->name, pa, "retract/1");
      return BUILTIN_ERROR;
    }
  }

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
      ctx->stats.retracts++;
// TODO: ugly
#if COMPACT_AFTER_RETRACTS > 0
      if (ctx->stats.retracts % COMPACT_AFTER_RETRACTS == 0)
        compact_perm_pool(ctx);
#endif
      return BUILTIN_OK;
    }
    env->count = ctx->bind_count = env_mark;
    ctx->term_pool_offset = trm_save;
  }
  return BUILTIN_FAIL;
}

static builtin_result_t builtin_retractall(trilog_ctx_t *ctx, term_t *goal,
                                           env_t *env) {
  term_t *head_pat = deref(env, goal->args[0]);
  if (head_pat->type != VAR) {
    int pa = (head_pat->type == FUNC) ? head_pat->arity : 0;
    if (is_static_procedure(ctx, head_pat->name, pa)) {
      throw_static_proc_error(ctx, head_pat->name, pa, "retractall/1");
      return BUILTIN_ERROR;
    }
  }
  int i = 0;
  int removed = 0;
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
      removed++;
    } else {
      i++;
    }
  }
  if (removed > 0) {
    ctx->stats.retracts += removed;
#if COMPACT_AFTER_RETRACTS > 0
    compact_perm_pool(ctx);
#endif
  }
  return BUILTIN_OK;
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

static term_t *array_to_list(trilog_ctx_t *ctx, term_t **arr, int n) {
  term_t *list = make_const(ctx, "[]");
  for (int i = n - 1; i >= 0; i--) {
    term_t *args[2] = {arr[i], list};
    list = make_func(ctx, ".", args, 2);
  }
  return list;
}

//****
//* sorting and reloading
//****

static builtin_result_t builtin_msort(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_sort(trilog_ctx_t *ctx, term_t *goal,
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

static builtin_result_t builtin_make(trilog_ctx_t *ctx, term_t *goal,
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
    trilog_load_file(ctx, snapshot[i]);

  io_writef(ctx, "%% make: reloaded %d file(s) (%d changed)\n", count, changed);
  return BUILTIN_OK;
}

static void register_dynamic_indicator(trilog_ctx_t *ctx, term_t *ind,
                                       env_t *env) {
  ind = deref(env, ind);
  if (ind->type == FUNC && strcmp(ind->name, ",") == 0 && ind->arity == 2) {
    register_dynamic_indicator(ctx, ind->args[0], env);
    register_dynamic_indicator(ctx, ind->args[1], env);
    return;
  }
  if (ind->type != FUNC || strcmp(ind->name, "/") != 0 || ind->arity != 2)
    return;
  term_t *n = deref(env, ind->args[0]);
  term_t *a = deref(env, ind->args[1]);
  const char *name = term_atom_str(n);
  int arity;
  if (!name || !term_as_int(a, &arity))
    return;
  if (is_declared_dynamic(ctx, name, arity))
    return;
  if (ctx->dynamic_pred_count >= MAX_DYNAMIC_PREDS)
    return;
  strncpy(ctx->dynamic_preds[ctx->dynamic_pred_count].name, name, MAX_NAME - 1);
  ctx->dynamic_preds[ctx->dynamic_pred_count].name[MAX_NAME - 1] = '\0';
  ctx->dynamic_preds[ctx->dynamic_pred_count].arity = arity;
  ctx->dynamic_pred_count++;
}

// dynamic/1: register predicate indicators as dynamic (modifiable at runtime)
static builtin_result_t builtin_dynamic(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  register_dynamic_indicator(ctx, deref(env, goal->args[0]), env);
  return BUILTIN_OK;
}

// abolish/1: remove all clauses for a predicate indicator name/arity
static builtin_result_t builtin_abolish(trilog_ctx_t *ctx, term_t *goal,
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

// consulted(-Ls): unify Ls with list of files currently tracked by make/0
static builtin_result_t builtin_consulted(trilog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  term_t *list = make_const(ctx, "[]");
  for (int i = ctx->make_file_count - 1; i >= 0; i--) {
    term_t *path = make_const(ctx, ctx->make_files[i].path);
    term_t *args[2] = {path, list};
    list = make_func(ctx, ".", args, 2);
  }
  return unify(ctx, deref(env, goal->args[0]), list, env) ? BUILTIN_OK
                                                          : BUILTIN_FAIL;
}

// unconsult(+File): remove all clauses loaded from File and drop it from
// make/0 tracking. fails if File is not currently consulted.
static builtin_result_t builtin_unconsult(trilog_ctx_t *ctx, term_t *goal,
                                          env_t *env) {
  term_t *arg = deref(env, goal->args[0]);
  if (arg->type == VAR) {
    throw_instantiation_error(ctx, "forget_file/1");
    return BUILTIN_ERROR;
  }
  const char *path = term_atom_str(arg);
  if (!path) {
    throw_type_error(ctx, "atom", arg, "unconsult/1");
    return BUILTIN_ERROR;
  }
  int file_idx = -1;
  for (int i = 0; i < ctx->make_file_count; i++) {
    if (strcmp(ctx->make_files[i].path, path) == 0) {
      file_idx = i;
      break;
    }
  }
  if (file_idx == -1)
    return BUILTIN_FAIL;
  int old_count = ctx->db_count;
  int dst = 0;
  for (int src = 0; src < ctx->db_count; src++) {
    if (ctx->database[src].source_file == file_idx)
      continue;
    ctx->database[dst] = ctx->database[src];
    if (ctx->database[dst].source_file > file_idx)
      ctx->database[dst].source_file--;
    dst++;
  }
  ctx->db_count = dst;
  ctx->db_dirty = true;
  for (int i = file_idx; i < ctx->make_file_count - 1; i++)
    ctx->make_files[i] = ctx->make_files[i + 1];
  ctx->make_file_count--;
  int removed = old_count - dst;
  if (removed > 0) {
    ctx->stats.retracts += removed;
#if COMPACT_AFTER_RETRACTS > 0
    compact_perm_pool(ctx);
#endif
  }
  return BUILTIN_OK;
}

// current_prolog_flag/2
static builtin_result_t builtin_current_prolog_flag(trilog_ctx_t *ctx,
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

//****
//* dispatch table
//****

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
    {"[]", 0, builtin_nil_goal},
    {".", 2, builtin_list_goal},
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
    {"consulted", 1, builtin_consulted},
    {"unconsult", 1, builtin_unconsult},
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

builtin_result_t try_builtin(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
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

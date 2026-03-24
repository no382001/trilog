#include "platform_impl.h"

//****
//* arithmetic operator table
//****

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
  // iso: result has sign of divisor
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

//****
//* arithmetic evaluator
//****

bool eval_arith(trilog_ctx_t *ctx, term_t *t, env_t *env, int *result,
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

  // unknown functor or non-numeric atom: type_error(evaluable, name/arity)
  if (t->type == CONST || t->type == FUNC) {
    int arity = (t->type == FUNC) ? t->arity : 0;
    throw_evaluable_error(ctx, t->name, arity, pred);
  } else {
    throw_type_error(ctx, "evaluable", t, pred);
  }
  return false;
}

//****
//* arithmetic builtins
//****

builtin_result_t builtin_is(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
  int result;
  if (!eval_arith(ctx, goal->args[1], env, &result, "is/2"))
    return ctx->has_runtime_error ? BUILTIN_ERROR : BUILTIN_FAIL;
  char buf[32];
  snprintf(buf, sizeof(buf), "%d", result);
  term_t *result_term = make_const(ctx, buf);
  return unify(ctx, goal->args[0], result_term, env) ? BUILTIN_OK
                                                     : BUILTIN_FAIL;
}

#define ARITH_CMP_BUILTIN(name, op, pred)                                      \
  builtin_result_t name(trilog_ctx_t *ctx, term_t *goal, env_t *env) {         \
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

builtin_result_t builtin_succ(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
  term_t *x = deref(env, goal->args[0]);
  term_t *s = deref(env, goal->args[1]);
  int ix, is_val;
  bool x_int = term_as_int(x, &ix);
  bool s_int = term_as_int(s, &is_val);

  if (x_int) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", ix + 1);
    return unify(ctx, goal->args[1], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  if (s_int && is_val > 0) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", is_val - 1);
    return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  return BUILTIN_FAIL;
}

builtin_result_t builtin_plus(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
  term_t *a = deref(env, goal->args[0]);
  term_t *b = deref(env, goal->args[1]);
  term_t *c = deref(env, goal->args[2]);
  int ia, ib, ic;
  bool a_int = term_as_int(a, &ia);
  bool b_int = term_as_int(b, &ib);
  bool c_int = term_as_int(c, &ic);

  char buf[32];
  if (a_int && b_int) {
    snprintf(buf, sizeof(buf), "%d", ia + ib);
    return unify(ctx, goal->args[2], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  if (a_int && c_int) {
    snprintf(buf, sizeof(buf), "%d", ic - ia);
    return unify(ctx, goal->args[1], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  if (b_int && c_int) {
    snprintf(buf, sizeof(buf), "%d", ic - ib);
    return unify(ctx, goal->args[0], make_const(ctx, buf), env) ? BUILTIN_OK
                                                                : BUILTIN_FAIL;
  }
  return BUILTIN_FAIL;
}

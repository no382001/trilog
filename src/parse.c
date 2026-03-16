#include "platform_impl.h"

void parse_error(prolog_ctx_t *ctx, const char *fmt, ...) {
  if (ctx->error.has_error)
    return;

  ctx->error.has_error = true;
  ctx->error.line = ctx->input_line;
  ctx->error.column = (int)(ctx->input_ptr - ctx->input_start) + 1;

  va_list args;
  va_start(args, fmt);
  vsnprintf(ctx->error.message, MAX_ERROR_MSG, fmt, args);
  va_end(args);
}

void parse_error_clear(prolog_ctx_t *ctx) {
  ctx->error.has_error = false;
  ctx->error.error_is_eof = false;
  ctx->error.message[0] = '\0';
  ctx->error.line = 0;
  ctx->error.column = 0;
}

static void parse_error_eof(prolog_ctx_t *ctx) {
  if (ctx->error.has_error)
    return;
  ctx->error.has_error = true;
  ctx->error.error_is_eof = true;
  strncpy(ctx->error.message, "end_of_file", MAX_ERROR_MSG - 1);
  ctx->error.message[MAX_ERROR_MSG - 1] = '\0';
  ctx->error.line = ctx->input_line;
  ctx->error.column = (int)(ctx->input_ptr - ctx->input_start) + 1;
}

bool parse_has_error(prolog_ctx_t *ctx) { return ctx->error.has_error; }

void ctx_runtime_error(prolog_ctx_t *ctx, const char *fmt, ...) {
  if (ctx->has_runtime_error)
    return; // keep first error
  ctx->has_runtime_error = true;
  va_list args;
  va_start(args, fmt);
  vsnprintf(ctx->runtime_error, MAX_ERROR_MSG, fmt, args);
  va_end(args);
}

void parse_error_print(prolog_ctx_t *ctx) {
  if (!ctx->error.has_error)
    return;

  if (ctx->input_start && ctx->error.column > 0) {
    // show the offending line and point to the error
    io_writef_err(ctx, "  %s\n", ctx->input_start);
    io_writef_err(ctx, "  %*s^\n", ctx->error.column - 1, "");
    io_writef_err(ctx, "error: %s\n", ctx->error.message);
  } else {
    // fallback for non-interactive / no context
    io_writef_err(ctx, "error: line %d, column %d: %s\n", ctx->error.line,
                  ctx->error.column, ctx->error.message);
  }
}

void skip_ws(prolog_ctx_t *ctx) {
  assert(ctx != NULL && "Context is NULL");
  assert(ctx->input_ptr != NULL && "Input pointer is NULL");
  while (*ctx->input_ptr) {
    if (isspace((unsigned char)*ctx->input_ptr)) {
      ctx->input_ptr++;
    } else if (ctx->input_ptr[0] == '/' && ctx->input_ptr[1] == '*') {
      ctx->input_ptr += 2;
      while (*ctx->input_ptr &&
             !(ctx->input_ptr[0] == '*' && ctx->input_ptr[1] == '/'))
        ctx->input_ptr++;
      if (*ctx->input_ptr)
        ctx->input_ptr += 2;
    } else {
      break;
    }
  }
}

typedef struct {
  const char *text;
  int len;
  bool is_keyword; // needs non-alnum check after
} op_pattern_t;

typedef struct {
  const char *op;
  int precedence;
} op_prec_t;

static term_t *parse_primary(prolog_ctx_t *ctx);
static term_t *parse_infix(prolog_ctx_t *ctx, term_t *left, int min_prec);
static term_t *parse_arg(prolog_ctx_t *ctx);

static const op_prec_t precedence_table[] = {
    {"*", 40},   {"/", 40},    {"//", 40},  {"mod", 40},  {">>", 40},
    {"<<", 40},  {"/\\", 40},  {"xor", 40}, {"+", 30},    {"-", 30},
    {"\\/", 30}, {"<", 20},    {">", 20},   {"=<", 20},   {">=", 20},
    {"=:=", 20}, {"=\\=", 20}, {"==", 20},  {"\\==", 20}, {"@<", 20},
    {"@>", 20},  {"@=<", 20},  {"@>=", 20}, {"is", 10},   {"=", 10},
    {"\\=", 10}, {"..", 10},   {"->", 7},   {";", 5},     {"^", 6},
    {",", 9},    {NULL, 0}};

// ordered longest-first to avoid prefix conflicts
static const op_pattern_t op_patterns[] = {
    {"=:=", 3, false}, {"=\\=", 3, false}, {"=..", 3, false}, {"mod", 3, true},
    {"xor", 3, true},  {"\\==", 3, false}, {"@=<", 3, false}, {"@>=", 3, false},
    {"==", 2, false},  {"@<", 2, false},   {"@>", 2, false},  {"->", 2, false},
    {"\\=", 2, false}, {"\\/", 2, false},  {"=<", 2, false},  {">=", 2, false},
    {">>", 2, false},  {"<<", 2, false},   {"//", 2, false},  {"/\\", 2, false},
    {"is", 2, true},   {"+", 1, false},    {"*", 1, false},   {"/", 1, false},
    {"<", 1, false},   {">", 1, false},    {"=", 1, false},   {"-", 1, false},
    {";", 1, false},   {"^", 1, false},    {",", 1, false},   {NULL, 0, false}};

static int get_precedence(const char *op) {
  for (const op_prec_t *p = precedence_table; p->op; p++) {
    if (strcmp(op, p->op) == 0)
      return p->precedence;
  }
  return 0;
}

static int try_parse_op(prolog_ctx_t *ctx, char *op_out, int max_len) {
  char *p = ctx->input_ptr;

  for (const op_pattern_t *pat = op_patterns; pat->text; pat++) {
    if (strncmp(p, pat->text, pat->len) != 0)
      continue;

    // keyword operators need non-alnum after
    if (pat->is_keyword) {
      char next = p[pat->len];
      if (isalnum(next) || next == '_')
        continue;
    }

    strncpy(op_out, pat->text, max_len);
    op_out[max_len - 1] = '\0';
    return pat->len;
  }

  return 0;
}

term_t *parse_list(prolog_ctx_t *ctx) {
  assert(ctx != NULL && "Context is NULL");
  assert(ctx->input_ptr != NULL && "Input pointer is NULL");

  if (*ctx->input_ptr != '[') {
    parse_error(ctx, "expected '[' at start of list");
    return NULL;
  }

  ctx->input_ptr++;
  skip_ws(ctx);

  if (*ctx->input_ptr == ']') {
    ctx->input_ptr++;
    return make_const(ctx, "[]");
  }

  term_t *elements[MAX_LIST_LIT]; // scratch buffer
  int count = 0;
  term_t *tail = NULL;

  elements[count] = parse_arg(ctx);
  if (!elements[count]) {
    if (*ctx->input_ptr == '\0' && !parse_has_error(ctx))
      parse_error_eof(ctx);
    else if (!parse_has_error(ctx))
      parse_error(ctx, "failed to parse list element");
    return NULL;
  }
  count++;
  skip_ws(ctx);

  while (*ctx->input_ptr == ',' || *ctx->input_ptr == '|') {
    if (*ctx->input_ptr == '|') {
      ctx->input_ptr++;
      skip_ws(ctx);
      tail = parse_arg(ctx);
      if (!tail) {
        if (*ctx->input_ptr == '\0' && !parse_has_error(ctx))
          parse_error_eof(ctx);
        else if (!parse_has_error(ctx))
          parse_error(ctx, "failed to parse list tail after '|'");
        return NULL;
      }
      skip_ws(ctx);
      break;
    }
    ctx->input_ptr++;
    skip_ws(ctx);

    if (count >= MAX_LIST_LIT) {
      parse_error(ctx, "too many list elements (max %d)", MAX_LIST_LIT);
      return NULL;
    }

    elements[count] = parse_arg(ctx);
    if (!elements[count]) {
      if (*ctx->input_ptr == '\0' && !parse_has_error(ctx))
        parse_error_eof(ctx);
      else if (!parse_has_error(ctx))
        parse_error(ctx, "failed to parse list element");
      return NULL;
    }
    count++;
    skip_ws(ctx);
  }

  if (*ctx->input_ptr != ']') {
    if (*ctx->input_ptr == '\0')
      parse_error_eof(ctx);
    else
      parse_error(ctx, "expected ']' to close list, got '%c'", *ctx->input_ptr);
    return NULL;
  }
  ctx->input_ptr++;

  term_t *result = tail ? tail : make_const(ctx, "[]");
  for (int i = count - 1; i >= 0; i--) {
    term_t *args[2] = {elements[i], result};
    result = make_func(ctx, ".", args, 2);
  }

  return result;
}

static term_t *parse_primary(prolog_ctx_t *ctx) {
  assert(ctx != NULL && "Context is NULL");
  assert(ctx->input_ptr != NULL && "Input pointer is NULL");

  if (parse_has_error(ctx))
    return NULL;

  skip_ws(ctx);

  debug(ctx, "DEBUG parse_primary: next char = '%c'\n",
        *ctx->input_ptr ? *ctx->input_ptr : '?');

  if (*ctx->input_ptr == '\0') {
    return NULL; // end of input, not necessarily an error
  }

  // parenthesized expression: (a) or (a, b, ...) conjunction
  if (*ctx->input_ptr == '(') {
    ctx->input_ptr++;
    skip_ws(ctx);
    term_t *inner = parse_term(ctx);
    if (!inner) {
      if (*ctx->input_ptr == '\0' && !parse_has_error(ctx))
        parse_error_eof(ctx);
      else if (!parse_has_error(ctx))
        parse_error(ctx, "expected expression inside parentheses");
      return NULL;
    }
    skip_ws(ctx);
    // ',' is now an infix operator, so parse_term above already consumed
    // any conjunction chain inside the parens.
    if (*ctx->input_ptr != ')') {
      if (*ctx->input_ptr == '\0')
        parse_error_eof(ctx);
      else
        parse_error(ctx, "expected ')' after expression, got '%c'",
                    *ctx->input_ptr);
      return NULL;
    }
    ctx->input_ptr++;
    return inner;
  }

  if (*ctx->input_ptr == '[')
    return parse_list(ctx);

  if (*ctx->input_ptr == '\'') {
    ctx->input_ptr++; // skip opening quote
    char name[MAX_NAME];
    int i = 0;
    bool closed = false;
    while (*ctx->input_ptr) {
      if (*ctx->input_ptr == '\'') {
        if (ctx->input_ptr[1] == '\'') { // '' is escaped single-quote
          ctx->input_ptr += 2;
          if (i < MAX_NAME - 1)
            name[i++] = '\'';
        } else {
          ctx->input_ptr++; // closing quote
          closed = true;
          break;
        }
      } else if (*ctx->input_ptr == '\\' && ctx->input_ptr[1]) {
        // ISO 6.4.2.1 escape sequences
        ctx->input_ptr++;
        char esc = *ctx->input_ptr++;
        if (i < MAX_NAME - 1) {
          switch (esc) {
          case '\\':
            name[i++] = '\\';
            break;
          case 'n':
            name[i++] = '\n';
            break;
          case 't':
            name[i++] = '\t';
            break;
          case 'a':
            name[i++] = '\a';
            break;
          case 'b':
            name[i++] = '\b';
            break;
          case 'r':
            name[i++] = '\r';
            break;
          case 'f':
            name[i++] = '\f';
            break;
          default:
            name[i++] = esc;
            break;
          }
        }
      } else {
        if (i < MAX_NAME - 1)
          name[i++] = *ctx->input_ptr;
        ctx->input_ptr++;
      }
    }
    name[i] = '\0';

    if (!closed) {
      parse_error_eof(ctx);
      return NULL;
    }

    // quoted atom followed by '(' is a functor call (ISO 6.3.3)
    skip_ws(ctx);
    if (*ctx->input_ptr == '(') {
      ctx->input_ptr++;
      term_t *args[MAX_ARGS];
      int arity = 0;
      skip_ws(ctx);
      if (*ctx->input_ptr != ')') {
        do {
          skip_ws(ctx);
          if (arity >= MAX_ARGS) {
            parse_error(ctx, "too many arguments (max %d)", MAX_ARGS);
            return NULL;
          }
          args[arity] = parse_arg(ctx);
          if (!args[arity]) {
            if (!parse_has_error(ctx)) {
              if (*ctx->input_ptr == '\0')
                parse_error_eof(ctx);
              else
                parse_error(ctx, "failed to parse argument %d", arity + 1);
            }
            return NULL;
          }
          arity++;
          skip_ws(ctx);
        } while (*ctx->input_ptr == ',' && ctx->input_ptr++);
      }
      skip_ws(ctx);
      if (*ctx->input_ptr != ')') {
        if (*ctx->input_ptr == '\0')
          parse_error_eof(ctx);
        else
          parse_error(ctx, "expected ')' after arguments, got '%c'",
                      *ctx->input_ptr);
        return NULL;
      }
      ctx->input_ptr++;
      return make_func(ctx, name, args, arity);
    }

    return make_const(ctx, name);
  }

  if (*ctx->input_ptr == '\"') {
    ctx->input_ptr++;           // skip opening quote
    char str_buf[MAX_NAME * 4]; // allow longer strings
    size_t i = 0;

    while (*ctx->input_ptr && *ctx->input_ptr != '\"') {
      if (i >= sizeof(str_buf) - 1) {
        parse_error(ctx, "string too long (max %d chars)",
                    (int)sizeof(str_buf) - 1);
        return NULL;
      }

      // escape sequences
      if (*ctx->input_ptr == '\\' && ctx->input_ptr[1]) {
        ctx->input_ptr++;
        char decoded = *ctx->input_ptr;
        for (const str_escape_t *e = STR_ESCAPES; e->raw; e++) {
          if (e->seq == *ctx->input_ptr) {
            decoded = e->raw;
            break;
          }
        }
        str_buf[i++] = decoded;
        ctx->input_ptr++;
      } else {
        str_buf[i++] = *ctx->input_ptr++;
      }
    }

    if (*ctx->input_ptr != '\"') {
      parse_error(ctx, "unterminated string literal");
      return NULL;
    }
    ctx->input_ptr++; // skip closing quote
    str_buf[i] = '\0';

    return make_string(ctx, str_buf);
  }

  char name[MAX_NAME] = {0};
  int i = 0;

  if (*ctx->input_ptr == '!') {
    name[i++] = *ctx->input_ptr++;
  } else if (isdigit(*ctx->input_ptr) ||
             (*ctx->input_ptr == '-' && isdigit(ctx->input_ptr[1]))) {
    if (*ctx->input_ptr == '-')
      name[i++] = *ctx->input_ptr++;
    // 0'c character code notation
    if (ctx->input_ptr[0] == '0' && ctx->input_ptr[1] == '\'') {
      ctx->input_ptr += 2;
      unsigned char ch = (unsigned char)*ctx->input_ptr;
      if (ch == '\\' && ctx->input_ptr[1]) {
        ctx->input_ptr++;
        switch (*ctx->input_ptr) {
        case 'n':
          ch = '\n';
          break;
        case 't':
          ch = '\t';
          break;
        case 'r':
          ch = '\r';
          break;
        case '\\':
          ch = '\\';
          break;
        case '\'':
          ch = '\'';
          break;
        default:
          ch = (unsigned char)*ctx->input_ptr;
          break;
        }
      }
      ctx->input_ptr++;
      snprintf(name + i, MAX_NAME - i, "%d", (int)ch);
      i = strlen(name);
    } else {
      while (isdigit(*ctx->input_ptr)) {
        if (i >= MAX_NAME - 1) {
          parse_error(ctx, "number too long (max %d digits)", MAX_NAME - 1);
          return NULL;
        }
        name[i++] = *ctx->input_ptr++;
      }
    }
  } else if (isalpha(*ctx->input_ptr) || *ctx->input_ptr == '_') {
    while (isalnum(*ctx->input_ptr) || *ctx->input_ptr == '_') {
      if (i >= MAX_NAME - 1) {
        parse_error(ctx, "name too long (max %d chars)", MAX_NAME - 1);
        return NULL;
      }
      name[i++] = *ctx->input_ptr++;
    }
  } else if (*ctx->input_ptr == '\\') {
    if (ctx->input_ptr[1] == '+') {
      ctx->input_ptr += 2;
      skip_ws(ctx);
      term_t *inner = parse_arg(ctx); // stop before ',' like functor args
      if (!inner) {
        if (*ctx->input_ptr == '\0' && !parse_has_error(ctx))
          parse_error_eof(ctx);
        else if (!parse_has_error(ctx))
          parse_error(ctx, "expected term after '\\+'");
        return NULL;
      }
      term_t *args[1] = {inner};
      return make_func(ctx, "\\+", args, 1);
    } else {
      // unary bitwise complement: \Expr
      ctx->input_ptr++;
      skip_ws(ctx);
      term_t *inner = parse_primary(ctx);
      if (!inner) {
        if (*ctx->input_ptr == '\0' && !parse_has_error(ctx))
          parse_error_eof(ctx);
        else if (!parse_has_error(ctx))
          parse_error(ctx, "expected term after '\\'");
        return NULL;
      }
      term_t *args[1] = {inner};
      return make_func(ctx, "\\", args, 1);
    }
  } else {
    // Not a valid start of term
    return NULL;
  }

  debug(ctx, "DEBUG parse_primary: parsed name = '%s'\n", name);

  skip_ws(ctx);

  if (*ctx->input_ptr == '(') {
    ctx->input_ptr++;
    term_t *args[MAX_ARGS];
    int arity = 0;

    skip_ws(ctx);
    if (*ctx->input_ptr != ')') {
      do {
        skip_ws(ctx);
        if (arity >= MAX_ARGS) {
          parse_error(ctx, "too many arguments (max %d)", MAX_ARGS);
          return NULL;
        }
        args[arity] = parse_arg(ctx);
        if (!args[arity]) {
          if (!parse_has_error(ctx)) {
            if (*ctx->input_ptr == '\0')
              parse_error_eof(ctx);
            else
              parse_error(ctx, "failed to parse argument %d", arity + 1);
          }
          return NULL;
        }
        arity++;
        skip_ws(ctx);
      } while (*ctx->input_ptr == ',' && ctx->input_ptr++);
    }
    skip_ws(ctx);

    if (*ctx->input_ptr != ')') {
      if (*ctx->input_ptr == '\0')
        parse_error_eof(ctx);
      else
        parse_error(ctx, "expected ')' after arguments, got '%c'",
                    *ctx->input_ptr);
      return NULL;
    }
    ctx->input_ptr++;

    debug(ctx, "DEBUG parse_primary: functor %s/%d\n", name, arity);
    return make_func(ctx, name, args, arity);
  }

  if (isupper(name[0]) || name[0] == '_') {
    debug(ctx, "DEBUG parse_primary: variable %s\n", name);
    // anonymous variable: each _ is distinct; never shared.
    if (name[0] == '_' && name[1] == '\0') {
      return make_var(ctx, "_", ctx->var_counter++);
    }
    // named variable: share var_id within the clause/query.
    const char *iname = intern_name(ctx, name);
    for (int i = 0; i < ctx->clause_var_count; i++) {
      if (ctx->clause_vars[i].name == iname)
        return make_var(ctx, iname, ctx->clause_vars[i].var_id);
    }
    assert(ctx->clause_var_count < MAX_CLAUSE_VARS &&
           "Too many variables in clause");
    int vid = ctx->var_counter++;
    ctx->clause_vars[ctx->clause_var_count].name = iname;
    ctx->clause_vars[ctx->clause_var_count].var_id = vid;
    ctx->clause_var_count++;
    return make_var(ctx, iname, vid);
  }
  debug(ctx, "DEBUG parse_primary: constant %s\n", name);
  return make_const(ctx, name);
}

static term_t *parse_infix(prolog_ctx_t *ctx, term_t *left, int min_prec) {
  while (1) {
    skip_ws(ctx);

    char op[8] = {0};
    int op_len = try_parse_op(ctx, op, sizeof(op));

    if (op_len == 0)
      return left;

    int prec = get_precedence(op);
    if (prec < min_prec)
      return left;

    ctx->input_ptr += op_len;
    skip_ws(ctx);

    term_t *right = parse_primary(ctx);
    if (!right) {
      if (*ctx->input_ptr == '\0' && !parse_has_error(ctx))
        parse_error_eof(ctx);
      else if (!parse_has_error(ctx))
        parse_error(ctx, "expected term after '%s'", op);
      return NULL;
    }

    // Look ahead for higher precedence operator
    skip_ws(ctx);
    char next_op[8] = {0};
    int next_len = try_parse_op(ctx, next_op, sizeof(next_op));

    while (next_len > 0 && get_precedence(next_op) > prec) {
      right = parse_infix(ctx, right, get_precedence(next_op));
      if (!right)
        return NULL;
      skip_ws(ctx);
      next_len = try_parse_op(ctx, next_op, sizeof(next_op));
    }

    term_t *args[2] = {left, right};
    left = make_func(ctx, op, args, 2);
  }
}

term_t *parse_term(prolog_ctx_t *ctx) {
  assert(ctx != NULL && "Context is NULL");
  assert(ctx->input_ptr != NULL && "Input pointer is NULL");

  if (parse_has_error(ctx))
    return NULL;

  term_t *left = parse_primary(ctx);
  if (!left)
    return NULL;

  return parse_infix(ctx, left, 0);
}

// parse_arg: parses a functor argument or list element.
// Stops before ',' so functor args and list elements are delimited correctly.
static term_t *parse_arg(prolog_ctx_t *ctx) {
  term_t *left = parse_primary(ctx);
  if (!left)
    return NULL;
  return parse_infix(ctx, left, 10); // 10 > ',' prec (9), so comma stops arg
}

void strip_line_comment(char *line) {
  bool in_dq = false, in_sq = false;
  for (char *p = line; *p; p++) {
    if (in_dq) {
      if (*p == '\\' && *(p + 1))
        p++;
      else if (*p == '"')
        in_dq = false;
    } else if (in_sq) {
      if (*p == '\\' && *(p + 1))
        p++; // backslash escape (e.g. \')
      else if (*p == '\'' && *(p + 1) == '\'')
        p++; // escaped ''
      else if (*p == '\'')
        in_sq = false;
    } else {
      if (*p == '"')
        in_dq = true;
      else if (*p == '\'')
        in_sq = true;
      else if (*p == '%') {
        *p = '\0';
        break;
      }
    }
  }
}

bool has_complete_clause(const char *buf) {
  bool in_dq = false, in_sq = false;
  int depth = 0;
  for (const char *p = buf; *p; p++) {
    if (in_dq) {
      if (*p == '\\' && *(p + 1))
        p++;
      else if (*p == '"')
        in_dq = false;
    } else if (in_sq) {
      if (*p == '\\' && *(p + 1))
        p++; // backslash escape (e.g. \')
      else if (*p == '\'' && *(p + 1) == '\'')
        p++; // doubled-quote escape ''
      else if (*p == '\'')
        in_sq = false;
    } else {
      if (*p == '"') {
        in_dq = true;
      } else if (*p == '\'') {
        in_sq = true;
      } else if (*p == '(' || *p == '[') {
        depth++;
      } else if (*p == ')' || *p == ']') {
        depth--;
      } else if (*p == '.' && depth == 0) {
        char next = *(p + 1);
        if (next == '\0' || isspace((unsigned char)next))
          return true;
      }
    }
  }
  return false;
}

static bool parse_goals(prolog_ctx_t *ctx, char *query, goal_stmt_t *goals) {
  parse_error_clear(ctx);
  ctx->has_runtime_error = false;
  ctx->input_ptr = query;
  ctx->input_start = query;
  ctx->clause_var_count = 0;

  // collect terms into a temporary stack buffer, then allocate from pool
  term_t *tmp[MAX_GOALS];
  int n = 0;
  do {
    skip_ws(ctx);
    term_t *g = parse_term(ctx);
    if (!g) {
      if (parse_has_error(ctx)) {
        parse_error_print(ctx);
        return false;
      }
      break;
    }
    if (n < MAX_GOALS)
      tmp[n++] = g;
    skip_ws(ctx);
  } while (*ctx->input_ptr == ',' && ctx->input_ptr++);

  if (n == 0) {
    io_writef_err(ctx, "Error: empty query\n");
    return false;
  }

  // check for trailing unparsed input (skip optional trailing '.')
  skip_ws(ctx);
  if (*ctx->input_ptr == '.')
    ctx->input_ptr++;
  skip_ws(ctx);
  if (*ctx->input_ptr != '\0') {
    parse_error(ctx, "unexpected token: '%c'", *ctx->input_ptr);
    parse_error_print(ctx);
    return false;
  }

  *goals = goals_alloc(ctx, n);
  for (int i = 0; i < n; i++)
    goals->goals[goals->count++] = tmp[i];
  return true;
}

bool prolog_exec_query(prolog_ctx_t *ctx, char *query) {
  int term_mark = ctx->term_pool_offset;
  int string_mark = ctx->string_pool_offset;
  int db_mark = ctx->db_count;

  goal_stmt_t goals = {0};
  if (!parse_goals(ctx, query, &goals))
    return false;

  ctx->bind_count = 0;
  env_t env = {.bindings = ctx->bindings, .count = 0};
  bool ok = solve(ctx, &goals, &env);

  if (ctx->has_runtime_error) {
    io_write_str(ctx, "Unhandled exception: ");
    if (ctx->thrown_ball) {
      env_t err_env = {.bindings = ctx->bindings, .count = 0};
      io_write_term_quoted(ctx, ctx->thrown_ball, &err_env);
    } else {
      io_write_str(ctx, ctx->runtime_error);
    }
    io_write_str(ctx, "\n");
    ctx->has_runtime_error = false;
    ok = false;
  } else if (ok) {
    print_bindings(ctx, &env);
    io_write_str(ctx, "\n");
  } else {
    io_write_str(ctx, "false\n");
  }

  // restore pools if no new clauses were added
  // (clauses added via include must keep their terms)
  if (ctx->db_count == db_mark) {
    ctx->term_pool_offset = term_mark;
    ctx->string_pool_offset = string_mark;
  }
  return ok;
}

// parse and run a query, calling cb for each solution (no printing).
// returns true if at least one solution was found.
bool prolog_exec_query_multi(prolog_ctx_t *ctx, char *query,
                             solution_callback_t cb, void *ud) {
  int term_mark = ctx->term_pool_offset;
  int string_mark = ctx->string_pool_offset;
  int db_mark = ctx->db_count;

  goal_stmt_t goals = {0};
  if (!parse_goals(ctx, query, &goals))
    return false;

  ctx->bind_count = 0;
  env_t env = {.bindings = ctx->bindings, .count = 0};
  bool found = solve_all(ctx, &goals, &env, cb, ud);

  if (ctx->has_runtime_error) {
    io_write_str(ctx, "Unhandled exception: ");
    if (ctx->thrown_ball) {
      env_t err_env = {.bindings = ctx->bindings, .count = 0};
      io_write_term_quoted(ctx, ctx->thrown_ball, &err_env);
    } else {
      io_write_str(ctx, ctx->runtime_error);
    }
    io_write_str(ctx, "\n");
    // leave has_runtime_error set so the caller can suppress "false"
    found = false;
  }

  if (ctx->db_count == db_mark) {
    ctx->term_pool_offset = term_mark;
    ctx->string_pool_offset = string_mark;
  }
  return found;
}

static void exec_directive(prolog_ctx_t *ctx, char *buf) {
  prolog_exec_query(ctx, buf + 2); // skip "?-" or ":-"
}

// accumulate one trimmed line into clause[]. if a complete clause is ready,
// dispatch it and reset. returns false on parse error.
static bool process_clause_line(prolog_ctx_t *ctx, char *clause, size_t sz,
                                const char *trimmed) {
  if (*trimmed == '\0' && clause[0] == '\0')
    return true;
  if (clause[0] != '\0' && *trimmed != '\0')
    strncat(clause, " ", sz - strlen(clause) - 1);
  strncat(clause, trimmed, sz - strlen(clause) - 1);

  if (!has_complete_clause(clause))
    return true;

  ctx->input_line++;
  if (strncmp(clause, "?-", 2) == 0 || strncmp(clause, ":-", 2) == 0)
    exec_directive(ctx, clause);
  else
    parse_clause(ctx, clause);
  clause[0] = '\0';
  return !parse_has_error(ctx);
}

static bool load_clauses_from_fp(prolog_ctx_t *ctx, void *f,
                                 const char *label) {
  char line[1024];
  char clause[16384] = {0};

  while (io_file_read_line(ctx, f, line, sizeof(line))) {
    line[strcspn(line, "\n")] = 0;
    strip_line_comment(line);
    char *trimmed = line;
    while (isspace((unsigned char)*trimmed))
      trimmed++;
    if (!process_clause_line(ctx, clause, sizeof(clause), trimmed))
      return false;
  }

  char *p = clause;
  while (isspace((unsigned char)*p))
    p++;
  if (*p != '\0')
    io_writef_err(ctx, "Warning: unterminated clause at end of '%s'\n", label);
  return true;
}

bool prolog_load_file(prolog_ctx_t *ctx, const char *filename) {
  void *f = io_file_open(ctx, filename, "r");
  if (!f) {
    io_writef_err(ctx, "Error: cannot open file '%s'\n", filename);
    return false;
  }

  // track top-level files for make/0
  if (ctx->include_depth == 0) {
    bool already_tracked = false;
    for (int i = 0; i < ctx->make_file_count; i++) {
      if (strcmp(ctx->make_files[i].path, filename) == 0) {
        already_tracked = true;
        break;
      }
    }
    if (!already_tracked) {
      if (ctx->make_file_count == 0) {
        // first file ever (or first after a make reset): snapshot state
        ctx->make_db_mark = ctx->db_count;
        ctx->make_term_mark = ctx->term_pool_offset;
        ctx->make_string_mark = ctx->string_pool_offset;
      }
      if (ctx->make_file_count < MAX_MAKE_FILES) {
        int idx = ctx->make_file_count++;
        strncpy(ctx->make_files[idx].path, filename, MAX_FILE_PATH - 1);
        ctx->make_files[idx].path[MAX_FILE_PATH - 1] = '\0';
        ctx->make_files[idx].mtime = io_file_mtime(ctx, filename);
      }
    }
  }

  ctx->include_depth++;

  // set load_dir to this file's directory so nested includes resolve correctly
  char old_load_dir[MAX_FILE_PATH];
  strncpy(old_load_dir, ctx->load_dir, sizeof(old_load_dir) - 1);
  old_load_dir[sizeof(old_load_dir) - 1] = '\0';
  const char *last_slash = strrchr(filename, '/');
  if (last_slash) {
    size_t len = (size_t)(last_slash - filename);
    if (len >= sizeof(ctx->load_dir))
      len = sizeof(ctx->load_dir) - 1;
    strncpy(ctx->load_dir, filename, len);
    ctx->load_dir[len] = '\0';
  }

  bool ok = load_clauses_from_fp(ctx, f, filename);

  strncpy(ctx->load_dir, old_load_dir, sizeof(ctx->load_dir) - 1);
  io_file_close(ctx, f);
  ctx->include_depth--;
  return ok;
}

bool prolog_load_string(prolog_ctx_t *ctx, const char *src) {
  char line[1024];
  char clause[16384] = {0};
  ctx->include_depth++; // not tracked for make/0

  while (*src) {
    int i = 0;
    while (*src && *src != '\n' && i < (int)sizeof(line) - 1)
      line[i++] = *src++;
    if (*src == '\n')
      src++;
    line[i] = '\0';

    strip_line_comment(line);
    char *trimmed = line;
    while (isspace((unsigned char)*trimmed))
      trimmed++;
    if (!process_clause_line(ctx, clause, sizeof(clause), trimmed)) {
      ctx->include_depth--;
      return false;
    }
  }

  ctx->include_depth--;
  return true;
}

void parse_clause(prolog_ctx_t *ctx, char *line) {
  assert(ctx != NULL && "Context is NULL");
  assert(line != NULL && "Line cannot be NULL");

  parse_error_clear(ctx);
  ctx->input_ptr = line;
  ctx->input_start = line;
  ctx->clause_var_count = 0;

  if (ctx->db_count >= MAX_CLAUSES) {
    parse_error(ctx, "database full (max %d clauses)", MAX_CLAUSES);
    parse_error_print(ctx);
    return;
  }

  clause_t *c = &ctx->database[ctx->db_count];
  debug(ctx, "=== Parsing clause ===\n");

  ctx->alloc_permanent = true;
  c->head = parse_term(ctx);
  if (!c->head) {
    ctx->alloc_permanent = false;
    if (!parse_has_error(ctx)) {
      parse_error(ctx, "failed to parse clause head");
    }
    parse_error_print(ctx);
    return;
  }
  c->body_count = 0;
  c->body = NULL;

  skip_ws(ctx);
  if (ctx->input_ptr[0] == ':' && ctx->input_ptr[1] == '-') {
    ctx->input_ptr += 2;
    debug(ctx, "=== Parsing body ===\n");

    // collect body goals into a temp stack buffer, then alloc from perm pool
    term_t *tmp[MAX_GOALS];
    int n = 0;
    do {
      skip_ws(ctx);
      term_t *g = parse_term(ctx);
      if (!g) {
        if (parse_has_error(ctx)) {
          ctx->alloc_permanent = false;
          parse_error_print(ctx);
          return;
        }
        break;
      }
      if (n >= MAX_GOALS) {
        ctx->alloc_permanent = false;
        parse_error(ctx, "too many goals in clause body (max %d)", MAX_GOALS);
        parse_error_print(ctx);
        return;
      }
      tmp[n++] = g;
      skip_ws(ctx);
    } while (*ctx->input_ptr == ',' && ctx->input_ptr++);

    if (n > 0) {
      c->body = (term_t **)term_alloc(ctx, (size_t)n * sizeof(term_t *));
      for (int i = 0; i < n; i++)
        c->body[c->body_count++] = tmp[i];
    }
  }

  // terminating dot
  skip_ws(ctx);
  if (*ctx->input_ptr != '.') {
    ctx->alloc_permanent = false;
    parse_error(ctx, "expected '.' at end of clause");
    parse_error_print(ctx);
    return;
  }
  ctx->input_ptr++;
  ctx->alloc_permanent = false;

  ctx->db_count++;

  if (ctx->debug_enabled) {
    debug(ctx, "=== Clause %d parsed ===\n", ctx->db_count - 1);
    debug(ctx, "HEAD: ");
    debug_term_raw(ctx, c->head);
    debug(ctx, "\n");
    for (int i = 0; i < c->body_count; i++) {
      debug(ctx, "BODY[%d]: ", i);
      debug_term_raw(ctx, c->body[i]);
      debug(ctx, "\n");
    }
    debug(ctx, "======================\n");
  }
}
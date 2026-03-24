#include "platform_impl.h"

//****
//* operator classification
//****

// operators that print infix (arity 2) or prefix (arity 1)
static bool is_infix_op(const char *name) {
  static const char *ops[] = {
      "+", "-", "*",  "/",   "//",  "mod",  "is", "=",  "\\=", "==",  "\\==",
      "<", ">", "=<", ">=",  "=:=", "=\\=", "@<", "@>", "@=<", "@>=", "->",
      ";", ",", "^",  "=..", "\\/", "/\\",  ">>", "<<", "xor", NULL};
  for (const char **p = ops; *p; p++)
    if (strcmp(name, *p) == 0)
      return true;
  return false;
}

static bool is_prefix_op(const char *name) {
  return strcmp(name, "\\+") == 0 || strcmp(name, "not") == 0 ||
         strcmp(name, "\\") == 0;
}

// true if atom name needs single-quote wrapping
static bool needs_quoting(const char *name) {
  if (!name || name[0] == '\0')
    return true;
  // special atoms that never need quoting
  if (strcmp(name, "[]") == 0 || strcmp(name, "{}") == 0 ||
      strcmp(name, "!") == 0)
    return false;
  // negative integers don't need quoting
  if (name[0] == '-') {
    const char *p = name + 1;
    if (*p >= '0' && *p <= '9') {
      while (*p >= '0' && *p <= '9')
        p++;
      if (*p == '\0')
        return false;
    }
  }
  // starts with uppercase or underscore → variable-like, must quote
  if (isupper((unsigned char)name[0]) || name[0] == '_')
    return true;
  // contains whitespace or prolog comment/string delimiters → must quote
  for (const char *p = name; *p; p++) {
    if (isspace((unsigned char)*p) || *p == '%' || *p == '\'' || *p == '"')
      return true;
  }
  return false;
}

static void print_atom(trilog_ctx_t *ctx, const char *name, bool quoted) {
  if (quoted && needs_quoting(name)) {
    io_write_str(ctx, "'");
    for (const char *p = name; *p; p++) {
      if (*p == '\'')
        io_write_str(ctx, "\\'");
      else if (*p == '\\')
        io_write_str(ctx, "\\\\");
      else {
        char buf[2] = {*p, '\0'};
        io_write_str(ctx, buf);
      }
    }
    io_write_str(ctx, "'");
  } else {
    io_write_str(ctx, name);
  }
}

//****
//* term printing
//****

void print_term(trilog_ctx_t *ctx, term_t *t, env_t *env, bool quoted) {
  assert(env != ((void *)0) && "Environment is NULL");

  if (!t) {
    io_write_str(ctx, "NULL");
    return;
  }

  t = deref(env, t);

  if (is_cons(t)) {
    io_write_str(ctx, "[");
    while (is_cons(t)) {
      assert(t->arity == 2 && "List node must have arity 2");
      print_term(ctx, t->args[0], env, quoted);
      t = deref(env, t->args[1]);
      if (is_cons(t))
        io_write_str(ctx, ", ");
    }
    if (!is_nil(t)) {
      io_write_str(ctx, "|");
      print_term(ctx, t, env, quoted);
    }
    io_write_str(ctx, "]");
    return;
  }

  if (is_nil(t)) {
    io_write_str(ctx, "[]");
    return;
  }

  if (t->type == STRING) {
    if (quoted) {
      io_write_str(ctx, "\"");
      for (const char *p = t->string_data; *p; p++) {
        const str_escape_t *e = STR_ESCAPES;
        while (e->raw && e->raw != *p)
          e++;
        if (e->raw) {
          char esc[3] = {'\\', e->seq, '\0'};
          io_write_str(ctx, esc);
        } else {
          char buf[2] = {*p, '\0'};
          io_write_str(ctx, buf);
        }
      }
      io_write_str(ctx, "\"");
    } else {
      io_write_str(ctx, t->string_data);
    }
    return;
  }

  if (t->type == VAR) {
    if (t->name)
      io_write_str(ctx, t->name);
    else {
      char buf[32];
      snprintf(buf, sizeof(buf), "_G%d", t->arity);
      io_write_str(ctx, buf);
    }
    return;
  }

  // infix binary operator: x op y
  if (t->type == FUNC && t->arity == 2 && is_infix_op(t->name)) {
    print_term(ctx, t->args[0], env, quoted);
    io_write_str(ctx, t->name);
    print_term(ctx, t->args[1], env, quoted);
    return;
  }

  // prefix unary operator: op x
  if (t->type == FUNC && t->arity == 1 && is_prefix_op(t->name)) {
    io_write_str(ctx, t->name);
    io_write_str(ctx, "(");
    print_term(ctx, t->args[0], env, quoted);
    io_write_str(ctx, ")");
    return;
  }

  print_atom(ctx, t->name, quoted);
  if (t->type == FUNC && t->arity > 0) {
    io_write_str(ctx, "(");
    for (int i = 0; i < t->arity; i++) {
      if (i > 0)
        io_write_str(ctx, ", ");
      print_term(ctx, t->args[i], env, quoted);
    }
    io_write_str(ctx, ")");
  }
}

//****
//* binding output
//****

void print_bindings(trilog_ctx_t *ctx, env_t *env) {
  bool printed = false;
  for (int i = 0; i < env->count; i++) {
    const char *name = env->bindings[i].name;
    if (!name || name[0] == '_')
      continue;
    if (printed)
      io_write_str(ctx, ", ");
    io_writef(ctx, "%s = ", name);
    io_write_term_quoted(ctx, env->bindings[i].value, env);
    printed = true;
  }
  if (!printed)
    io_write_str(ctx, "true");
}

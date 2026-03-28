#include "platform_impl.h"

//****
//* buffer capture (output to string)
//****

#define BCAP_SIZE 4096

typedef struct {
  io_hooks_t saved;
  char buf[BCAP_SIZE];
  int pos;
} bcap_t;

static void bcap_write_str(trilog_ctx_t *ctx, const char *str, void *ud) {
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

static void bcap_writef(trilog_ctx_t *ctx, const char *fmt, va_list args,
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

static void bcap_start(trilog_ctx_t *ctx, bcap_t *c) {
  c->saved = ctx->io_hooks;
  c->pos = 0;
  c->buf[0] = '\0';
  ctx->io_hooks.write_str = bcap_write_str;
  ctx->io_hooks.writef = bcap_writef;
  ctx->io_hooks.writef_err = bcap_writef;
  ctx->io_hooks.userdata = c;
}

static void bcap_end(trilog_ctx_t *ctx, bcap_t *c) { ctx->io_hooks = c->saved; }

//****
//* stream term construction
//****

static term_t *make_stream_term(trilog_ctx_t *ctx, int id) {
  term_t *n = make_int(ctx, id);
  term_t *args[1] = {n};
  return make_func(ctx, "$stream", args, 1);
}

static bool get_stream_id(env_t *env, term_t *t, int *id) {
  t = deref(env, t);
  if (!t || t->type != FUNC || strcmp(t->name, "$stream") != 0 || t->arity != 1)
    return false;
  return term_as_int(t->args[0], id);
}

//****
//* stream write capture (redirect to file handle)
//****

typedef struct {
  io_hooks_t saved;
  trilog_ctx_t *ctx;
  void *file_handle;
} scap_t;

static void scap_write_str(trilog_ctx_t *ctx, const char *str, void *ud) {
  (void)ctx;
  scap_t *c = ud;
  io_file_write(c->ctx, c->file_handle, str);
}

static void scap_writef(trilog_ctx_t *ctx, const char *fmt, va_list args,
                        void *ud) {
  (void)ctx;
  scap_t *c = ud;
  char buf[4096];
  vsnprintf(buf, sizeof(buf), fmt, args);
  io_file_write(c->ctx, c->file_handle, buf);
}

static void scap_start(trilog_ctx_t *ctx, scap_t *c, void *file_handle) {
  c->saved = ctx->io_hooks;
  c->ctx = ctx;
  c->file_handle = file_handle;
  ctx->io_hooks.write_str = scap_write_str;
  ctx->io_hooks.writef = scap_writef;
  ctx->io_hooks.writef_err = scap_writef;
  ctx->io_hooks.userdata = c;
}

static void scap_end(trilog_ctx_t *ctx, scap_t *c) { ctx->io_hooks = c->saved; }

//****
//* stream resolution
//****

// resolve stream arg: null = user_output, (void*)-1 = error, else file handle
static void *resolve_output_stream(trilog_ctx_t *ctx, env_t *env, term_t *arg) {
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

//****
//* stream builtins
//****

builtin_result_t builtin_nl1(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
  void *h = resolve_output_stream(ctx, env, goal->args[0]);
  if (h == (void *)-1)
    return BUILTIN_FAIL;
  if (!h)
    io_write_str(ctx, "\n");
  else
    io_file_write(ctx, h, "\n");
  return BUILTIN_OK;
}

builtin_result_t builtin_write2(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
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

builtin_result_t builtin_writeln2(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
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

builtin_result_t builtin_writeq2(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
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

builtin_result_t builtin_with_output_to(trilog_ctx_t *ctx, term_t *goal,
                                        env_t *env) {
  term_t *sink = deref(env, goal->args[0]);
  term_t *g = deref(env, goal->args[1]);

  if (!sink || sink->type != FUNC || sink->arity != 1)
    return BUILTIN_FAIL;

  const char *sname = sink->name;
  bool is_atom = strcmp(sname, "atom") == 0;
  bool is_codes = strcmp(sname, "codes") == 0;
  bool is_chars = strcmp(sname, "chars") == 0;
  if (!is_atom && !is_codes && !is_chars)
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
  if (is_codes) {
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

builtin_result_t builtin_term_to_atom(trilog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  term_t *term_arg = deref(env, goal->args[0]);
  term_t *atom_arg = deref(env, goal->args[1]);

  // atom -> term direction
  if (term_arg->type == VAR && atom_arg->type != VAR) {
    const char *str = atom_arg->name;
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

  // term -> atom direction
  bcap_t cap;
  bcap_start(ctx, &cap);
  print_term(ctx, term_arg, env, true);
  bcap_end(ctx, &cap);

  return unify(ctx, atom_arg, make_const(ctx, cap.buf), env) ? BUILTIN_OK
                                                             : BUILTIN_FAIL;
}

builtin_result_t builtin_atom_to_term(trilog_ctx_t *ctx, term_t *goal,
                                      env_t *env) {
  term_t *atom_arg = deref(env, goal->args[0]);
  const char *str = atom_arg->name;
  if (!str)
    return BUILTIN_FAIL;

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

builtin_result_t builtin_open(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
  term_t *path_t = deref(env, goal->args[0]);
  term_t *mode_t = deref(env, goal->args[1]);
  if (!path_t || !mode_t || mode_t->type != CONST)
    return BUILTIN_FAIL;

  const char *path = path_t->name;
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

builtin_result_t builtin_close(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
  int id;
  if (!get_stream_id(env, goal->args[0], &id))
    return BUILTIN_FAIL;
  if (id < 0 || id >= MAX_OPEN_STREAMS || !ctx->open_streams[id])
    return BUILTIN_FAIL;
  io_file_close(ctx, ctx->open_streams[id]);
  ctx->open_streams[id] = NULL;
  return BUILTIN_OK;
}

builtin_result_t builtin_read_line_to_atom(trilog_ctx_t *ctx, term_t *goal,
                                           env_t *env) {
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

builtin_result_t builtin_get_char(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
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

builtin_result_t builtin_read_term(trilog_ctx_t *ctx, term_t *goal,
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

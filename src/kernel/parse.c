#include "parse.h"
#include "arena.h"
#include "atoms.h"
#include "ctx.h"
#include "embedded.h"
#include "heap.h"
#include "io.h"
#include "solve.h"
#include <ctype.h>
#include <errno.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ARITY 255
#define MAX_TOKEN 4096

typedef enum { XFX, XFY, YFX, FX, FY } assoc_t;
typedef struct {
  const char *name;
  int pri;
  assoc_t assoc;
} op_t;

static const op_t OPS[] = {
    {":-", 1200, XFX}, {":-", 1200, FX},   {"?-", 1200, FX},
    {";", 1100, XFY},  {"->", 1050, XFY},  {",", 1000, XFY},
    {"\\+", 900, FY},  {"=", 700, XFX},    {"\\=", 700, XFX},
    {"==", 700, XFX},  {"\\==", 700, XFX}, {"is", 700, XFX},
    {"<", 700, XFX},   {">", 700, XFX},    {"=<", 700, XFX},
    {">=", 700, XFX},  {"=:=", 700, XFX},  {"=\\=", 700, XFX},
    {"=..", 700, XFX}, {"@<", 700, XFX},   {"@>", 700, XFX},
    {"@=<", 700, XFX}, {"@>=", 700, XFX},  {"+", 500, YFX},
    {"-", 500, YFX},   {"*", 400, YFX},    {"/", 400, YFX},
    {"mod", 400, YFX}, {"//", 400, YFX},   {"-", 200, FY},
    {"+", 200, FY},    {"\\/", 500, YFX},  {"xor", 400, YFX},
    {"<<", 400, YFX},  {">>", 400, YFX},   {"/\\", 400, YFX},
    {"\\", 200, FY},   {"^", 200, XFY},
};
#define NOPS (int)(sizeof(OPS) / sizeof(OPS[0]))

static int find_infix(trilog_t *T, const char *name, op_t *out) {
  for (int i = 0; i < NOPS; i++)
    if ((OPS[i].assoc == XFX || OPS[i].assoc == XFY || OPS[i].assoc == YFX) &&
        !strcmp(OPS[i].name, name)) {
      *out = OPS[i];
      return 1;
    }
  int pri, assoc_code;
  int32_t id = atom_intern(T, name);
  if (op_lookup_infix(T, id, &pri, &assoc_code)) {
    out->name = atom_name(T, id); // permanent atom-table storage, not `name`
    out->pri = pri;
    out->assoc = (assoc_t)assoc_code;
    return 1;
  }
  return 0;
}

static int find_prefix(trilog_t *T, const char *name, op_t *out) {
  for (int i = 0; i < NOPS; i++)
    if ((OPS[i].assoc == FX || OPS[i].assoc == FY) &&
        !strcmp(OPS[i].name, name)) {
      *out = OPS[i];
      return 1;
    }
  int pri, assoc_code;
  int32_t id = atom_intern(T, name);
  if (op_lookup_prefix(T, id, &pri, &assoc_code)) {
    out->name = atom_name(T, id);
    out->pri = pri;
    out->assoc = (assoc_t)assoc_code;
    return 1;
  }
  return 0;
}

// ---- input cursor and error handling ----

static void perr(trilog_t *T, const char *msg) {
  snprintf(T->err_msg, sizeof(T->err_msg), "%s near \"%.20s\"", msg, T->P);
  longjmp(T->err_jmp, 1);
}

static int is_symbol_char(int c) {
  return c != '\0' && strchr("+-*/\\^<>=~:.?@#&$", c) != NULL;
}

static void skip_ws(trilog_t *T) {
  for (;;) {
    while (isspace((unsigned char)*T->P))
      T->P++;
    if (T->P[0] == '%') {
      while (*T->P && *T->P != '\n')
        T->P++;
    } else if (T->P[0] == '/' && T->P[1] == '*') {
      T->P += 2;
      while (*T->P && !(T->P[0] == '*' && T->P[1] == '/'))
        T->P++;
      if (*T->P)
        T->P += 2;
    } else
      break;
  }
}

// true if a '.' at P ends a clause (period followed by layout/EOF/%)
static int at_clause_end(trilog_t *T) {
  return T->P[0] == '.' &&
         (T->P[1] == '\0' || isspace((unsigned char)T->P[1]) || T->P[1] == '%');
}

// ---- per-clause variable table: reset before each clause/query

static void vartab_reset(trilog_t *T) { T->var_count = 0; }

static int32_t vartab_slot(trilog_t *T, const char *name) {
  if (strcmp(name, "_") != 0) {
    for (int32_t i = 0; i < T->var_count; i++)
      if (!strcmp(T->var_names[i], name))
        return i;
  }
  if (T->var_count >= MAX_CVARS)
    perr(T, "too many distinct variables in one clause");
  if (strlen(name) >= MAX_VARNAME)
    perr(T, "variable name too long");
  strcpy(T->var_names[T->var_count], name);
  return T->var_count++;
}

// ---- tokens ----

static void read_while(trilog_t *T, char *buf, int (*pred)(int)) {
  size_t n = 0;
  while (pred((unsigned char)*T->P)) {
    if (n + 1 >= MAX_TOKEN)
      perr(T, "token too long");
    buf[n++] = *T->P++;
  }
  buf[n] = '\0';
}

static int is_ident_char(int c) { return isalnum(c) || c == '_'; }

static void read_quoted(trilog_t *T, char quote, char *buf) {
  T->P++; // opening quote
  size_t n = 0;
  for (;;) {
    if (*T->P == '\0')
      perr(T, "unterminated quoted token");
    if (*T->P == quote) {
      if (T->P[1] == quote) {
        if (n + 1 >= MAX_TOKEN)
          perr(T, "token too long");
        buf[n++] = quote;
        T->P += 2;
        continue;
      }
      T->P++;
      break;
    }
    char v = *T->P;
    if (*T->P == '\\') {
      T->P++;
      if (*T->P == '\0')
        perr(T, "unterminated quoted token");
      char c = *T->P++;
      switch (c) {
      case 'n':
        v = '\n';
        break;
      case 't':
        v = '\t';
        break;
      case 'a':
        v = '\a';
        break;
      default:
        v = c;
        break;
      }
    } else
      T->P++;
    if (n + 1 >= MAX_TOKEN)
      perr(T, "token too long");
    buf[n++] = v;
  }
  buf[n] = '\0';
}

static tterm_t *parse_expr(trilog_t *T, int max_prec);
static tterm_t *parse_arg(trilog_t *T) {
  return parse_expr(T, 999);
} // args stop below ','

// parses comma-separated args into caller-owned scratch
static int32_t parse_arglist(trilog_t *T, tterm_t **scratch) {
  int32_t n = 0;
  scratch[n++] = parse_arg(T);
  skip_ws(T);
  while (*T->P == ',') {
    T->P++;
    skip_ws(T);
    if (n >= MAX_ARITY)
      perr(T, "too many arguments");
    scratch[n++] = parse_arg(T);
    skip_ws(T);
  }
  return n;
}

static tterm_t *parse_list(trilog_t *T) {
  T->P++; // '['
  skip_ws(T);
  if (*T->P == ']') {
    T->P++;
    return tt_atom(T, "[]");
  }
  tterm_t *elems[MAX_ARITY];
  int n = 0;
  elems[n++] = parse_arg(T);
  skip_ws(T);
  tterm_t *tail = tt_atom(T, "[]");
  while (*T->P == ',') {
    T->P++;
    skip_ws(T);
    if (n >= MAX_ARITY)
      perr(T, "list literal too long");
    elems[n++] = parse_arg(T);
    skip_ws(T);
  }
  if (*T->P == '|') {
    T->P++;
    skip_ws(T);
    tail = parse_arg(T);
    skip_ws(T);
  }
  if (*T->P != ']')
    perr(T, "expected ']'");
  T->P++;
  tterm_t *acc = tail;
  for (int i = n - 1; i >= 0; i--) {
    tterm_t *cons[2] = {elems[i], acc};
    acc = tt_struct(T, ".", 2, cons);
  }
  return acc;
}

static tterm_t *parse_string(trilog_t *T) {
  char buf[MAX_TOKEN];
  read_quoted(T, '"', buf);
  tterm_t *acc = tt_atom(T, "[]");
  size_t n = strlen(buf);
  for (size_t i = n; i-- > 0;) {
    char c[2] = {buf[i], '\0'};
    tterm_t *cons[2] = {tt_atom(T, c), acc};
    acc = tt_struct(T, ".", 2, cons);
  }
  return acc;
}

// 0'c: the character code of c. A doubled quote (0''') is a literal
// quote, matching how a quoted atom escapes one; not a quoted-atom opener.
static tterm_t *parse_char_code(trilog_t *T) {
  T->P += 2; // "0'"
  int code;
  if (*T->P == '\0' || (*T->P == '\\' && T->P[1] == '\0'))
    perr(T, "unexpected end of input in 0' character code");
  if (*T->P == '\\') {
    T->P++;
    char c = *T->P++;
    switch (c) {
    case 'n':
      code = '\n';
      break;
    case 't':
      code = '\t';
      break;
    case 'r':
      code = '\r';
      break;
    case 'a':
      code = '\a';
      break;
    case 'b':
      code = '\b';
      break;
    case 'f':
      code = '\f';
      break;
    case 'v':
      code = '\v';
      break;
    default:
      code = (unsigned char)c;
      break;
    }
  } else if (T->P[0] == '\'' && T->P[1] == '\'') {
    code = '\'';
    T->P += 2;
  } else {
    code = (unsigned char)*T->P++;
  }
  return tt_int(T, code);
}

static tterm_t *parse_number(trilog_t *T) {
  if (T->P[0] == '0' && T->P[1] == '\'')
    return parse_char_code(T);
  const char *start = T->P;
  if (*T->P == '-')
    T->P++;
  while (isdigit((unsigned char)*T->P))
    T->P++;
  int is_float = 0;
  if (T->P[0] == '.' && isdigit((unsigned char)T->P[1])) {
    is_float = 1;
    T->P++;
    while (isdigit((unsigned char)*T->P))
      T->P++;
  }
  if (*T->P == 'e' || *T->P == 'E') {
    is_float = 1;
    T->P++;
    if (*T->P == '+' || *T->P == '-')
      T->P++;
    while (isdigit((unsigned char)*T->P))
      T->P++;
  }
  size_t n = (size_t)(T->P - start);
  char buf[64];
  if (n >= sizeof(buf))
    perr(T, "number literal too long");
  memcpy(buf, start, n);
  buf[n] = '\0';
  if (is_float)
    return tt_flt(T, strtod(buf, NULL));
  errno = 0;
  long long v = strtoll(buf, NULL, 10);
  if (errno == ERANGE)
    perr(T, "integer literal out of range");
  return tt_int(T, v);
}

static tterm_t *parse_primary(trilog_t *T) {
  skip_ws(T);
  if (*T->P == '\0')
    perr(T, "unexpected end of input");
  char name[MAX_TOKEN];

  if (*T->P == '(') {
    T->P++;
    skip_ws(T);
    tterm_t *t = parse_expr(T, 1200);
    skip_ws(T);
    if (*T->P != ')')
      perr(T, "expected ')'");
    T->P++;
    return t;
  }
  if (*T->P == '[')
    return parse_list(T);
  if (*T->P == '{') {
    T->P++;
    skip_ws(T);
    if (*T->P == '}') {
      T->P++;
      return tt_atom(T, "{}");
    }
    tterm_t *t = parse_expr(T, 1200);
    skip_ws(T);
    if (*T->P != '}')
      perr(T, "expected '}'");
    T->P++;
    tterm_t *args[1] = {t};
    return tt_struct(T, "{}", 1, args);
  }
  if (*T->P == '"')
    return parse_string(T);
  if (*T->P == '!') {
    T->P++;
    return tt_atom(T, "!");
  }
  if (*T->P == ';') {
    T->P++;
    return tt_atom(T, ";");
  }
  if (*T->P == '\'') {
    read_quoted(T, '\'', name);
    skip_ws(T);
    if (*T->P == '(') {
      T->P++;
      skip_ws(T);
      tterm_t *args[MAX_ARITY];
      int32_t n = parse_arglist(T, args);
      skip_ws(T);
      if (*T->P != ')')
        perr(T, "expected ')'");
      T->P++;
      return tt_struct(T, name, n, args);
    }
    return tt_atom(T, name);
  }
  if (*T->P == '_' || isupper((unsigned char)*T->P)) {
    read_while(T, name, is_ident_char);
    return tt_var(T, vartab_slot(T, name));
  }
  if (isdigit((unsigned char)*T->P))
    return parse_number(T);
  if (*T->P == '-' && isdigit((unsigned char)T->P[1]))
    return parse_number(T);

  if (islower((unsigned char)*T->P)) {
    read_while(T, name, is_ident_char);
    if (*T->P == '(') {
      T->P++;
      skip_ws(T);
      tterm_t *args[MAX_ARITY];
      int32_t n = parse_arglist(T, args);
      skip_ws(T);
      if (*T->P != ')')
        perr(T, "expected ')'");
      T->P++;
      return tt_struct(T, name, n, args);
    }
    op_t pre, dummy;
    int have_pre = find_prefix(T, name, &pre);
    if (have_pre && *T->P != '\0' && !at_clause_end(T) && *T->P != ')' &&
        *T->P != ',' && *T->P != ']' && *T->P != '|' &&
        !find_infix(T, name, &dummy)) {
      tterm_t *arg = parse_expr(T, pre.assoc == FY ? pre.pri : pre.pri - 1);
      return tt_struct(T, name, 1, &arg);
    }
    return tt_atom(T, name);
  }
  if (is_symbol_char((unsigned char)*T->P)) {
    read_while(T, name, is_symbol_char);
    if (*T->P == '(') {
      T->P++;
      skip_ws(T);
      tterm_t *args[MAX_ARITY];
      int32_t n = parse_arglist(T, args);
      skip_ws(T);
      if (*T->P != ')')
        perr(T, "expected ')'");
      T->P++;
      return tt_struct(T, name, n, args);
    }
    op_t pre;
    int have_pre = find_prefix(T, name, &pre);
    if (have_pre && *T->P != '\0' && !at_clause_end(T) && *T->P != ')' &&
        *T->P != ',' && *T->P != ']' && *T->P != '|') {
      tterm_t *arg = parse_expr(T, pre.assoc == FY ? pre.pri : pre.pri - 1);
      return tt_struct(T, name, 1, &arg);
    }
    return tt_atom(T, name);
  }
  perr(T, "unexpected character");
  return NULL; // unreachable
}

// tries to read an infix operator name at the current position without
// consuming it if it doesn't turn out to be one; returns 0 if none.
static int peek_infix_op(trilog_t *T, size_t *len_out, op_t *out) {
  skip_ws(T);
  if (*T->P == '\0' || *T->P == ')' || *T->P == ']' || *T->P == '|' ||
      at_clause_end(T))
    return 0;
  if (*T->P == ',') {
    *len_out = 1;
    return find_infix(T, ",", out);
  }
  if (*T->P == ';') {
    *len_out = 1;
    return find_infix(T, ";", out);
  }
  if (is_symbol_char((unsigned char)*T->P)) {
    const char *save = T->P;
    char name[MAX_TOKEN];
    read_while(T, name, is_symbol_char);
    int found = find_infix(T, name, out);
    size_t len = strlen(name);
    T->P = save;
    if (found)
      *len_out = len;
    return found;
  }
  if (islower((unsigned char)*T->P)) {
    const char *save = T->P;
    char name[MAX_TOKEN];
    read_while(T, name, is_ident_char);
    int found = find_infix(T, name, out);
    size_t len = strlen(name);
    T->P = save;
    if (found)
      *len_out = len;
    return found;
  }
  return 0;
}

static tterm_t *parse_expr(trilog_t *T, int max_prec) {
  tterm_t *left = parse_primary(T);
  for (;;) {
    size_t len;
    op_t op;
    if (!peek_infix_op(T, &len, &op) || op.pri > max_prec)
      break;
    int right_max = (op.assoc == XFY) ? op.pri : op.pri - 1;
    T->P += len;
    skip_ws(T);
    tterm_t *right = parse_expr(T, right_max);
    tterm_t *args[2] = {left, right};
    left = tt_struct(T, op.name, 2, args);
  }
  return left;
}

// ---- clause assembly ----

// flattens a right-nested ','/2 chain into an array of goals
static tterm_t **flatten_conj(trilog_t *T, tterm_t *t, int32_t *n_out) {
  tterm_t *scratch[MAX_ARITY];
  int32_t n = 0;
  while (t->tag == T_STR && t->as.str.arity == 2 &&
         t->as.str.atom_id == atom_comma) {
    if (n >= MAX_ARITY)
      perr(T, "clause body too long");
    scratch[n++] = t->as.str.args[0];
    t = t->as.str.args[1];
  }
  if (n >= MAX_ARITY)
    perr(T, "clause body too long");
  scratch[n++] = t;
  tterm_t **out = arena_alloc(T, (size_t)n * sizeof(tterm_t *));
  memcpy(out, scratch, (size_t)n * sizeof(tterm_t *));
  *n_out = n;
  return out;
}

static int all_solutions(void *ud, int has_more) {
  (void)ud;
  (void)has_more;
  return 1;
}

static void run_directive(trilog_t *T, tterm_t *goal, int32_t nvars) {
  int32_t n;
  tterm_t **goals = flatten_conj(T, goal, &n);
  if (run_query(T, goals, n, nvars, all_solutions, NULL) == QUERY_ERROR) {
    io_write_err(T, "uncaught exception: ");
    print_term_via(T, query_error_ball(T), 0, io_write_err);
    io_write_err(T, "\n");
  }
}

static void assemble_clause(trilog_t *T, tterm_t *t, int32_t nvars) {
  if (t->tag == T_STR && t->as.str.arity == 2 &&
      t->as.str.atom_id == atom_ruleop) {
    int32_t nbody;
    tterm_t **body = flatten_conj(T, t->as.str.args[1], &nbody);
    db_add(T, t->as.str.args[0], body, nbody, nvars, 1);
    return;
  }
  if (t->tag == T_STR && t->as.str.arity == 1 &&
      (t->as.str.atom_id == atom_ruleop ||
       t->as.str.atom_id == atom_qmark_dash)) {
    run_directive(T, t->as.str.args[0], nvars);
    return;
  }
  db_add(T, t, NULL, 0, nvars, 1); // a fact - neither a rule nor a directive
}

// library files baked into a release build are consulted as "embedded:PATH".
#define EMBED_PREFIX "embedded:"
#define EMBED_PREFIX_LEN (sizeof EMBED_PREFIX - 1)

// folds "." and "dir/.." segments in place, so that "boot/../lib/lists.pl"
// matches the embedded file "lib/lists.pl".
static void normalize_path(char *path) {
  char *seg[256];
  int n = 0;
  for (char *tok = strtok(path, "/"); tok; tok = strtok(NULL, "/")) {
    if (!strcmp(tok, "."))
      continue;
    if (!strcmp(tok, "..") && n > 0 && strcmp(seg[n - 1], ".."))
      n--;
    else if (n < 256)
      seg[n++] = tok;
  }
  char out[4096];
  size_t len = 0;
  out[0] = '\0';
  for (int i = 0; i < n; i++)
    len += (size_t)snprintf(out + len, sizeof out - len, "%s%s", i ? "/" : "",
                            seg[i]);
  memcpy(path, out, strlen(out) + 1);
}

// the embedded text for a relative path, or NULL. On a hit, resolved gets
// the "embedded:" name that later relative consults resolve against.
static const char *find_embedded(const char *path, char *resolved, size_t cap) {
  char key[4096];
  snprintf(key, sizeof key, "%s", path);
  normalize_path(key);
  for (const embedded_file *e = embedded_files; e->path; e++)
    if (!strcmp(e->path, key)) {
      snprintf(resolved, cap, EMBED_PREFIX "%s", e->path);
      return e->data;
    }
  return NULL;
}

static size_t read_file_pass(trilog_t *T, const char *path, char *out,
                             size_t cap) {
  void *h = io_file_open(T, path, "rb");
  if (!h)
    return (size_t)-1;
  char chunk[4096];
  size_t len = 0;
  long got;
  while ((got = io_file_read(T, h, chunk, sizeof chunk)) > 0) {
    size_t n = (size_t)got;
    size_t room = len < cap ? cap - len : 0;
    if (out)
      memcpy(out + len, chunk, n < room ? n : room);
    len += n;
  }
  io_file_close(T, h);
  return len;
}

static char *read_whole_file(trilog_t *T, const char *path) {
  size_t len = read_file_pass(T, path, NULL, 0);
  if (len == (size_t)-1)
    return NULL;
  char *buf = arena_alloc(T, len + 1); // FIXME: never freed
  size_t got = read_file_pass(T, path, buf, len);
  buf[got != (size_t)-1 && got < len ? got : len] = '\0';
  return buf;
}

// A relative path consulted from inside a file resolves against that file's
// directory first, then the current directory, then the embedded libraries.
static const char *consult_text(trilog_t *T, const char *path, char *resolved,
                                size_t cap) {
  if (!strncmp(path, EMBED_PREFIX, EMBED_PREFIX_LEN))
    return find_embedded(path + EMBED_PREFIX_LEN, resolved, cap);
  const char *slash = T->consulting ? strrchr(T->consulting, '/') : NULL;
  if (path[0] != '/' && slash) {
    snprintf(resolved, cap, "%.*s/%s", (int)(slash - T->consulting),
             T->consulting, path);
    if (!strncmp(resolved, EMBED_PREFIX, EMBED_PREFIX_LEN)) {
      char rel[4096];
      snprintf(rel, sizeof rel, "%s", resolved + EMBED_PREFIX_LEN);
      const char *text = find_embedded(rel, resolved, cap);
      if (text)
        return text;
    } else {
      char *text = read_whole_file(T, resolved);
      if (text)
        return text;
    }
  }
  snprintf(resolved, cap, "%s", path);
  char *text = read_whole_file(T, resolved);
  if (text)
    return text;
  return path[0] != '/' ? find_embedded(path, resolved, cap) : NULL;
}

static bool consult_source(trilog_t *T, const char *text, const char *path);

// Re-entrant: a consult/1 directive inside the file saves and restores the
// outer file's parse state.
static bool consult_nested(trilog_t *T, const char *text, const char *file,
                           const char *name) {
  const char *saved_P = T->P, *saved_consulting = T->consulting;
  int32_t saved_atom = T->consulting_atom;
  jmp_buf saved_jmp;
  memcpy(saved_jmp, T->err_jmp, sizeof(jmp_buf));
  T->consulting = file;
  T->consulting_atom = file ? atom_intern(T, file) : -1;
  bool ok = consult_source(T, text, name);
  T->consulting = saved_consulting;
  T->consulting_atom = saved_atom;
  T->P = saved_P;
  memcpy(T->err_jmp, saved_jmp, sizeof(jmp_buf));
  return ok;
}

bool consult_file(trilog_t *T, const char *path, int32_t *source) {
  char resolved[4096];
  const char *text = consult_text(T, path, resolved, sizeof resolved);
  if (!text) {
    char msg[300];
    snprintf(msg, sizeof msg, "cannot open %s\n", path);
    io_write_err(T, msg);
    return false;
  }
  int32_t atom = atom_intern(T, resolved);
  db_unload(T, atom);
  if (source)
    *source = atom;
  return consult_nested(T, text, resolved, resolved);
}

bool consult_string(trilog_t *T, const char *text) {
  return consult_nested(T, text, NULL, "<string>");
}

static bool consult_source(trilog_t *T, const char *text, const char *path) {
  T->P = text;
  if (setjmp(T->err_jmp)) {
    char msg[300 + sizeof T->err_msg];
    snprintf(msg, sizeof msg, "parse error in %s: %s\n", path, T->err_msg);
    io_write_err(T, msg);
    return false;
  }
  for (;;) {
    skip_ws(T);
    if (*T->P == '\0')
      break;
    vartab_reset(T);
    tterm_t *t = parse_expr(T, 1200);
    skip_ws(T);
    if (!at_clause_end(T))
      perr(T, "expected '.' to end clause");
    T->P++;
    assemble_clause(T, t, T->var_count);
  }
  return true;
}

bool parse_query(trilog_t *T, const char *src, tterm_t ***goals_out,
                 int32_t *ngoals_out, int32_t *nvars_out,
                 const char ***varnames_out) {
  T->P = src;
  if (setjmp(T->err_jmp)) {
    char msg[32 + sizeof T->err_msg];
    snprintf(msg, sizeof msg, "parse error: %s\n", T->err_msg);
    io_write_err(T, msg);
    return false;
  }
  vartab_reset(T);
  tterm_t *t = parse_expr(T, 1200);
  skip_ws(T);
  if (*T->P != '\0' && !at_clause_end(T))
    perr(T, "unexpected trailing input");
  if (at_clause_end(T))
    T->P++;

  *goals_out = flatten_conj(T, t, ngoals_out);
  *nvars_out = T->var_count;
  const char **names = arena_alloc(
      T, (size_t)(T->var_count > 0 ? T->var_count : 1) * sizeof(char *));
  for (int32_t i = 0; i < T->var_count; i++)
    names[i] = arena_strdup(T, T->var_names[i]);
  *varnames_out = names;
  return true;
}

static bool parse_term_from_string_(trilog_t *T, const char *src,
                                    tterm_t **term_out, int32_t *nvars_out,
                                    const char ***varnames_out);

bool parse_term_from_string(trilog_t *T, const char *src, tterm_t **term_out,
                            int32_t *nvars_out, const char ***varnames_out) {
  const char *saved_P = T->P;
  jmp_buf saved_jmp;
  memcpy(saved_jmp, T->err_jmp, sizeof(jmp_buf));
  bool ok = parse_term_from_string_(T, src, term_out, nvars_out, varnames_out);
  T->P = saved_P;
  memcpy(T->err_jmp, saved_jmp, sizeof(jmp_buf));
  return ok;
}

static bool parse_term_from_string_(trilog_t *T, const char *src,
                                    tterm_t **term_out, int32_t *nvars_out,
                                    const char ***varnames_out) {
  T->P = src;
  if (setjmp(T->err_jmp))
    return false;
  vartab_reset(T);
  tterm_t *t = parse_expr(T, 1200);
  skip_ws(T);
  if (*T->P != '\0' && !at_clause_end(T))
    perr(T, "unexpected trailing input");
  if (at_clause_end(T))
    T->P++;

  *term_out = t;
  *nvars_out = T->var_count;
  const char **names = arena_alloc(
      T, (size_t)(T->var_count > 0 ? T->var_count : 1) * sizeof(char *));
  for (int32_t i = 0; i < T->var_count; i++)
    names[i] = arena_strdup(T, T->var_names[i]);
  *varnames_out = names;
  return true;
}

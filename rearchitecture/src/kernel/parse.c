#define _POSIX_C_SOURCE 200809L
#include "parse.h"
#include "arena.h"
#include "heap.h"
#include "io.h"
#include "solve.h"
#include <ctype.h>
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
    {"mod", 400, YFX}, {"-", 200, FY},     {"+", 200, FY},
};
#define NOPS (int)(sizeof(OPS) / sizeof(OPS[0]))

static const op_t *find_infix(const char *name) {
  for (int i = 0; i < NOPS; i++)
    if ((OPS[i].assoc == XFX || OPS[i].assoc == XFY || OPS[i].assoc == YFX) &&
        !strcmp(OPS[i].name, name))
      return &OPS[i];
  return NULL;
}

static const op_t *find_prefix(const char *name) {
  for (int i = 0; i < NOPS; i++)
    if ((OPS[i].assoc == FX || OPS[i].assoc == FY) &&
        !strcmp(OPS[i].name, name))
      return &OPS[i];
  return NULL;
}

// ---- input cursor and error handling ----
static const char *P;
static jmp_buf err_jmp;
static char err_msg[256];

static void perr(const char *msg) {
  snprintf(err_msg, sizeof(err_msg), "%s near \"%.20s\"", msg, P);
  longjmp(err_jmp, 1);
}

static int is_symbol_char(int c) {
  return strchr("+-*/\\^<>=~:.?@#&$", c) != NULL;
}

static void skip_ws(void) {
  for (;;) {
    while (isspace((unsigned char)*P))
      P++;
    if (P[0] == '%') {
      while (*P && *P != '\n')
        P++;
    } else if (P[0] == '/' && P[1] == '*') {
      P += 2;
      while (*P && !(P[0] == '*' && P[1] == '/'))
        P++;
      if (*P)
        P += 2;
    } else
      break;
  }
}

// true if a '.' at P ends a clause (period followed by layout/EOF/%)
static int at_clause_end(void) {
  return P[0] == '.' &&
         (P[1] == '\0' || isspace((unsigned char)P[1]) || P[1] == '%');
}

// ---- per-clause variable table: reset before each clause/query
#define MAX_CVARS 512
#define MAX_VARNAME 256
static char var_names[MAX_CVARS][MAX_VARNAME];
static int32_t var_count;

static void vartab_reset(void) { var_count = 0; }

static int32_t vartab_slot(const char *name) {
  if (strcmp(name, "_") != 0) {
    for (int32_t i = 0; i < var_count; i++)
      if (!strcmp(var_names[i], name))
        return i;
  }
  if (var_count >= MAX_CVARS)
    perr("too many distinct variables in one clause");
  if (strlen(name) >= MAX_VARNAME)
    perr("variable name too long");
  strcpy(var_names[var_count], name);
  return var_count++;
}

// ---- tokens ----

static void read_while(char *buf, int (*pred)(int)) {
  size_t n = 0;
  while (pred((unsigned char)*P)) {
    if (n + 1 >= MAX_TOKEN)
      perr("token too long");
    buf[n++] = *P++;
  }
  buf[n] = '\0';
}

static int is_ident_char(int c) { return isalnum(c) || c == '_'; }

static void read_quoted(char quote, char *buf) {
  P++; // opening quote
  size_t n = 0;
  for (;;) {
    if (*P == '\0')
      perr("unterminated quoted token");
    if (*P == quote) {
      if (P[1] == quote) {
        if (n + 1 >= MAX_TOKEN)
          perr("token too long");
        buf[n++] = quote;
        P += 2;
        continue;
      }
      P++;
      break;
    }
    char v = *P;
    if (*P == '\\') {
      P++;
      char c = *P++;
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
      P++;
    if (n + 1 >= MAX_TOKEN)
      perr("token too long");
    buf[n++] = v;
  }
  buf[n] = '\0';
}

static tterm_t *parse_expr(int max_prec);
static tterm_t *parse_arg(void) {
  return parse_expr(999);
} // args stop below ','

// parses comma-separated args into caller-owned scratch
static int32_t parse_arglist(tterm_t **scratch) {
  int32_t n = 0;
  scratch[n++] = parse_arg();
  skip_ws();
  while (*P == ',') {
    P++;
    skip_ws();
    if (n >= MAX_ARITY)
      perr("too many arguments");
    scratch[n++] = parse_arg();
    skip_ws();
  }
  return n;
}

static tterm_t *parse_list(void) {
  P++; // '['
  skip_ws();
  if (*P == ']') {
    P++;
    return tt_atom("[]");
  }
  tterm_t *elems[MAX_ARITY];
  int n = 0;
  elems[n++] = parse_arg();
  skip_ws();
  tterm_t *tail = tt_atom("[]");
  while (*P == ',') {
    P++;
    skip_ws();
    if (n >= MAX_ARITY)
      perr("list literal too long");
    elems[n++] = parse_arg();
    skip_ws();
  }
  if (*P == '|') {
    P++;
    skip_ws();
    tail = parse_arg();
    skip_ws();
  }
  if (*P != ']')
    perr("expected ']'");
  P++;
  tterm_t *acc = tail;
  for (int i = n - 1; i >= 0; i--) {
    tterm_t *cons[2] = {elems[i], acc};
    acc = tt_struct(".", 2, cons);
  }
  return acc;
}

static tterm_t *parse_string(void) {
  char buf[MAX_TOKEN];
  read_quoted('"', buf);
  tterm_t *acc = tt_atom("[]");
  size_t n = strlen(buf);
  for (size_t i = n; i-- > 0;) {
    tterm_t *cons[2] = {tt_int((unsigned char)buf[i]), acc};
    acc = tt_struct(".", 2, cons);
  }
  return acc;
}

static tterm_t *parse_number(void) {
  const char *start = P;
  if (*P == '-')
    P++;
  while (isdigit((unsigned char)*P))
    P++;
  int is_float = 0;
  if (P[0] == '.' && isdigit((unsigned char)P[1])) {
    is_float = 1;
    P++;
    while (isdigit((unsigned char)*P))
      P++;
  }
  if (*P == 'e' || *P == 'E') {
    is_float = 1;
    P++;
    if (*P == '+' || *P == '-')
      P++;
    while (isdigit((unsigned char)*P))
      P++;
  }
  size_t n = (size_t)(P - start);
  char buf[64];
  if (n >= sizeof(buf))
    perr("number literal too long");
  memcpy(buf, start, n);
  buf[n] = '\0';
  return is_float ? tt_flt(strtod(buf, NULL)) : tt_int(strtoll(buf, NULL, 10));
}

static tterm_t *parse_primary(void) {
  skip_ws();
  if (*P == '\0')
    perr("unexpected end of input");
  char name[MAX_TOKEN];

  if (*P == '(') {
    P++;
    skip_ws();
    tterm_t *t = parse_expr(1200);
    skip_ws();
    if (*P != ')')
      perr("expected ')'");
    P++;
    return t;
  }
  if (*P == '[')
    return parse_list();
  if (*P == '"')
    return parse_string();
  if (*P == '!') {
    P++;
    return tt_atom("!");
  }
  if (*P == ';') {
    P++;
    return tt_atom(";");
  }
  if (*P == '\'') {
    read_quoted('\'', name);
    skip_ws();
    if (*P == '(') {
      P++;
      skip_ws();
      tterm_t *args[MAX_ARITY];
      int32_t n = parse_arglist(args);
      skip_ws();
      if (*P != ')')
        perr("expected ')'");
      P++;
      return tt_struct(name, n, args);
    }
    return tt_atom(name);
  }
  if (*P == '_' || isupper((unsigned char)*P)) {
    read_while(name, is_ident_char);
    return tt_var(vartab_slot(name));
  }
  if (isdigit((unsigned char)*P))
    return parse_number();
  if (*P == '-' && isdigit((unsigned char)P[1]))
    return parse_number();

  if (islower((unsigned char)*P)) {
    read_while(name, is_ident_char);
    if (*P == '(') {
      P++;
      skip_ws();
      tterm_t *args[MAX_ARITY];
      int32_t n = parse_arglist(args);
      skip_ws();
      if (*P != ')')
        perr("expected ')'");
      P++;
      return tt_struct(name, n, args);
    }
    const op_t *pre = find_prefix(name);
    if (pre && *P != '\0' && !at_clause_end() && *P != ')' && *P != ',' &&
        *P != ']' && *P != '|' && !find_infix(name)) {
      tterm_t *arg = parse_expr(pre->assoc == FY ? pre->pri : pre->pri - 1);
      return tt_struct(name, 1, &arg);
    }
    return tt_atom(name);
  }
  if (is_symbol_char((unsigned char)*P)) {
    read_while(name, is_symbol_char);
    const op_t *pre = find_prefix(name);
    if (pre) {
      tterm_t *arg = parse_expr(pre->assoc == FY ? pre->pri : pre->pri - 1);
      return tt_struct(name, 1, &arg);
    }
    return tt_atom(name);
  }
  perr("unexpected character");
  return NULL; // unreachable
}

// tries to read an infix operator name at the current position without
// consuming it if it doesn't turn out to be one; returns NULL if none.
static const op_t *peek_infix_op(size_t *len_out) {
  skip_ws();
  if (*P == '\0' || *P == ')' || *P == ']' || *P == '|' || at_clause_end())
    return NULL;
  if (*P == ',') {
    *len_out = 1;
    return find_infix(",");
  }
  if (*P == ';') {
    *len_out = 1;
    return find_infix(";");
  }
  if (is_symbol_char((unsigned char)*P)) {
    const char *save = P;
    char name[MAX_TOKEN];
    read_while(name, is_symbol_char);
    const op_t *op = find_infix(name);
    size_t len = strlen(name);
    P = save;
    if (op)
      *len_out = len;
    return op;
  }
  if (islower((unsigned char)*P)) {
    const char *save = P;
    char name[MAX_TOKEN];
    read_while(name, is_ident_char);
    const op_t *op = find_infix(name);
    size_t len = strlen(name);
    P = save;
    if (op)
      *len_out = len;
    return op;
  }
  return NULL;
}

static tterm_t *parse_expr(int max_prec) {
  tterm_t *left = parse_primary();
  for (;;) {
    size_t len;
    const op_t *op = peek_infix_op(&len);
    if (!op || op->pri > max_prec)
      break;
    int right_max = (op->assoc == XFY) ? op->pri : op->pri - 1;
    P += len;
    skip_ws();
    tterm_t *right = parse_expr(right_max);
    tterm_t *args[2] = {left, right};
    left = tt_struct(op->name, 2, args);
  }
  return left;
}

// ---- clause assembly ----

// flattens a right-nested ','/2 chain into an array of goals
static tterm_t **flatten_conj(tterm_t *t, int32_t *n_out) {
  tterm_t *scratch[MAX_ARITY];
  int32_t n = 0;
  while (t->tag == T_STR && t->as.str.arity == 2 &&
         !strcmp(atom_name(t->as.str.atom_id), ",")) {
    if (n >= MAX_ARITY)
      perr("clause body too long");
    scratch[n++] = t->as.str.args[0];
    t = t->as.str.args[1];
  }
  if (n >= MAX_ARITY)
    perr("clause body too long");
  scratch[n++] = t;
  tterm_t **out = arena_alloc((size_t)n * sizeof(tterm_t *));
  memcpy(out, scratch, (size_t)n * sizeof(tterm_t *));
  *n_out = n;
  return out;
}

static void run_directive(tterm_t *goal, int32_t nvars) {
  int32_t n;
  tterm_t **goals = flatten_conj(goal, &n);
  const char **names =
      arena_alloc((size_t)(nvars > 0 ? nvars : 1) * sizeof(char *));
  for (int32_t i = 0; i < nvars; i++)
    names[i] = arena_strdup(var_names[i]);
  run_query(goals, n, nvars, names, RUN_SILENT);
}

static void assemble_clause(tterm_t *t, int32_t nvars) {
  if (t->tag == T_STR && t->as.str.arity == 2 &&
      !strcmp(atom_name(t->as.str.atom_id), ":-")) {
    int32_t nbody;
    tterm_t **body = flatten_conj(t->as.str.args[1], &nbody);
    db_add(t->as.str.args[0], body, nbody, nvars);
    return;
  }
  if (t->tag == T_STR && t->as.str.arity == 1 &&
      (!strcmp(atom_name(t->as.str.atom_id), ":-") ||
       !strcmp(atom_name(t->as.str.atom_id), "?-"))) {
    run_directive(t->as.str.args[0], nvars);
    return;
  }
  db_add(t, NULL, 0, nvars); // a fact
}

bool consult_file(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) {
    char msg[300];
    snprintf(msg, sizeof msg, "cannot open %s\n", path);
    io_write_err(msg);
    return false;
  }
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);

  char *buf = arena_alloc((size_t)sz + 1); // FIXME: this is never cleaned up
  size_t got = fread(buf, 1, (size_t)sz, f);
  buf[got] = '\0';
  fclose(f);

  P = buf;
  if (setjmp(err_jmp)) {
    char msg[300 + sizeof err_msg];
    snprintf(msg, sizeof msg, "parse error in %s: %s\n", path, err_msg);
    io_write_err(msg);
    return false;
  }
  for (;;) {
    skip_ws();
    if (*P == '\0')
      break;
    vartab_reset();
    tterm_t *t = parse_expr(1200);
    skip_ws();
    if (!at_clause_end())
      perr("expected '.' to end clause");
    P++;
    assemble_clause(t, var_count);
  }
  return true;
}

bool parse_query(const char *src, tterm_t ***goals_out, int32_t *ngoals_out,
                 int32_t *nvars_out, const char ***varnames_out) {
  P = src;
  if (setjmp(err_jmp)) {
    char msg[32 + sizeof err_msg];
    snprintf(msg, sizeof msg, "parse error: %s\n", err_msg);
    io_write_err(msg);
    return false;
  }
  vartab_reset();
  tterm_t *t = parse_expr(1200);
  skip_ws();
  if (*P != '\0' && !at_clause_end())
    perr("unexpected trailing input");
  if (at_clause_end())
    P++;

  *goals_out = flatten_conj(t, ngoals_out);
  *nvars_out = var_count;
  const char **names =
      arena_alloc((size_t)(var_count > 0 ? var_count : 1) * sizeof(char *));
  for (int32_t i = 0; i < var_count; i++)
    names[i] = arena_strdup(var_names[i]);
  *varnames_out = names;
  return true;
}

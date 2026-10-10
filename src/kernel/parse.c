#include "parse.h"
#include "arena.h"
#include "atoms.h"
#include "chars.h"
#include "ctx.h"
#include "embedded.h"
#include "fmt.h"
#include "heap.h"
#include "io.h"
#include "mem.h"
#include "platform.h"
#include "solve.h"
#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

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
    {"mod", 400, YFX}, {"rem", 400, YFX},  {"//", 400, YFX},
    {"**", 200, XFX},  {"-", 200, FY},     {"+", 200, FY},
    {"\\/", 500, YFX}, {"xor", 400, YFX},  {"<<", 400, YFX},
    {">>", 400, YFX},  {"/\\", 400, YFX},  {"\\", 200, FY},
    {"^", 200, XFY},
};
#define NOPS (int)(sizeof(OPS) / sizeof(OPS[0]))

// The standard table seeds '$$op'/3, which the parser then reads alone,
// so op/3 can redefine or remove these.
// These could be in Prolog, but we want OSoT, maybe fix later
void ops_seed(trilog_t *T) {
  static const char *const type_names[] = {"xfx", "xfy", "yfx", "fx", "fy"};
  for (int i = 0; i < NOPS; i++) {
    tterm_t *args[3] = {tt_int(T, OPS[i].pri),
                        tt_atom(T, type_names[OPS[i].assoc]),
                        tt_atom(T, OPS[i].name)};
    db_add(T, tt_struct(T, "$$op", 3, args), NULL, 0, 0, 0);
  }
}

static int find_infix(trilog_t *T, const char *name, op_t *out) {
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
  fmt(T->err_msg, sizeof(T->err_msg), "%s near \"%.20s\"", msg, T->P);
  longjmp(T->err_jmp, 1);
}

static int is_symbol_char(int c) {
  return c != '\0' && strchr("+-*/\\^<>=~:.?@#&$", c) != NULL;
}

static void skip_ws(trilog_t *T) {
  for (;;) {
    while (ascii_space((unsigned char)*T->P))
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
         (T->P[1] == '\0' || ascii_space((unsigned char)T->P[1]) ||
          T->P[1] == '%');
}

// ---- per-clause variable table: reset before each clause/query

static void vartab_reset(trilog_t *T) { T->var_count = 0; }

static int32_t vartab_slot(trilog_t *T, const char *name) {
  int32_t id = atom_intern(T, name);
  if (strcmp(name, "_") != 0) {
    for (int32_t i = 0; i < T->var_count; i++)
      if (T->var_names[i] == id)
        return i;
  }
  mem_reserve(T, (void **)&T->var_names, &T->var_names_cap,
              (size_t)(T->var_count + 1) * sizeof(int32_t));
  T->var_names[T->var_count] = id;
  return T->var_count++;
}

// ---- tokens ----

static void tok_put(trilog_t *T, size_t n, char c) {
  mem_reserve(T, (void **)&T->tok, &T->tok_cap, n + 2);
  T->tok[n] = c;
}

static const char *read_while(trilog_t *T, int (*pred)(int)) {
  size_t n = 0;
  while (pred((unsigned char)*T->P))
    tok_put(T, n++, *T->P++);
  tok_put(T, n, '\0');
  return T->tok;
}

static int is_ident_char(int c) { return ascii_alnum(c) || c == '_'; }

static const char *read_quoted(trilog_t *T, char quote) {
  T->P++; // opening quote
  size_t n = 0;
  for (;;) {
    if (*T->P == '\0')
      perr(T, "unterminated quoted token");
    if (*T->P == quote) {
      if (T->P[1] == quote) {
        tok_put(T, n++, quote);
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
    tok_put(T, n++, v);
  }
  tok_put(T, n, '\0');
  return T->tok;
}

static const char *read_name(trilog_t *T, int (*pred)(int)) {
  return atom_name(T, atom_intern(T, read_while(T, pred)));
}

static void pstack_push(trilog_t *T, tterm_t *t) {
  mem_reserve(T, (void **)&T->pstack, &T->pstack_cap,
              (T->psp + 1) * sizeof(tterm_t *));
  T->pstack[T->psp++] = t;
}

static tterm_t *parse_string(trilog_t *T) {
  const char *buf = read_quoted(T, '"');
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
  while (ascii_digit((unsigned char)*T->P))
    T->P++;
  int is_float = 0;
  if (T->P[0] == '.' && ascii_digit((unsigned char)T->P[1])) {
    is_float = 1;
    T->P++;
    while (ascii_digit((unsigned char)*T->P))
      T->P++;
  }
  if (*T->P == 'e' || *T->P == 'E') {
    is_float = 1;
    T->P++;
    if (*T->P == '+' || *T->P == '-')
      T->P++;
    while (ascii_digit((unsigned char)*T->P))
      T->P++;
  }
  size_t n = (size_t)(T->P - start);
  char buf[64];
  if (n >= sizeof(buf))
    perr(T, "number literal too long");
  memcpy(buf, start, n);
  buf[n] = '\0';
  if (is_float)
    return tt_flt(T, trilog_parse_float(buf, NULL));
  int64_t v;
  if (!parse_int(buf, NULL, &v))
    perr(T, "integer literal out of range");
  return tt_int(T, v);
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
    const char *name = read_while(T, is_symbol_char);
    int found = find_infix(T, name, out);
    size_t len = (size_t)(T->P - save);
    T->P = save;
    if (found)
      *len_out = len;
    return found;
  }
  if (ascii_lower((unsigned char)*T->P)) {
    const char *save = T->P;
    const char *name = read_while(T, is_ident_char);
    int found = find_infix(T, name, out);
    size_t len = (size_t)(T->P - save);
    T->P = save;
    if (found)
      *len_out = len;
    return found;
  }
  return 0;
}

// Frames: (kind, a, b, c).
enum {
  K_DONE,
  K_INFIX, // a = prec
  K_RIGHT, // a = prec, b = op, c = left
  K_PAREN,
  K_BRACE,
  K_ARGS,   // a = name, b = base, c = argc
  K_LIST,   // b = base
  K_TAIL,   // b = base
  K_PREFIX, // a = op
};

static void frame_push(trilog_t *T, size_t kind, size_t a, size_t b, size_t c) {
  wstack_push(T, kind);
  wstack_push(T, a);
  wstack_push(T, b);
  wstack_push(T, c);
}

#define PTR(p) ((size_t)(uintptr_t)(p))
#define TERM(x) ((tterm_t *)(uintptr_t)(x))
#define NAME(x) ((const char *)(uintptr_t)(x))

static void expect(trilog_t *T, char c, const char *msg) {
  skip_ws(T);
  if (*T->P != c)
    perr(T, msg);
  T->P++;
}

static tterm_t *build_list(trilog_t *T, size_t base, tterm_t *tail) {
  tterm_t *acc = tail;
  for (size_t i = T->psp; i-- > base;) {
    tterm_t *cons[2] = {T->pstack[i], acc};
    acc = tt_struct(T, ".", 2, cons);
  }
  T->psp = base;
  return acc;
}

static int prefix_applies(trilog_t *T) {
  return *T->P != '\0' && !at_clause_end(T) && *T->P != ')' && *T->P != ',' &&
         *T->P != ']' && *T->P != '|';
}

static tterm_t *parse_expr(trilog_t *T, int max_prec) {
  size_t wbase = T->wsp;
  int prec = max_prec;
  tterm_t *v;
  frame_push(T, K_DONE, 0, 0, 0);

start:
  frame_push(T, K_INFIX, (size_t)prec, 0, 0);
  skip_ws(T);
  if (*T->P == '\0')
    perr(T, "unexpected end of input");
  switch (*T->P) {
  case '(':
    T->P++;
    skip_ws(T);
    frame_push(T, K_PAREN, 0, 0, 0);
    prec = 1200;
    goto start;
  case '[':
    T->P++;
    skip_ws(T);
    if (*T->P == ']') {
      T->P++;
      v = tt_atom(T, "[]");
      goto produced;
    }
    frame_push(T, K_LIST, 0, T->psp, 0);
    prec = 999;
    goto start;
  case '{':
    T->P++;
    skip_ws(T);
    if (*T->P == '}') {
      T->P++;
      v = tt_atom(T, "{}");
      goto produced;
    }
    frame_push(T, K_BRACE, 0, 0, 0);
    prec = 1200;
    goto start;
  case '"':
    v = parse_string(T);
    goto produced;
  case '!':
    T->P++;
    v = tt_atom(T, "!");
    goto produced;
  case ';':
    T->P++;
    v = tt_atom(T, ";");
    goto produced;
  case '\'': {
    const char *name = atom_name(T, atom_intern(T, read_quoted(T, '\'')));
    skip_ws(T);
    if (*T->P == '(')
      goto compound_name;
    v = tt_atom(T, name);
    goto produced;
  compound_name:
    T->P++;
    skip_ws(T);
    frame_push(T, K_ARGS, PTR(name), T->psp, 0);
    prec = 999;
    goto start;
  }
  default:
    break;
  }
  if (*T->P == '_' || ascii_upper((unsigned char)*T->P)) {
    v = tt_var(T, vartab_slot(T, read_while(T, is_ident_char)));
    goto produced;
  }
  if (ascii_digit((unsigned char)*T->P) ||
      (*T->P == '-' && ascii_digit((unsigned char)T->P[1]))) {
    v = parse_number(T);
    goto produced;
  }
  {
    int lower = ascii_lower((unsigned char)*T->P);
    if (!lower && !is_symbol_char((unsigned char)*T->P))
      perr(T, "unexpected character");
    const char *name = read_name(T, lower ? is_ident_char : is_symbol_char);
    if (*T->P == '(') {
      T->P++;
      skip_ws(T);
      frame_push(T, K_ARGS, PTR(name), T->psp, 0);
      prec = 999;
      goto start;
    }
    op_t pre, dummy;
    if (find_prefix(T, name, &pre) && prefix_applies(T) &&
        !(lower && find_infix(T, name, &dummy))) {
      frame_push(T, K_PREFIX, PTR(name), 0, 0);
      prec = pre.assoc == FY ? pre.pri : pre.pri - 1;
      goto start;
    }
    v = tt_atom(T, name);
    goto produced;
  }

produced:
  for (;;) {
    size_t c = T->wstack[--T->wsp];
    size_t b = T->wstack[--T->wsp];
    size_t a = T->wstack[--T->wsp];
    size_t kind = T->wstack[--T->wsp];
    switch (kind) {
    case K_DONE:
      T->wsp = wbase;
      return v;
    case K_RIGHT: {
      tterm_t *args[2] = {TERM(c), v};
      v = tt_struct(T, NAME(b), 2, args);
    }
      // fall through
    case K_INFIX: {
      size_t len;
      op_t op;
      if (!peek_infix_op(T, &len, &op) || op.pri > (int)a)
        continue;
      T->P += len;
      skip_ws(T);
      frame_push(T, K_RIGHT, a, PTR(op.name), PTR(v));
      prec = op.assoc == XFY ? op.pri : op.pri - 1;
      goto start;
    }
    case K_PAREN:
      expect(T, ')', "expected ')'");
      continue;
    case K_BRACE: {
      expect(T, '}', "expected '}'");
      tterm_t *args[1] = {v};
      v = tt_struct(T, "{}", 1, args);
      continue;
    }
    case K_ARGS:
      pstack_push(T, v);
      c++;
      skip_ws(T);
      if (*T->P == ',') {
        T->P++;
        skip_ws(T);
        frame_push(T, K_ARGS, a, b, c);
        prec = 999;
        goto start;
      }
      expect(T, ')', "expected ')'");
      v = tt_struct(T, NAME(a), (int32_t)c, T->pstack + b);
      T->psp = b;
      continue;
    case K_LIST:
      pstack_push(T, v);
      skip_ws(T);
      if (*T->P == ',' || *T->P == '|') {
        frame_push(T, *T->P == ',' ? K_LIST : K_TAIL, 0, b, 0);
        T->P++;
        skip_ws(T);
        prec = 999;
        goto start;
      }
      expect(T, ']', "expected ']'");
      v = build_list(T, b, tt_atom(T, "[]"));
      continue;
    case K_TAIL:
      expect(T, ']', "expected ']'");
      v = build_list(T, b, v);
      continue;
    case K_PREFIX:
      v = tt_struct(T, NAME(a), 1, &v);
      continue;
    }
  }
}

// ---- clause assembly ----

// flattens a right-nested ','/2 chain into an array of goals
static tterm_t **flatten_conj(trilog_t *T, tterm_t *t, int32_t *n_out) {
  size_t base = T->psp;
  int32_t n = 0;
  while (t->tag == T_STR && t->as.str.arity == 2 &&
         t->as.str.atom_id == atom_comma) {
    pstack_push(T, t->as.str.args[0]);
    n++;
    t = t->as.str.args[1];
  }
  pstack_push(T, t);
  n++;
  tterm_t **out = arena_alloc(T, (size_t)n * sizeof(tterm_t *));
  memcpy(out, T->pstack + base, (size_t)n * sizeof(tterm_t *));
  T->psp = base;
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
  // The result is never longer than the input, so it is rebuilt in place.
  size_t r = 0, w = 0, root = path[0] == '/';
  w = root;
  while (path[r]) {
    while (path[r] == '/')
      r++;
    size_t start = r;
    while (path[r] && path[r] != '/')
      r++;
    size_t k = r - start;
    if (k == 0 || (k == 1 && path[start] == '.'))
      continue;
    if (k == 2 && path[start] == '.' && path[start + 1] == '.' && root &&
        w == root)
      continue;
    if (k == 2 && path[start] == '.' && path[start + 1] == '.' && w > root) {
      size_t last = w;
      while (last > 0 && path[last - 1] != '/')
        last--;
      if (!(w - last == 2 && path[last] == '.' && path[last + 1] == '.')) {
        w = last > root ? last - 1 : root;
        continue;
      }
    }
    if (w > root)
      path[w++] = '/';
    memmove(path + w, path + start, k);
    w += k;
  }
  path[w] = '\0';
}

#ifndef PATH_CAP
#define PATH_CAP 4096
#endif

static void path_buffers(trilog_t *T) {
  if (!T->path_buf) {
    T->path_buf = mem_grow_n(T, NULL, PATH_CAP, 1);
    T->path_tmp = mem_grow_n(T, NULL, PATH_CAP, 1);
  }
}

// the embedded text for a relative path, or NULL. On a hit, resolved gets
// the "embedded:" name that later relative consults resolve against.
static const char *find_embedded(trilog_t *T, const char *path, char *resolved,
                                 size_t cap) {
  char *key = T->path_tmp;
  if (key != path)
    fmt(key, PATH_CAP, "%s", path);
  normalize_path(key);
  for (const embedded_file *e = embedded_files; e->path; e++)
    if (!strcmp(e->path, key)) {
      fmt(resolved, cap, EMBED_PREFIX "%s", e->path);
      return e->data;
    }
  return NULL;
}

static size_t read_file_pass(trilog_t *T, const char *path, char *out,
                             size_t cap) {
  void *h = io_file_open(T, path, "rb");
  if (!h)
    return (size_t)-1;
  char chunk[256]; // only for the sizing pass; the copy pass reads in place
  size_t len = 0;
  long got;
  for (;;) {
    char *dst = out ? out + len : chunk;
    size_t room = out ? cap - len : sizeof chunk;
    if (room == 0)
      break;
    if ((got = io_file_read(T, h, dst, room)) <= 0)
      break;
    len += (size_t)got;
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

static bool file_exists(trilog_t *T, const char *path) {
  void *h = io_file_open(T, path, "rb");
  if (!h)
    return false;
  io_file_close(T, h);
  return true;
}

// Relative paths are made absolute, so one file has one name.
static bool resolve_disk(trilog_t *T, const char *path, char *out, size_t cap) {
  if (!file_exists(T, path))
    return false;
  char *abs = T->path_tmp;
  if (path[0] != '/' && io_cwd(T, abs, PATH_CAP)) {
    size_t n = strlen(abs);
    fmt(abs + n, PATH_CAP - n, "/%s", path);
    path = abs;
  }
  if (out != path)
    fmt(out, cap, "%s", path);
  normalize_path(out);
  return true;
}

// A relative path consulted from inside a file resolves against that file's
// directory first, then the current directory, then the embedded libraries.
static bool resolve_source(trilog_t *T, const char *path, char *out,
                           size_t cap) {
  path_buffers(T);
  if (!strncmp(path, EMBED_PREFIX, EMBED_PREFIX_LEN))
    return find_embedded(T, path + EMBED_PREFIX_LEN, out, cap) != NULL;
  const char *slash = T->consulting ? strrchr(T->consulting, '/') : NULL;
  if (path[0] != '/' && slash) {
    fmt(out, cap, "%.*s/%s", (int)(slash - T->consulting), T->consulting, path);
    if (!strncmp(out, EMBED_PREFIX, EMBED_PREFIX_LEN)) {
      fmt(T->path_tmp, PATH_CAP, "%s", out + EMBED_PREFIX_LEN);
      if (find_embedded(T, T->path_tmp, out, cap))
        return true;
    } else if (resolve_disk(T, out, out, cap)) {
      return true;
    }
  }
  if (resolve_disk(T, path, out, cap))
    return true;
  return path[0] != '/' && find_embedded(T, path, out, cap);
}

const char *source_path(trilog_t *T, const char *path) {
  path_buffers(T);
  return resolve_source(T, path, T->path_buf, PATH_CAP) ? T->path_buf : NULL;
}

static const char *consult_text(trilog_t *T, const char *path, char *resolved,
                                size_t cap) {
  if (!resolve_source(T, path, resolved, cap))
    return NULL;
  if (!strncmp(resolved, EMBED_PREFIX, EMBED_PREFIX_LEN))
    return find_embedded(T, resolved + EMBED_PREFIX_LEN, resolved, cap);
  return read_whole_file(T, resolved);
}

static bool consult_source(trilog_t *T, const char *text, const char *path);

// Re-entrant: a consult/1 directive inside the file saves and restores the
// outer file's parse state.
static bool consult_nested(trilog_t *T, const char *text, const char *file,
                           const char *name) {
  const char *saved_P = T->P, *saved_consulting = T->consulting;
  int32_t saved_atom = T->consulting_atom;
  size_t saved_psp = T->psp;
  jmp_buf saved_jmp;
  memcpy(saved_jmp, T->err_jmp, sizeof(jmp_buf));
  T->consulting = file;
  T->consulting_atom = file ? atom_intern(T, file) : -1;
  bool ok = consult_source(T, text, name);
  T->consulting = saved_consulting;
  T->consulting_atom = saved_atom;
  T->P = saved_P;
  T->psp = saved_psp;
  memcpy(T->err_jmp, saved_jmp, sizeof(jmp_buf));
  return ok;
}

bool consult_file(trilog_t *T, const char *path, int32_t *source) {
  path_buffers(T);
  const char *text = consult_text(T, path, T->path_buf, PATH_CAP);
  if (!text) {
    io_write_err(T, "cannot open ");
    io_write_err(T, path);
    io_write_err(T, "\n");
    return false;
  }
  // The path buffers are reused by nested consults; the atom's name is not.
  int32_t atom = atom_intern(T, T->path_buf);
  const char *resolved = atom_name(T, atom);
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
    io_write_err(T, "parse error in ");
    io_write_err(T, path);
    io_write_err(T, ": ");
    io_write_err(T, T->err_msg);
    io_write_err(T, "\n");
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
  T->psp = 0;
  if (setjmp(T->err_jmp)) {
    io_write_err(T, "parse error: ");
    io_write_err(T, T->err_msg);
    io_write_err(T, "\n");
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
    names[i] = atom_name(T, T->var_names[i]);
  *varnames_out = names;
  return true;
}

static bool parse_term_from_string_(trilog_t *T, const char *src,
                                    tterm_t **term_out, int32_t *nvars_out,
                                    const char ***varnames_out);

bool parse_term_from_string(trilog_t *T, const char *src, tterm_t **term_out,
                            int32_t *nvars_out, const char ***varnames_out) {
  const char *saved_P = T->P;
  size_t saved_psp = T->psp;
  jmp_buf saved_jmp;
  memcpy(saved_jmp, T->err_jmp, sizeof(jmp_buf));
  bool ok = parse_term_from_string_(T, src, term_out, nvars_out, varnames_out);
  T->P = saved_P;
  T->psp = saved_psp;
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
    names[i] = atom_name(T, T->var_names[i]);
  *varnames_out = names;
  return true;
}

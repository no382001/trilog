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

typedef enum { XFX, XFY, YFX, FX, FY, XF, YF } assoc_t;
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
    {"^", 200, XFY},   {":", 600, XFY},
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

static int find_postfix(trilog_t *T, const char *name, op_t *out) {
  int pri, assoc_code;
  int32_t id = atom_intern(T, name);
  if (op_lookup_postfix(T, id, &pri, &assoc_code)) {
    out->name = atom_name(T, id);
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

static int is_symbol_char(int c) { return ascii_symbol(c); }

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

// The escape after a backslash: a control or meta escape, octal \NNN\ or
// hex \xHH\.
static int read_escape(trilog_t *T) {
  int c = (unsigned char)*T->P;
  if (c == '\n' || c == '\\' || c == '\'' || c == '"' || c == '`') {
    T->P++;
    return c == '\n' ? -1 : c;
  }
  int e = escape_char(c);
  if (e >= 0) {
    T->P++;
    return e;
  }
  int base = 8;
  if (c == 'x') {
    base = 16;
    T->P++;
  }
  const char *start = T->P;
  long v = 0;
  for (;;) {
    int d = *T->P;
    int digit = ascii_digit(d) && d - '0' < base     ? d - '0'
                : base == 16 && d >= 'a' && d <= 'f' ? d - 'a' + 10
                : base == 16 && d >= 'A' && d <= 'F' ? d - 'A' + 10
                                                     : -1;
    if (digit < 0)
      break;
    v = v * base + digit;
    if (v > 0x10FFFF)
      perr(T, "character code out of range in escape");
    T->P++;
  }
  if (T->P == start || *T->P != '\\')
    perr(T, "undefined escape sequence");
  T->P++;
  return (int)v;
}

// Codes above 127 are stored as their UTF-8 bytes, as source text is.
static size_t put_code(trilog_t *T, size_t n, int c) {
  if (c < 0x80) {
    tok_put(T, n++, (char)c);
  } else if (c < 0x800) {
    tok_put(T, n++, (char)(0xC0 | c >> 6));
    tok_put(T, n++, (char)(0x80 | (c & 0x3F)));
  } else if (c < 0x10000) {
    tok_put(T, n++, (char)(0xE0 | c >> 12));
    tok_put(T, n++, (char)(0x80 | (c >> 6 & 0x3F)));
    tok_put(T, n++, (char)(0x80 | (c & 0x3F)));
  } else {
    tok_put(T, n++, (char)(0xF0 | c >> 18));
    tok_put(T, n++, (char)(0x80 | (c >> 12 & 0x3F)));
    tok_put(T, n++, (char)(0x80 | (c >> 6 & 0x3F)));
    tok_put(T, n++, (char)(0x80 | (c & 0x3F)));
  }
  return n;
}

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
    if (*T->P == '\n' || *T->P == '\t')
      perr(T, "layout other than a space inside quoted text");
    if (*T->P != '\\') {
      tok_put(T, n++, *T->P++);
      continue;
    }
    T->P++;
    int c = read_escape(T);
    if (c == 0)
      perr(T, "\\0\\ cannot be stored in quoted text");
    if (c > 0)
      n = put_code(T, n, c);
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

// Without a character after it 0' is 0 and a quoted atom, so 0''1 is 0 '' 1.
static bool char_code_follows(const char *p) {
  if (p[0] == '\0' || (p[0] == '\\' && p[1] == '\n'))
    return false;
  return p[0] != '\'' || p[1] == '\'';
}

// 0'c: the character code of c. A doubled quote (0''') is a literal
// quote, matching how a quoted atom escapes one; not a quoted-atom opener.
static int parse_char_code(trilog_t *T) {
  T->P += 2; // "0'"
  if (*T->P == '\\') {
    T->P++;
    return read_escape(T);
  }
  if (T->P[0] == '\'' && T->P[1] == '\'') {
    T->P += 2;
    return '\'';
  }
  if (*T->P == '\n' || *T->P == '\t')
    perr(T, "layout other than a space after 0'");
  return (unsigned char)*T->P++;
}

static int base_digit(int c, int base) {
  int d = ascii_digit(c)         ? c - '0'
          : c >= 'a' && c <= 'z' ? c - 'a' + 10
          : c >= 'A' && c <= 'Z' ? c - 'A' + 10
                                 : base;
  return d < base ? d : -1;
}

static int radix(int c) {
  return c == 'x' ? 16 : c == 'o' ? 8 : c == 'b' ? 2 : 0;
}

#define INTEGER_OVERFLOW "integer literal out of range"
#define FLOAT_OVERFLOW "float literal out of range"

static tterm_t *parse_number(trilog_t *T, bool negative) {
  if (T->P[0] == '0' && T->P[1] == '\'' && char_code_follows(T->P + 2)) {
    int code = parse_char_code(T);
    return tt_int(T, negative ? -code : code);
  }
  int base = T->P[0] == '0' ? radix(T->P[1]) : 0;
  if (base && base_digit((unsigned char)T->P[2], base) >= 0) {
    T->P += 2;
    int64_t v = 0;
    for (int d; (d = base_digit((unsigned char)*T->P, base)) >= 0; T->P++)
      if (__builtin_mul_overflow(v, base, &v) ||
          __builtin_add_overflow(v, negative ? -d : d, &v))
        perr(T, INTEGER_OVERFLOW);
    return tt_int(T, v);
  }
  char buf[64];
  size_t n = 0;
  if (negative)
    buf[n++] = '-';
  const char *start = T->P;
  while (ascii_digit((unsigned char)*T->P))
    T->P++;
  bool is_float = T->P[0] == '.' && ascii_digit((unsigned char)T->P[1]);
  if (is_float) {
    T->P++;
    while (ascii_digit((unsigned char)*T->P))
      T->P++;
    const char *e = T->P;
    if (*e == 'e' || *e == 'E') {
      e += e[1] == '+' || e[1] == '-' ? 2 : 1;
      if (ascii_digit((unsigned char)*e)) {
        T->P = e;
        while (ascii_digit((unsigned char)*T->P))
          T->P++;
      }
    }
  }
  if ((size_t)(T->P - start) >= sizeof buf - n)
    perr(T, "number literal too long");
  memcpy(buf + n, start, (size_t)(T->P - start));
  buf[n + (size_t)(T->P - start)] = '\0';
  if (is_float) {
    double v = trilog_parse_float(buf, NULL);
    if (__builtin_isinf(v))
      perr(T, FLOAT_OVERFLOW);
    return tt_flt(T, v);
  }
  int64_t v;
  if (!parse_int(buf, NULL, &v))
    perr(T, INTEGER_OVERFLOW);
  return tt_int(T, v);
}

// The standard reads a '-' name token before a number as its sign: - 1 is -1.
static bool negative_number_follows(trilog_t *T) {
  const char *save = T->P;
  skip_ws(T);
  if (ascii_digit((unsigned char)*T->P))
    return true;
  T->P = save;
  return false;
}

// tries to read an operator name that find accepts at the current position,
// without consuming it; returns 0 if none.
static int peek_op(trilog_t *T, size_t *len_out, op_t *out,
                   int (*find)(trilog_t *, const char *, op_t *)) {
  skip_ws(T);
  if (*T->P == '\0' || *T->P == ')' || *T->P == ']' || *T->P == '|' ||
      at_clause_end(T))
    return 0;
  if (*T->P == ',') {
    *len_out = 1;
    return find(T, ",", out);
  }
  if (*T->P == ';') {
    *len_out = 1;
    return find(T, ";", out);
  }
  if (*T->P == '\'') {
    const char *save = T->P;
    const char *name = read_quoted(T, '\'');
    int found = find(T, name, out);
    size_t len = (size_t)(T->P - save);
    T->P = save;
    if (found)
      *len_out = len;
    return found;
  }
  if (is_symbol_char((unsigned char)*T->P)) {
    const char *save = T->P;
    const char *name = read_while(T, is_symbol_char);
    int found = find(T, name, out);
    size_t len = (size_t)(T->P - save);
    T->P = save;
    if (found)
      *len_out = len;
    return found;
  }
  if (ascii_lower((unsigned char)*T->P)) {
    const char *save = T->P;
    const char *name = read_while(T, is_ident_char);
    int found = find(T, name, out);
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
  K_RIGHT, // a = prec | op priority << 16, b = op, c = left
  K_PAREN,
  K_BRACE,
  K_ARGS,   // a = name, b = base, c = argc
  K_LIST,   // b = base
  K_TAIL,   // b = base
  K_PREFIX, // a = op, b = its priority
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

// vpri is the priority of the term v just read: an operator's, or 0. It must
// fit the operand an infix or postfix operator after it takes, so a = b = c
// is a syntax error.
static tterm_t *parse_expr(trilog_t *T, int max_prec) {
  size_t wbase = T->wsp;
  int prec = max_prec, vpri = 0;
  tterm_t *v;
  frame_push(T, K_DONE, 0, 0, 0);

start:
  vpri = 0;
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
      if (*T->P == '(') {
        T->P++;
        skip_ws(T);
        frame_push(T, K_ARGS, PTR("[]"), T->psp, 0);
        prec = 999;
        goto start;
      }
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
      if (*T->P == '(') {
        T->P++;
        skip_ws(T);
        frame_push(T, K_ARGS, PTR("{}"), T->psp, 0);
        prec = 999;
        goto start;
      }
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
    if (*T->P == '(') {
      T->P++;
      skip_ws(T);
      frame_push(T, K_ARGS, PTR(";"), T->psp, 0);
      prec = 999;
      goto start;
    }
    v = tt_atom(T, ";");
    goto produced;
  case '\'': {
    const char *name = atom_name(T, atom_intern(T, read_quoted(T, '\'')));
    if (!strcmp(name, "-") && negative_number_follows(T)) {
      v = parse_number(T, true);
      goto produced;
    }
    skip_ws(T);
    if (*T->P == '(')
      goto compound_name;
    op_t pre;
    if (find_prefix(T, name, &pre) && prefix_applies(T)) {
      frame_push(T, K_PREFIX, PTR(name), (size_t)pre.pri, 0);
      prec = pre.assoc == FY ? pre.pri : pre.pri - 1;
      goto start;
    }
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
  if (ascii_digit((unsigned char)*T->P)) {
    v = parse_number(T, false);
    goto produced;
  }
  if (*T->P == '-' && ascii_digit((unsigned char)T->P[1])) {
    T->P++;
    v = parse_number(T, true);
    goto produced;
  }
  {
    int lower = ascii_lower((unsigned char)*T->P);
    if (!lower && !is_symbol_char((unsigned char)*T->P))
      perr(T, "unexpected character");
    const char *name = read_name(T, lower ? is_ident_char : is_symbol_char);
    if (!strcmp(name, "-") && *T->P != '(' && negative_number_follows(T)) {
      v = parse_number(T, true);
      goto produced;
    }
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
      frame_push(T, K_PREFIX, PTR(name), (size_t)pre.pri, 0);
      prec = pre.assoc == FY ? pre.pri : pre.pri - 1;
      goto start;
    }
    v = tt_atom(T, name);
    // An operator as a plain atom cannot be an operand without brackets.
    if (find_prefix(T, name, &dummy) || find_infix(T, name, &dummy) ||
        find_postfix(T, name, &dummy))
      vpri = 1201;
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
      vpri = (int)(a >> 16);
      a &= 0xFFFF;
    }
      // fall through
    case K_INFIX: {
      size_t len;
      op_t op;
      while (peek_op(T, &len, &op, find_postfix) && op.pri <= (int)a &&
             vpri <= (op.assoc == YF ? op.pri : op.pri - 1)) {
        T->P += len;
        v = tt_struct(T, op.name, 1, &v);
        vpri = op.pri;
      }
      if (!peek_op(T, &len, &op, find_infix) || op.pri > (int)a ||
          vpri > (op.assoc == YFX ? op.pri : op.pri - 1))
        continue;
      T->P += len;
      skip_ws(T);
      frame_push(T, K_RIGHT, a | (size_t)op.pri << 16, PTR(op.name), PTR(v));
      prec = op.assoc == XFY ? op.pri : op.pri - 1;
      goto start;
    }
    case K_PAREN:
      expect(T, ')', "expected ')'");
      vpri = 0;
      continue;
    case K_BRACE: {
      expect(T, '}', "expected '}'");
      tterm_t *args[1] = {v};
      v = tt_struct(T, "{}", 1, args);
      vpri = 0;
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
      vpri = 0;
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
      vpri = 0;
      continue;
    case K_TAIL:
      expect(T, ']', "expected ']'");
      v = build_list(T, b, v);
      vpri = 0;
      continue;
    case K_PREFIX:
      v = tt_struct(T, NAME(a), 1, &v);
      vpri = (int)b;
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

static int first_solution(void *ud, int has_more) {
  (void)ud;
  (void)has_more;
  return 0;
}

static bool is_load_error(trilog_t *T, size_t ball) {
  size_t b = heap_deref(T, ball);
  if (T->heap[b].tag != TAG_STR)
    return false;
  size_t f = T->heap[b].as.ptr;
  if (T->heap[f].as.func.atom_id != atom_error ||
      T->heap[f].as.func.arity != 2)
    return false;
  size_t c = heap_deref(T, f + 2);
  if (T->heap[c].tag != TAG_STR)
    return false;
  size_t cf = T->heap[c].as.ptr;
  size_t n = heap_deref(T, cf + 1), a = heap_deref(T, cf + 2);
  return T->heap[cf].as.func.atom_id == atom_slash &&
         T->heap[cf].as.func.arity == 2 && T->heap[n].tag == TAG_ATOM &&
         T->heap[n].as.atom_id == atom_load && T->heap[a].tag == TAG_INT &&
         T->heap[a].as.ival == 1;
}

// A directive shares no variables with the code that loads it, so what it
// left on the heap is garbage, except a load error that '$$consult' raises.
static void run_directive(trilog_t *T, tterm_t *goal, int32_t nvars) {
  int32_t n;
  tterm_t **goals = flatten_conj(T, goal, &n);
  size_t hmark = heap_mark(T), tmark = trail_mark(T),
         cmark = catch_stack_size(T);
  if (run_query(T, goals, n, nvars, first_solution, NULL) == QUERY_ERROR) {
    if (query_error_ball(T) != (size_t)-1 &&
        is_load_error(T, query_error_ball(T))) {
      T->load_error_ball = query_error_ball(T);
      return;
    }
    io_write_err(T, "uncaught exception: ");
    print_term_via(T, query_error_ball(T), 0, io_write_err);
    io_write_err(T, "\n");
  }
  catch_stack_set_size(T, cmark);
  trail_release(T, tmark);
  heap_release(T, hmark);
}

static bool decl_has(const pred_decl_t *d, int32_t n, int32_t id,
                     int32_t arity) {
  for (int32_t i = 0; i < n; i++)
    if (d[i].pred_id == id && d[i].pred_arity == arity)
      return true;
  return false;
}

static bool callable_name(const tterm_t *t, int32_t *id, int32_t *arity) {
  if (t->tag == T_ATOM) {
    *id = t->as.atom_id;
    *arity = 0;
    return true;
  }
  if (t->tag == T_STR) {
    *id = t->as.str.atom_id;
    *arity = t->as.str.arity;
    return true;
  }
  return false;
}

static void rename_callable(tterm_t *t, int32_t id) {
  if (t->tag == T_ATOM)
    t->as.atom_id = id;
  else
    t->as.str.atom_id = id;
}

// A head the module does not export, and that is not dynamic, is private.
static void module_define(trilog_t *T, tterm_t *t, int32_t extra) {
  int32_t id, arity;
  if (!callable_name(t, &id, &arity))
    return;
  arity += extra;
  if (decl_has(T->module_exports, T->module_nexports, id, arity) ||
      db_is_dynamic(T, id, arity))
    return;
  if (!decl_has(T->module_private, T->module_nprivate, id, arity)) {
    if (T->module_nprivate == T->module_private_cap) {
      int32_t cap = T->module_private_cap ? T->module_private_cap * 2 : 16;
      T->module_private =
          mem_grow_n(T, T->module_private, (size_t)cap, sizeof(pred_decl_t));
      T->module_private_cap = cap;
    }
    T->module_private[T->module_nprivate++] = (pred_decl_t){id, arity};
  }
  rename_callable(t, module_qualified(T, T->module_id, id, true));
}

static void module_ref(trilog_t *T, tterm_t *t, int32_t extra) {
  int32_t id, arity;
  if (callable_name(t, &id, &arity) &&
      decl_has(T->module_private, T->module_nprivate, id, arity + extra))
    rename_callable(t, module_qualified(T, T->module_id, id, true));
}

static void module_goal(trilog_t *T, tterm_t **slot);
static void module_dcg(trilog_t *T, tterm_t **slot);
static bool caller_goal(trilog_t *T, const tterm_t *t);

// An unbound goal in a module runs as Module:Goal, so it finds the module's
// private predicates once it is bound.
static void module_wrap(trilog_t *T, tterm_t **slot) {
  tterm_t *args[2] = {tt_atom(T, atom_name(T, T->module_id)), *slot};
  *slot = tt_struct(T, ":", 2, args);
}

// A closure called with `extra` more arguments.
static void module_closure(trilog_t *T, tterm_t **slot, int32_t extra) {
  if ((*slot)->tag == T_VAR) {
    if (!caller_goal(T, *slot))
      module_wrap(T, slot);
  }
  else if (extra == 0)
    module_goal(T, slot);
  else
    module_ref(T, *slot, extra);
}

static void module_meta_args(trilog_t *T, tterm_t *t) {
  tterm_t *specs = db_meta_specs(T, t->as.str.atom_id, t->as.str.arity);
  tterm_t **a = t->as.str.args;
  for (int32_t i = 0; specs && specs->tag == T_STR &&
                      specs->as.str.atom_id == atom_dot && i < t->as.str.arity;
       i++, specs = specs->as.str.args[1]) {
    tterm_t *spec = specs->as.str.args[0], **arg = &a[i];
    if (spec->tag == T_INT && spec->as.ival >= 0 && spec->as.ival <= 9) {
      module_closure(T, arg, (int32_t)spec->as.ival);
    } else if (spec->tag == T_ATOM && spec->as.atom_id == atom_caret) {
      while ((*arg)->tag == T_STR && (*arg)->as.str.atom_id == atom_caret &&
             (*arg)->as.str.arity == 2)
        arg = &(*arg)->as.str.args[1];
      module_closure(T, arg, 0);
    } else if (spec->tag == T_ATOM && spec->as.atom_id == atom_intdiv) {
      module_dcg(T, arg);
    }
  }
}

static void module_dcg(trilog_t *T, tterm_t **slot) {
  tterm_t *t = *slot;
  if (t->tag == T_ATOM) {
    if (t->as.atom_id != atom_nil && t->as.atom_id != atom_bang)
      module_ref(T, t, 2);
    return;
  }
  if (t->tag != T_STR)
    return;
  int32_t id = t->as.str.atom_id, n = t->as.str.arity;
  tterm_t **a = t->as.str.args;
  if ((id == atom_dot && n == 2) || id == atom_call || id == atom_colon)
    return;
  if (id == atom_curly && n == 1)
    module_closure(T, &a[0], 0);
  else if (n == 2 && (id == atom_comma || id == atom_semicolon ||
                      id == atom_arrow || id == atom_bar))
    module_dcg(T, &a[0]), module_dcg(T, &a[1]);
  else if (n == 1 && id == atom_naf)
    module_dcg(T, &a[0]);
  else
    module_ref(T, t, 2);
}

static bool caller_goal(trilog_t *T, const tterm_t *t) {
  for (int32_t i = 0; i < T->module_nmeta_vars; i++)
    if (T->module_meta_vars[i] == t->as.slot)
      return true;
  return false;
}

static void module_goal(trilog_t *T, tterm_t **slot) {
  tterm_t *t = *slot;
  if (t->tag == T_VAR) {
    if (!caller_goal(T, t))
      module_wrap(T, slot);
    return;
  }
  if (t->tag == T_STR && t->as.str.atom_id == atom_colon &&
      t->as.str.arity == 2)
    return;
  if (t->tag == T_STR)
    module_meta_args(T, t);
  module_ref(T, t, 0);
}

// The specs of the predicate a head defines, also for a renamed private one.
static tterm_t *head_meta_specs(trilog_t *T, const tterm_t *h) {
  int32_t id, arity;
  if (!callable_name(h, &id, &arity) || arity == 0)
    return NULL;
  tterm_t *specs = db_meta_specs(T, id, arity);
  const char *m = atom_name(T, T->module_id), *n = atom_name(T, id);
  size_t lm = strlen(m);
  if (!specs && !strncmp(n, m, lm) && n[lm] == ':') {
    int32_t plain = atom_find(T, n + lm + 1);
    if (plain >= 0)
      specs = db_meta_specs(T, plain, arity);
  }
  return specs;
}

// A head variable in a goal position of the clause's own meta_predicate
// holds the caller's goal, which must not be taken as this module's.
static void collect_caller_goals(trilog_t *T, const tterm_t *h) {
  T->module_nmeta_vars = 0;
  tterm_t *specs = head_meta_specs(T, h);
  for (int32_t i = 0; specs && specs->tag == T_STR &&
                      specs->as.str.atom_id == atom_dot && i < h->as.str.arity;
       i++, specs = specs->as.str.args[1]) {
    tterm_t *spec = specs->as.str.args[0], *arg = h->as.str.args[i];
    bool goal = (spec->tag == T_INT) ||
                (spec->tag == T_ATOM && (spec->as.atom_id == atom_caret ||
                                         spec->as.atom_id == atom_intdiv));
    if (!goal || arg->tag != T_VAR)
      continue;
    if (T->module_nmeta_vars == T->module_meta_vars_cap) {
      int32_t cap = T->module_meta_vars_cap ? T->module_meta_vars_cap * 2 : 8;
      T->module_meta_vars = mem_grow_n(T, T->module_meta_vars, (size_t)cap,
                                       sizeof(int32_t));
      T->module_meta_vars_cap = cap;
    }
    T->module_meta_vars[T->module_nmeta_vars++] = arg->as.slot;
  }
}

// Points the file's calls to its private predicates at their new names.
static void module_patch(trilog_t *T) {
  for (int32_t i = 0; i < T->db_count; i++) {
    clause_t *c = &T->db[i];
    if (!c->head || c->source != T->consulting_atom)
      continue;
    collect_caller_goals(T, c->head);
    if (c->head->tag == T_STR && c->head->as.str.atom_id == atom_dcg_arrow &&
        c->head->as.str.arity == 2)
      module_dcg(T, &c->head->as.str.args[1]);
    for (int32_t j = 0; j < c->nbody; j++)
      module_goal(T, &c->body[j]);
  }
  T->module_nmeta_vars = 0;
}

// user:H defines H; Module:H defines Module's private H.
static tterm_t *module_head(trilog_t *T, tterm_t *h) {
  int32_t id, arity;
  if (h->tag == T_STR && h->as.str.atom_id == atom_colon &&
      h->as.str.arity == 2 && h->as.str.args[0]->tag == T_ATOM &&
      callable_name(h->as.str.args[1], &id, &arity)) {
    int32_t m = h->as.str.args[0]->as.atom_id;
    tterm_t *g = h->as.str.args[1];
    if (m != atom_user)
      rename_callable(g, module_qualified(T, m, id, true));
    return g;
  }
  if (T->module_id < 0)
    return h;
  if (h->tag == T_STR && h->as.str.atom_id == atom_dcg_arrow &&
      h->as.str.arity == 2) {
    tterm_t *nt = h->as.str.args[0];
    if (nt->tag == T_STR && nt->as.str.atom_id == atom_comma &&
        nt->as.str.arity == 2)
      nt = nt->as.str.args[0];
    module_define(T, nt, 2);
    return h;
  }
  module_define(T, h, 0);
  return h;
}

static void assemble_clause(trilog_t *T, tterm_t *t, int32_t nvars) {
  if (t->tag == T_STR && t->as.str.arity == 2 &&
      t->as.str.atom_id == atom_ruleop) {
    int32_t nbody;
    tterm_t **body = flatten_conj(T, t->as.str.args[1], &nbody);
    db_add(T, module_head(T, t->as.str.args[0]), body, nbody, nvars, 1);
    return;
  }
  if (t->tag == T_STR && t->as.str.arity == 1 &&
      (t->as.str.atom_id == atom_ruleop ||
       t->as.str.atom_id == atom_qmark_dash)) {
    if (T->module_id >= 0) {
      module_patch(T);
      module_goal(T, &t->as.str.args[0]);
    }
    run_directive(T, t->as.str.args[0], nvars);
    return;
  }
  db_add(T, module_head(T, t), NULL, 0, nvars, 1); // a fact
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
  int32_t saved_module = T->module_id, saved_nexports = T->module_nexports,
          saved_nprivate = T->module_nprivate,
          saved_private_cap = T->module_private_cap;
  pred_decl_t *saved_exports = T->module_exports,
              *saved_private = T->module_private;
  T->module_id = -1;
  T->module_exports = T->module_private = NULL;
  T->module_nexports = T->module_nprivate = T->module_private_cap = 0;
  T->consulting = file;
  T->consulting_atom = file ? atom_intern(T, file) : -1;
  bool ok = consult_source(T, text, name);
  if (T->module_id >= 0)
    module_patch(T);
  mem_free(T, T->module_exports);
  mem_free(T, T->module_private);
  T->module_id = saved_module;
  T->module_exports = saved_exports;
  T->module_private = saved_private;
  T->module_nexports = saved_nexports;
  T->module_nprivate = saved_nprivate;
  T->module_private_cap = saved_private_cap;
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
    if (T->load_error_ball != (size_t)-1)
      return false;
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

static number_text_t parse_number_text_(trilog_t *T, const char *text,
                                        tterm_t **out) {
  T->P = text;
  volatile bool negative = false;
  if (setjmp(T->err_jmp)) {
    if (!strncmp(T->err_msg, FLOAT_OVERFLOW, strlen(FLOAT_OVERFLOW)))
      return NUMBER_TEXT_FLOAT_OVERFLOW;
    return strncmp(T->err_msg, INTEGER_OVERFLOW, strlen(INTEGER_OVERFLOW))
               ? NUMBER_TEXT_BAD
           : negative ? NUMBER_TEXT_TOO_SMALL
                      : NUMBER_TEXT_TOO_BIG;
  }
  skip_ws(T);
  if (T->P[0] == '-' && !is_symbol_char((unsigned char)T->P[1])) {
    T->P++;
    negative = true;
  } else if (T->P[0] == '\'') {
    if (strcmp(read_quoted(T, '\''), "-"))
      perr(T, "not a number");
    negative = true;
  }
  if (negative)
    skip_ws(T);
  if (!ascii_digit((unsigned char)*T->P))
    perr(T, "not a number");
  *out = parse_number(T, negative);
  if (*T->P != '\0')
    perr(T, "text after a number");
  return NUMBER_TEXT_OK;
}

number_text_t parse_number_text(trilog_t *T, const char *text, tterm_t **out) {
  const char *saved_P = T->P;
  jmp_buf saved_jmp;
  memcpy(saved_jmp, T->err_jmp, sizeof(jmp_buf));
  bool saved_temp = T->arena_use_temp;
  T->arena_use_temp = true;
  number_text_t r = parse_number_text_(T, text, out);
  T->arena_use_temp = saved_temp;
  T->P = saved_P;
  memcpy(T->err_jmp, saved_jmp, sizeof(jmp_buf));
  return r;
}

bool parse_term_from_string(trilog_t *T, const char *src, tterm_t **term_out,
                            int32_t *nvars_out, const char ***varnames_out) {
  const char *saved_P = T->P;
  size_t saved_psp = T->psp;
  jmp_buf saved_jmp;
  memcpy(saved_jmp, T->err_jmp, sizeof(jmp_buf));
  bool saved_temp = T->arena_use_temp;
  T->arena_use_temp = true;
  bool ok = parse_term_from_string_(T, src, term_out, nvars_out, varnames_out);
  T->arena_use_temp = saved_temp;
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

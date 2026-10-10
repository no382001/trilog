#include "trilog.h"
#include <stdio.h>
#include <string.h>

static int failures = 0;
static int checks = 0;

static bool streq(const char *a, const char *b) {
  return a && b && strcmp(a, b) == 0;
}

#define CHECK(cond)                                                            \
  do {                                                                         \
    bool ok_ = (cond);                                                         \
    printf("%sok %d - %s: %s\n", ok_ ? "" : "not ", ++checks, __func__,        \
           #cond);                                                             \
    if (!ok_) {                                                                \
      printf("# %s:%d\n", __FILE__, __LINE__);                                 \
      failures++;                                                              \
    }                                                                          \
  } while (0)

typedef struct {
  int count;
  int stop_after;
  bool last_has_more;
  char text[8][64];
} collected;

static bool collect(trilog_t *t, void *ud, bool has_more) {
  collected *c = ud;
  if (c->count < 8 && trilog_binding_count(t) > 0)
    trilog_format(t, trilog_binding_value(t, 0), TRILOG_FORMAT_QUOTED,
                  c->text[c->count], sizeof c->text[0]);
  c->count++;
  c->last_has_more = has_more;
  return c->stop_after == 0 || c->count < c->stop_after;
}

static void test_solutions(trilog_t *t) {
  CHECK(trilog_load_string(t, "p(1). p(two). p(\"x y\").\n"
                              "q(X) :- p(X), X \\== two.\n") == TRILOG_TRUE);
  collected c = {0};
  CHECK(trilog_query(t, "p(X)", collect, &c) == TRILOG_TRUE);
  CHECK(c.count == 3);
  CHECK(!c.last_has_more);
  CHECK(streq(c.text[0], "1"));
  CHECK(streq(c.text[1], "two"));
  CHECK(streq(c.text[2], "\"x y\""));

  collected first = {.stop_after = 1};
  CHECK(trilog_query(t, "q(X).", collect, &first) == TRILOG_TRUE);
  CHECK(first.count == 1);
  CHECK(first.last_has_more);

  collected none = {0};
  CHECK(trilog_query(t, "p(3)", collect, &none) == TRILOG_FALSE);
  CHECK(none.count == 0);
}

static bool inspect(trilog_t *t, void *ud, bool has_more) {
  (void)has_more;
  int *checked = ud;
  CHECK(trilog_binding_count(t) == 3);
  CHECK(streq(trilog_binding_name(t, 0), "X"));
  CHECK(streq(trilog_binding_name(t, 1), "T"));
  CHECK(streq(trilog_binding_name(t, 2), "U"));
  CHECK(trilog_binding_name(t, 3) == NULL);
  CHECK(trilog_term_type(t, trilog_binding_value(t, 2)) == TRILOG_VAR);

  trilog_term_t term = trilog_binding_value(t, 1);
  const char *name = "";
  int arity = 0;
  CHECK(trilog_get_functor(t, term, &name, &arity));
  CHECK(streq(name, "f") && arity == 3);

  trilog_term_t a1 = {(size_t)-1}, a2 = a1, a3 = a1, none = a1;
  CHECK(trilog_get_arg(t, term, 1, &a1));
  CHECK(trilog_get_arg(t, term, 2, &a2));
  CHECK(trilog_get_arg(t, term, 3, &a3));
  CHECK(!trilog_get_arg(t, term, 0, &none));
  CHECK(!trilog_get_arg(t, term, 4, &none));

  int64_t i;
  double d;
  CHECK(trilog_get_int(t, a1, &i) && i == -9223372036854775807 - 1);
  CHECK(trilog_get_float(t, a2, &d) && d == 2.5);
  CHECK(streq(trilog_get_atom(t, a3), "hello world"));
  CHECK(trilog_get_atom(t, a1) == NULL);
  CHECK(!trilog_get_int(t, a3, &i));

  char buf[64];
  size_t n = trilog_format(t, a3, TRILOG_FORMAT_QUOTED, buf, sizeof buf);
  CHECK(n == 13 && streq(buf, "'hello world'"));
  CHECK(trilog_format(t, a3, 0, buf, sizeof buf) == 11);
  CHECK(streq(buf, "hello world"));
  char tiny[4];
  CHECK(trilog_format(t, a3, 0, tiny, sizeof tiny) == 11);
  CHECK(streq(tiny, "hel"));

  CHECK(trilog_query(t, "true", collect, &(collected){0}) == TRILOG_ERROR);
  CHECK(trilog_load_string(t, "r(1).") == TRILOG_ERROR);

  ++*checked;
  return true;
}

static void test_terms(trilog_t *t) {
  int checked = 0;
  CHECK(trilog_query(t,
                     "X is -(9223372036854775807) - 1, "
                     "T = f(X, 2.5, 'hello world'), var(U)",
                     inspect, &checked) == TRILOG_TRUE);
  CHECK(checked == 1);
  CHECK(trilog_binding_count(t) == 0);

  trilog_term_t stale = {(size_t)-1};
  CHECK(trilog_term_type(t, stale) == TRILOG_INVALID);
}

static void test_errors(trilog_t *t) {
  collected c = {0};
  CHECK(trilog_query(t, "throw(oops(1, \"a\"))", collect, &c) == TRILOG_ERROR);
  char buf[64];
  trilog_format(t, trilog_error_term(t), TRILOG_FORMAT_QUOTED, buf, sizeof buf);
  CHECK(streq(buf, "oops(1, \"a\")"));

  CHECK(trilog_query(t, "undefined_pred", collect, &c) == TRILOG_ERROR);
  trilog_format(t, trilog_error_term(t), 0, buf, sizeof buf);
  CHECK(!strncmp(
      buf, "error(existence_error(procedure, /(undefined_pred, 0))",
      strlen("error(existence_error(procedure, /(undefined_pred, 0))")));

  CHECK(trilog_query(t, "foo(", collect, &c) == TRILOG_ERROR);
  CHECK(trilog_term_type(t, trilog_error_term(t)) == TRILOG_INVALID);
  CHECK(trilog_load_string(t, "broken( :- .") == TRILOG_ERROR);
  CHECK(trilog_load_file(t, "/nonexistent/file.pl") == TRILOG_ERROR);
  CHECK(c.count == 0);

  collected after = {0};
  CHECK(trilog_query(t, "p(1)", collect, &after) == TRILOG_TRUE);
  CHECK(after.count == 1);
}

static void test_directives(trilog_t *t) {
  CHECK(trilog_load_string(t, ":- dynamic(seen/1).\n"
                              ":- assertz(seen(directive)).\n") == TRILOG_TRUE);
  collected c = {0};
  CHECK(trilog_query(t, "seen(X)", collect, &c) == TRILOG_TRUE);
  CHECK(c.count == 1 && streq(c.text[0], "directive"));
}

static bool ffi_add(trilog_t *t, void *ud, const trilog_value_t *in,
                    trilog_value_t *out) {
  (void)t;
  int *calls = ud;
  ++*calls;
  out[0].i = in[0].i + in[1].i;
  return true;
}

static bool ffi_half(trilog_t *t, void *ud, const trilog_value_t *in,
                     trilog_value_t *out) {
  (void)t;
  (void)ud;
  if (in[0].f == 0.0)
    return false;
  out[0].f = in[0].f / 2;
  out[1].a = in[0].f > 0 ? "positive" : "negative";
  return true;
}

static bool ffi_nan(trilog_t *t, void *ud, const trilog_value_t *in,
                    trilog_value_t *out) {
  (void)t;
  (void)ud;
  (void)in;
  out[0].f = 0.0 / 0.0;
  return true;
}

static bool ffi_greet(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)t;
  (void)out;
  return streq(in[0].a, (const char *)ud);
}

static bool ffi_isqrt(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)ud;
  if (in[0].i < 0)
    return trilog_error(t, "domain_error(not_less_than_zero, %lld)",
                        (long long)in[0].i);
  int64_t r = 0;
  while ((r + 1) * (r + 1) <= in[0].i)
    r++;
  out[0].i = r;
  return true;
}

static bool ffi_bad_error(trilog_t *t, void *ud, const trilog_value_t *in,
                          trilog_value_t *out) {
  (void)ud;
  (void)in;
  (void)out;
  return trilog_error(t, "oops(");
}

static trilog_status_t error_text(trilog_t *t, const char *goal, char *buf,
                                  size_t cap) {
  collected c = {0};
  trilog_status_t s = trilog_query(t, goal, collect, &c);
  trilog_format(t, trilog_error_term(t), 0, buf, cap);
  return s;
}

static void test_foreign(trilog_t *t) {
  int calls = 0;
  CHECK(trilog_register(t, "c_add", "ii>i", ffi_add, &calls));
  CHECK(trilog_register(t, "c_half", "f>fa", ffi_half, NULL));
  CHECK(trilog_register(t, "c_nan", ">f", ffi_nan, NULL));
  CHECK(trilog_register(t, "c_greet", "a", ffi_greet, "world"));

  collected c = {0};
  CHECK(trilog_query(t, "c_add(2, 40, X)", collect, &c) == TRILOG_TRUE);
  CHECK(c.count == 1 && streq(c.text[0], "42") && calls == 1);
  collected d = {0};
  CHECK(trilog_query(t, "c_add(2, 40, 41)", collect, &d) == TRILOG_FALSE);
  collected e = {0};
  CHECK(trilog_query(t, "c_half(5, X, S)", collect, &e) == TRILOG_TRUE);
  CHECK(streq(e.text[0], "2.5"));
  collected f = {0};
  CHECK(trilog_query(t, "c_half(0, _, _)", collect, &f) == TRILOG_FALSE);
  collected g = {0};
  CHECK(trilog_query(t, "c_greet(world), \\+ c_greet(moon)", collect, &g) ==
        TRILOG_TRUE);

  char buf[128];
  CHECK(error_text(t, "c_add(X, 1, _)", buf, sizeof buf) == TRILOG_ERROR);
  CHECK(!strncmp(buf, "error(instantiation_error", 25));
  CHECK(error_text(t, "c_add(a, 1, _)", buf, sizeof buf) == TRILOG_ERROR);
  CHECK(!strncmp(buf, "error(type_error(integer, a)", 28));
  CHECK(error_text(t, "c_greet(1)", buf, sizeof buf) == TRILOG_ERROR);
  CHECK(!strncmp(buf, "error(type_error(atom, 1)", 25));
  CHECK(error_text(t, "c_nan(_)", buf, sizeof buf) == TRILOG_ERROR);
  CHECK(!strncmp(buf, "error(evaluation_error(undefined)", 33));
  CHECK(error_text(t, "assertz(c_add(1, 2, 3))", buf, sizeof buf) ==
        TRILOG_ERROR);
  CHECK(!strncmp(buf, "error(permission_error(modify", 29));
  collected h = {0};
  CHECK(trilog_query(t,
                     "catch(c_add(x, 1, _), error(type_error(T, V), _), "
                     "true)",
                     collect, &h) == TRILOG_TRUE);

  CHECK(!trilog_error(t, "domain_error(x, y)"));
  CHECK(trilog_register(t, "c_isqrt", "i>i", ffi_isqrt, NULL));
  CHECK(trilog_register(t, "c_bad_error", "", ffi_bad_error, NULL));
  collected r = {0};
  CHECK(trilog_query(t, "c_isqrt(17, R)", collect, &r) == TRILOG_TRUE);
  CHECK(streq(r.text[0], "4"));
  CHECK(error_text(t, "c_isqrt(-3, _)", buf, sizeof buf) == TRILOG_ERROR);
  CHECK(
      streq(buf, "error(domain_error(not_less_than_zero, -3), /(c_isqrt, 2))"));
  collected k = {0};
  CHECK(trilog_query(t,
                     "catch(c_isqrt(-3, _), error(domain_error(D, V), C), "
                     "true), D == not_less_than_zero, V == -3, C == c_isqrt/2",
                     collect, &k) == TRILOG_TRUE);
  CHECK(error_text(t, "c_bad_error", buf, sizeof buf) == TRILOG_ERROR);
  CHECK(!strncmp(buf, "error(syntax_error(oops(), /(c_bad_error, 0))", 46));
  CHECK(trilog_load_string(t, ":- catch(c_isqrt(-1, _), _, true).\n"
                              "after_error(1).\n") == TRILOG_TRUE);
  collected a = {0};
  CHECK(trilog_query(t, "after_error(1)", collect, &a) == TRILOG_TRUE);

  CHECK(!trilog_register(t, "c_bad", "iq", ffi_add, NULL));
  CHECK(!trilog_register(t, "c_bad", "iiiiiiiii", ffi_add, NULL));
  CHECK(!trilog_register(t, "p", "i", ffi_add, NULL));
  CHECK(!trilog_register(t, "c_bad", "i", NULL, NULL));
}

static bool count_steps(trilog_t *t, size_t depth, void *ud) {
  (void)t;
  (void)depth;
  long *steps = ud;
  return ++*steps < 50;
}

static void test_yield(trilog_t *t) {
  CHECK(trilog_load_string(t, "spin :- spin.\n") == TRILOG_TRUE);
  long steps = 0;
  trilog_set_yield(t, count_steps, 100, &steps);
  collected c = {0};
  CHECK(trilog_query(t, "catch(spin, _, true)", collect, &c) == TRILOG_ABORTED);
  CHECK(steps == 50 && c.count == 0);
  trilog_set_yield(t, NULL, 0, NULL);
  collected d = {0};
  CHECK(trilog_query(t, "p(1)", collect, &d) == TRILOG_TRUE);
}

typedef struct {
  char out[256];
  size_t len;
} sink;

typedef struct {
  const char *text;
  size_t pos;
} vfs_file;

typedef struct {
  sink out, err;
  vfs_file file;
} host;

static const char *const vfs_text = "v(1).\nv(2).\n";

static void *vfs_open(void *ud, const char *path, const char *mode) {
  host *h = ud;
  if (!streq(path, "mem/v.pl") || mode[0] != 'r')
    return NULL;
  h->file = (vfs_file){.text = vfs_text};
  return &h->file;
}

static long vfs_read(void *ud, void *handle, char *buf, size_t n) {
  host *h = ud;
  if (handle != &h->file)
    return 0;
  size_t left = strlen(h->file.text) - h->file.pos;
  size_t k = n < 3 ? n : 3;
  if (k > left)
    k = left;
  memcpy(buf, h->file.text + h->file.pos, k);
  h->file.pos += k;
  return (long)k;
}

static long vfs_write(void *ud, void *handle, const char *buf, size_t n) {
  host *h = ud;
  sink *k = handle == &h->out ? &h->out : handle == &h->err ? &h->err : NULL;
  if (n > 5)
    n = 5;
  if (!k || k->len + n >= sizeof k->out)
    return -1;
  memcpy(k->out + k->len, buf, n);
  k->len += n;
  k->out[k->len] = '\0';
  return (long)n;
}

static void vfs_close(void *ud, void *handle) {
  (void)ud;
  (void)handle;
}

static void test_io(trilog_t *t) {
  host h = {0};
  trilog_io_t io = {.open = vfs_open,
                    .read = vfs_read,
                    .write = vfs_write,
                    .close = vfs_close,
                    .out = &h.out,
                    .err = &h.err,
                    .userdata = &h};
  CHECK(trilog_set_io(t, &io));
  collected c = {0};
  CHECK(trilog_query(t, "write(hello(1)), nl", collect, &c) == TRILOG_TRUE);
  CHECK(streq(h.out.out, "hello(1)\n"));
  CHECK(trilog_load_string(t, "broken(") == TRILOG_ERROR);
  CHECK(strstr(h.err.out, "parse error") != NULL);
  CHECK(strstr(h.out.out, "parse error") == NULL);
  CHECK(trilog_load_file(t, "mem/v.pl") == TRILOG_TRUE);
  collected d = {0};
  CHECK(trilog_query(t, "v(X)", collect, &d) == TRILOG_TRUE && d.count == 2);
  collected e = {0};
  CHECK(trilog_query(t,
                     "open('mem/v.pl', read, S), read_line_to_atom(S, A), "
                     "read_line_to_atom(S, B), read_line_to_atom(S, C), "
                     "close(S), A == 'v(1).', B == 'v(2).', C == end_of_file",
                     collect, &e) == TRILOG_TRUE);
  CHECK(trilog_query(t, "open('mem/nope.pl', read, _)", collect, &e) !=
        TRILOG_TRUE);
  CHECK(!trilog_set_io(t, &(trilog_io_t){.write = vfs_write}));
  size_t before = h.out.len;
  CHECK(trilog_query(t, "write(still)", collect, &e) == TRILOG_TRUE);
  CHECK(h.out.len > before);
  CHECK(trilog_set_io(t, NULL));
}

static void test_usage(trilog_t *t) {
  trilog_usage_t u;
  trilog_usage(t, &u);
  CHECK(u.clauses > 100 && u.atoms >= 116 && u.arena_bytes > 0);
  CHECK(u.heap_capacity_cells >= u.heap_cells);
  CHECK(u.heap_peak_cells >= u.heap_cells);
}

static trilog_t *boot(void) {
  return trilog_new(&(trilog_config_t){.boot_path = "boot/core.pl"});
}

static bool query_other(trilog_t *t, void *ud, bool has_more) {
  (void)has_more;
  trilog_t *other = ud;
  collected c = {0};
  CHECK(trilog_query(other, "who(X)", collect, &c) == TRILOG_TRUE);
  CHECK(c.count == 1 && streq(c.text[0], "second"));
  CHECK(streq(trilog_get_atom(t, trilog_binding_value(t, 0)), "first"));
  return true;
}

static void test_two_interpreters(void) {
  trilog_t *a = boot(), *b = boot();
  CHECK(a && b);
  if (!a || !b)
    return;
  CHECK(trilog_load_string(a, "who(first). n(0).") == TRILOG_TRUE);
  CHECK(trilog_load_string(b, "who(second).") == TRILOG_TRUE);
  for (int i = 0; i < 3; i++) {
    collected ca = {0}, cb = {0};
    CHECK(trilog_query(a, "who(X)", collect, &ca) == TRILOG_TRUE);
    CHECK(trilog_query(b, "who(X)", collect, &cb) == TRILOG_TRUE);
    CHECK(ca.count == 1 && streq(ca.text[0], "first"));
    CHECK(cb.count == 1 && streq(cb.text[0], "second"));
  }
  collected none = {0};
  CHECK(trilog_query(b, "n(_)", collect, &none) == TRILOG_ERROR);
  CHECK(trilog_query(a, "who(X)", query_other, b) == TRILOG_TRUE);
  CHECK(trilog_query(a, "numlist(1, 50000, L), length(L, N), N > 0", collect,
                     &none) == TRILOG_TRUE);
  collected cb = {0};
  CHECK(trilog_query(b, "who(X)", collect, &cb) == TRILOG_TRUE);
  CHECK(cb.count == 1 && streq(cb.text[0], "second"));
  trilog_free(a);
  trilog_free(b);
}

static void test_create_free(void) {
  for (int i = 0; i < 3; i++) {
    trilog_t *t = boot();
    CHECK(t != NULL);
    collected c = {0};
    CHECK(trilog_query(t, "assertz(k(1)), k(X)", collect, &c) == TRILOG_TRUE);
    trilog_free(t);
  }
  trilog_free(NULL);
}

int main(void) {
  trilog_t *t = trilog_new(&(trilog_config_t){.boot_path = "boot/core.pl"});
  if (!t) {
    fprintf(stderr, "trilog_new failed\n");
    return 1;
  }

  test_solutions(t);
  test_terms(t);
  test_errors(t);
  test_directives(t);
  test_foreign(t);
  test_yield(t);
  test_io(t);
  test_usage(t);
  test_two_interpreters();
  test_create_free();

  trilog_usage_t u;
  trilog_usage(t, &u);
  CHECK(u.heap_peak_cells > 0);
  CHECK(u.heap_peak_bytes >= u.heap_peak_cells);

  trilog_free(t);
  printf("1..%d\n", checks);
  if (failures) {
    fprintf(stderr, "api_test: %d check(s) failed\n", failures);
    return 1;
  }
  printf("api_test: ok\n");
  return 0;
}

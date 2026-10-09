#pragma once
// The trilog embedding API. Hosts include only this header.
//
// Interpreters share no state: any number may exist,
// and each may be used by one thread at a time.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct trilog trilog_t;

// A term owned by the interpreter.
// Handles from a solution callback are valid only during that callback;
// the error term is valid until the next call that runs Prolog code.
typedef struct {
  size_t ref;
} trilog_term_t;

typedef enum {
  TRILOG_FALSE = 0,   // no solution
  TRILOG_TRUE = 1,    // at least one solution
  TRILOG_ERROR = 2,   // uncaught exception, syntax error, out of memory, misuse
  TRILOG_HALT = 3,    // halt/1 ran; see trilog_halt_code
  TRILOG_ABORTED = 4, // the yield callback returned false
} trilog_status_t;

typedef enum {
  TRILOG_INVALID, // stale or never-valid handle
  TRILOG_VAR,
  TRILOG_ATOM,
  TRILOG_INT,
  TRILOG_FLOAT,
  TRILOG_COMPOUND,
} trilog_type_t;

typedef struct {
  void *(*open)(void *ud, const char *path, const char *mode); // NULL: failed
  long (*read)(void *ud, void *handle, char *buf, size_t n); // 0 at end of file
  long (*write)(void *ud, void *handle, const char *buf, size_t n);
  void (*close)(void *ud, void *handle);
  void (*flush)(void *ud, void *handle); // optional
  void *in, *out, *err;
  void *userdata;
} trilog_io_t;

typedef struct {
  // NULL boots from the copy of boot/core.pl baked in by `make release`.
  const char *boot_path;
  void *(*realloc)(void *ud, void *p, size_t n);
  void (*free)(void *ud, void *p);
  void *alloc_ud;
  // NULL means stdio. Also used to read the boot file.
  const trilog_io_t *io;
  size_t gc_threshold;
  bool gc_debug; // one line per collection on the error stream
} trilog_config_t;

typedef struct {
  size_t heap_cells;
  size_t heap_capacity_cells;
  size_t heap_peak_cells;
  size_t heap_peak_bytes;
  size_t trail_entries;
  size_t choicepoints;
  size_t clauses;
  size_t atoms;
  size_t arena_bytes; // clauses, atom names and parsed source
} trilog_usage_t;

// Accepts a NULL config. Returns NULL if booting fails, if only one of the
// allocator hooks is set, or if the I/O hooks are an incomplete set.
trilog_t *trilog_new(const trilog_config_t *config);
void trilog_free(trilog_t *t);

trilog_status_t trilog_load_file(trilog_t *t, const char *path);
trilog_status_t trilog_load_string(trilog_t *t, const char *text);

// After TRILOG_HALT, the code halt/1 was given.
int trilog_halt_code(trilog_t *t);

// Called once per solution, with has_more false when no choicepoint is left.
// Return true to ask for the next solution.
// The callback must not call trilog_query or trilog_load_* on the same
// interpreter.
typedef bool (*trilog_solution_fn)(trilog_t *t, void *ud, bool has_more);

// The goal is query text; its trailing '.' is optional.
trilog_status_t trilog_query(trilog_t *t, const char *goal,
                             trilog_solution_fn on_solution, void *ud);

// Read the bindings of the current solution, in order of first appearance.
int trilog_binding_count(trilog_t *t);
const char *trilog_binding_name(trilog_t *t, int i);
trilog_term_t trilog_binding_value(trilog_t *t, int i);

// After TRILOG_ERROR, returns the exception term,
// or an invalid handle when the error was not an exception.
trilog_term_t trilog_error_term(trilog_t *t);

trilog_type_t trilog_term_type(trilog_t *t, trilog_term_t term);
bool trilog_get_int(trilog_t *t, trilog_term_t term, int64_t *out);
bool trilog_get_float(trilog_t *t, trilog_term_t term, double *out);
// The name lives as long as the interpreter.
// Returns NULL if the term is not an atom.
const char *trilog_get_atom(trilog_t *t, trilog_term_t term);
bool trilog_get_functor(trilog_t *t, trilog_term_t term, const char **name,
                        int *arity);
// The index i is 1-based, as in arg/3.
bool trilog_get_arg(trilog_t *t, trilog_term_t term, int i, trilog_term_t *out);

enum { TRILOG_FORMAT_QUOTED = 1 };

// Writes the term as text, like snprintf:
// the result is always terminated when cap > 0,
// and the return value is the full length,
// so a return >= cap means the text was cut short.
size_t trilog_format(trilog_t *t, trilog_term_t term, int flags, char *buf,
                     size_t cap);

void trilog_usage(trilog_t *t, trilog_usage_t *out);

// Replaces the I/O hooks; NULL restores stdio. False for an incomplete set.
bool trilog_set_io(trilog_t *t, const trilog_io_t *io);

#define TRILOG_MAX_FOREIGN_ARGS 8

typedef union {
  int64_t i;
  double f;
  const char *a;
} trilog_value_t;

// Returning false makes the call fail.
typedef bool (*trilog_fn)(trilog_t *t, void *ud, const trilog_value_t *in,
                          trilog_value_t *out);

// Defines name/N as a call to fn. sig types each argument: i integer,
// f float (integers convert), a atom; '>' splits inputs from outputs, so
// "ii>i" is name(+Integer, +Integer, -Integer). Bad inputs raise
// instantiation_error or type_error. Atoms in `out` are copied; NULL fails.
// Returns false for a bad sig, a name with clauses, or out of memory.
bool trilog_register(trilog_t *t, const char *name, const char *sig,
                     trilog_fn fn, void *ud);

// From inside a registered fn, raises error(Formal, Name/Arity), where Formal
// is the Prolog text of formal after formatting; elsewhere it does nothing.
// The format takes %% %c %s %.*s, %d and %u with no, l, ll or z length, and
// %g. Always returns false, so fn can end with `return trilog_error(...)`.
bool trilog_error(trilog_t *t, const char *formal, ...);

// Calls fn every `every` steps; returning false makes the running call
// return TRILOG_ABORTED, which catch/3 cannot intercept. NULL disables it.
// fn must not call trilog_query or trilog_load_* on t.
typedef bool (*trilog_yield_fn)(trilog_t *t, size_t depth, void *ud);
void trilog_set_yield(trilog_t *t, trilog_yield_fn fn, unsigned every,
                      void *ud);

// The build's git describe output and branch, e.g. "v0.2-3-gabc1234-dirty
// (main)".
const char *trilog_version(void);

#ifdef __cplusplus
}
#endif

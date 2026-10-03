#pragma once
// The trilog embedding API. Hosts include only this header.
//
// Not yet thread-safe: the engine still keeps its state in globals,
// so only one interpreter may exist per process,
// and trilog_new returns NULL for a second one.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct trilog trilog_t;

// A term owned by the interpreter.
// Handles from a solution callback are valid only during that callback;
// the error term is valid until the next call that runs Prolog code.
typedef struct {
  size_t ref;
} trilog_term_t;

typedef enum {
  TRILOG_FALSE = 0, // no solution
  TRILOG_TRUE = 1,  // at least one solution
  TRILOG_ERROR = 2, // uncaught exception, syntax error, or misuse
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
  // NULL boots from the copy of boot/core.pl baked in by `make release`.
  const char *boot_path;
} trilog_config_t;

typedef struct {
  size_t heap_peak_cells;
  size_t heap_peak_bytes;
} trilog_usage_t;

// Accepts a NULL config. Returns NULL if booting fails.
trilog_t *trilog_new(const trilog_config_t *config);
void trilog_free(trilog_t *t);

// Clauses are added and directives run as the text is read.
// Returns false on a syntax error or a missing file.
bool trilog_load_file(trilog_t *t, const char *path);
bool trilog_load_string(trilog_t *t, const char *text);

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

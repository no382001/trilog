#pragma once

// freestanding mode: user must provide these macros before including this
// header hosted mode: we use stdlib normally
#ifndef PROLOG_FREESTANDING

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

#else // PROLOG_FREESTANDING

#ifndef bool
typedef _Bool bool;
#define true 1
#define false 0
#endif

#ifndef _VA_LIST_DEFINED
typedef __builtin_va_list va_list;
#define va_start __builtin_va_start
#define va_end __builtin_va_end
#define va_arg __builtin_va_arg
#define _VA_LIST_DEFINED
#endif

#ifndef NULL
#define NULL ((void *)0)
#endif

// user must define these as macros pointing to their implementations:
// strcmp, strncmp, strlen, strcspn, strncpy, strncat, strrchr
// memcpy, memset
// isspace, isdigit, isalpha, isalnum
// vsnprintf, snprintf
// assert (or define NDEBUG to disable)

#endif // PROLOG_FREESTANDING

#define MAX_NAME 64
#define MAX_ARGS 8
#define MAX_LIST_LIT 1024
#define MAX_CLAUSES 1024
#define MAX_BINDINGS 4096
#define MAX_GOALS 128
#define MAX_STACK 256
#define MAX_ERROR_MSG 256
#define MAX_CUSTOM_BUILTINS 64
#define MAX_STRING_POOL 65536
#define MAX_FILE_PATH 512
#define MAX_MAKE_FILES 16
#define MAX_OPEN_STREAMS 16
#define MAX_CLAUSE_VARS 64

#define TERM_POOL_BYTES (4 * 1024 * 1024)
#define PROLOG_CTX_SIZE(pool_bytes) (sizeof(prolog_ctx_t) + (pool_bytes))

typedef struct prolog_ctx prolog_ctx_t;
typedef struct term term_t;
typedef struct env env_t;

typedef enum {
  BUILTIN_FAIL = -1,
  BUILTIN_NOT_HANDLED = 0,
  BUILTIN_OK = 1,
  BUILTIN_CUT = 2,
  BUILTIN_ERROR = 3, // runtime error: ctx->runtime_error is set
} builtin_result_t;

typedef builtin_result_t (*builtin_handler_t)(prolog_ctx_t *ctx, term_t *goal,
                                              env_t *env);

typedef struct {
  char name[MAX_NAME];
  int arity;
  builtin_handler_t handler;
  void *userdata;
} custom_builtin_t;

typedef void (*io_write_callback_t)(prolog_ctx_t *ctx, const char *str,
                                    void *userdata);
typedef void (*io_write_term_callback_t)(prolog_ctx_t *ctx, term_t *t,
                                         env_t *env, void *userdata);
typedef void (*io_writef_callback_t)(prolog_ctx_t *ctx, const char *fmt,
                                     va_list args, void *userdata);
typedef int (*io_read_char_callback_t)(prolog_ctx_t *ctx, void *userdata);
typedef char *(*io_read_line_callback_t)(prolog_ctx_t *ctx, char *buf, int size,
                                         void *userdata);

// file i/o hooks (opaque handle = void*)
typedef void *(*io_file_open_callback_t)(prolog_ctx_t *ctx, const char *path,
                                         const char *mode, void *userdata);
typedef void (*io_file_close_callback_t)(prolog_ctx_t *ctx, void *handle,
                                         void *userdata);
typedef char *(*io_file_read_line_callback_t)(prolog_ctx_t *ctx, void *handle,
                                              char *buf, int size,
                                              void *userdata);
typedef bool (*io_file_write_callback_t)(prolog_ctx_t *ctx, void *handle,
                                         const char *str, void *userdata);
typedef bool (*io_file_exists_callback_t)(prolog_ctx_t *ctx, const char *path,
                                          void *userdata);
typedef long long (*io_file_mtime_callback_t)(prolog_ctx_t *ctx,
                                              const char *path, void *userdata);
typedef double (*io_clock_monotonic_callback_t)(prolog_ctx_t *ctx,
                                                void *userdata);

typedef struct {
  io_write_callback_t write_str;
  io_write_term_callback_t write_term;
  io_writef_callback_t writef;
  io_writef_callback_t writef_err;
  io_read_char_callback_t read_char;
  io_read_line_callback_t read_line;
  io_file_open_callback_t file_open;
  io_file_close_callback_t file_close;
  io_file_read_line_callback_t file_read_line;
  io_file_write_callback_t file_write;
  io_file_exists_callback_t file_exists;
  io_file_mtime_callback_t file_mtime;
  io_clock_monotonic_callback_t clock_monotonic;
  void *userdata;
} io_hooks_t;

typedef enum { CONST, VAR, FUNC, STRING } term_type;

// escape sequence table used by both the parser (decode) and printer (encode).
// each entry maps a raw byte to its two-character escape sequence.
typedef struct {
  char raw;
  char seq; // the letter after backslash: 'n', 't', etc.
} str_escape_t;
static const str_escape_t STR_ESCAPES[] = {
    {'\n', 'n'}, {'\t', 't'}, {'\r', 'r'}, {'\\', '\\'}, {'"', '"'}, {0, 0}};

struct term {
  term_type type;
  const char *name;
  int arity; // is repurposed for var_id VAR
  char *string_data;
  struct term *args[]; // FAM: arity elements follow
};

#define AS_FUNC(t) (t)
#define AS_CONST(t) (t)
#define AS_VAR(t) (t)
#define AS_STRING(t) (t)

typedef struct {
  int var_id;       // variable identity (matches term_t.arity for VAR terms)
  const char *name; // display name only; NULL for internal renamed vars
  term_t *value;
} binding_t;

typedef struct {
  int old_id;
  int new_id;
} var_id_map_entry_t;

typedef struct {
  var_id_map_entry_t entries[MAX_CLAUSE_VARS];
  int count;
} var_id_map_t;

struct env {
  binding_t *bindings; // points into ctx->bindings
  int count;
};

typedef struct {
  term_t *head;
  term_t **body; // allocated from perm pool
  int body_count;
} clause_t;

typedef struct {
  term_t **goals; // allocated from term pool
  int count;
} goal_stmt_t;

typedef struct {
  goal_stmt_t goals;
  int clause_index;
  int env_mark;
  int cut_point; // stack pointer to cut back to
  int term_mark; // term_pool_offset at push time (restored on backtrack)
} frame_t;

typedef struct {
  bool has_error;
  bool error_is_eof; // true when failure is due to unexpected end of input
  char message[MAX_ERROR_MSG];
  int line;
  int column;
} parse_error_t;

struct prolog_ctx {
  clause_t database[MAX_CLAUSES];
  int db_count;
  binding_t bindings[MAX_BINDINGS]; // centralized trail
  int bind_count;
  int var_counter;
  char *input_ptr;
  char *input_start;
  int input_line;
  bool debug_enabled;

  int term_pool_size;   // total bytes
  int term_pool_offset; // temp: grows up from 0
  int term_pool_perm;   // perm: grows down from term_pool_size
  int term_pool_floor;  // backtrack cannot reclaim below this
  int bind_floor;       // LCO cannot reclaim bindings below this
  bool alloc_permanent; // when true, allocate from perm end

  char string_pool[MAX_STRING_POOL];
  int string_pool_offset;

  parse_error_t error;

  io_hooks_t io_hooks;

  custom_builtin_t custom_builtins[MAX_CUSTOM_BUILTINS];
  int custom_builtin_count;

  char load_dir[MAX_FILE_PATH]; // directory of the file currently being loaded

  // make/0 – file reload tracking
  struct {
    char path[MAX_FILE_PATH];
    long long mtime;
  } make_files[MAX_MAKE_FILES];
  int make_file_count;
  int make_db_mark;
  int make_term_mark;
  int make_string_mark;
  int include_depth;

  // per-clause variable table: maps name -> var_id within one clause/query.
  // reset at the start of each clause or top-level query parse.
  struct {
    const char *name; // interned variable name
    int var_id;
  } clause_vars[MAX_CLAUSE_VARS];
  int clause_var_count;

  struct {
    int terms_allocated;
    int terms_peak;
    int unify_calls;
    int unify_fails;
    int son_calls;
    int backtracks;
  } stats;

  // open file streams (handles from io_file_open); NULL = free slot
  void *open_streams[MAX_OPEN_STREAMS];

  bool has_runtime_error;
  char runtime_error[MAX_ERROR_MSG];
  term_t *thrown_ball; // exception term set by throw/1

  _Alignas(8) char term_pool[]; // FAM - must be last field
};

static inline bool is_cons(const term_t *t) {
  return t && t->type == FUNC && t->name[0] == '.' && t->name[1] == '\0' &&
         t->arity == 2;
}

static inline bool is_nil(const term_t *t) {
  return t && t->type == CONST && t->name[0] == '[' && t->name[1] == ']' &&
         t->name[2] == '\0';
}

static inline bool term_as_int(const term_t *t, int *out) {
  if (!t || t->type != CONST)
    return false;
  const char *p = t->name;
  int sign = 1;
  if (*p == '-') {
    sign = -1;
    p++;
  }
  if (*p < '0' || *p > '9')
    return false;
  int val = 0;
  while (*p >= '0' && *p <= '9')
    val = val * 10 + (*p++ - '0');
  if (*p != '\0')
    return false;
  *out = sign * val;
  return true;
}

void ctx_reset_terms(prolog_ctx_t *ctx);
void *term_alloc(prolog_ctx_t *ctx, size_t size);
// Allocate a goal array of n slots from the term pool.
static inline goal_stmt_t goals_alloc(prolog_ctx_t *ctx, int n) {
  goal_stmt_t g;
  g.goals =
      (n > 0) ? (term_t **)term_alloc(ctx, (size_t)n * sizeof(term_t *)) : NULL;
  g.count = 0;
  return g;
}
const char *intern_name(prolog_ctx_t *ctx, const char *name);

static inline void prolog_ctx_init(prolog_ctx_t *ctx, int pool_bytes) {
  memset(ctx, 0, PROLOG_CTX_SIZE(pool_bytes));
  ctx->term_pool_size = pool_bytes;
  ctx->term_pool_perm = pool_bytes;
}

void debug(prolog_ctx_t *ctx, const char *fmt, ...);
void print_term_raw(prolog_ctx_t *ctx, term_t *t);
void debug_term_raw(prolog_ctx_t *ctx, term_t *t);

term_t *make_term(prolog_ctx_t *ctx, term_type type, const char *name,
                  term_t **args, int arity);
term_t *make_const(prolog_ctx_t *ctx, const char *name);
// for VAR terms, arity field stores the var_id (unique integer per variable).
// name may be NULL for internal renamed variables (not shown in output).
term_t *make_var(prolog_ctx_t *ctx, const char *name, int var_id);
term_t *make_func(prolog_ctx_t *ctx, const char *name, term_t **args,
                  int arity);
term_t *make_string(prolog_ctx_t *ctx, const char *str);

void skip_ws(prolog_ctx_t *ctx);
term_t *parse_term(prolog_ctx_t *ctx);
term_t *parse_list(prolog_ctx_t *ctx);
void parse_clause(prolog_ctx_t *ctx, char *line);
void strip_line_comment(char *line);
bool has_complete_clause(const char *buf);
bool prolog_load_file(prolog_ctx_t *ctx, const char *filename);
bool prolog_load_string(prolog_ctx_t *ctx, const char *src);

term_t *lookup(env_t *env, int var_id);
void bind(prolog_ctx_t *ctx, env_t *env, term_t *var, term_t *value);
term_t *deref(env_t *env, term_t *t);
term_t *substitute(prolog_ctx_t *ctx, env_t *env, term_t *t);

bool unify(prolog_ctx_t *ctx, term_t *a, term_t *b, env_t *env);

// rename_vars_mapped: rename all VARs in t, mapping old var_ids to fresh ones.
// the map is shared across multiple calls for the same clause instance so that
// the same variable in head and body gets the same renamed id.
term_t *rename_vars_mapped(prolog_ctx_t *ctx, term_t *t, var_id_map_t *map);
// Convenience wrapper: creates a fresh map for single-term rename.
term_t *rename_vars(prolog_ctx_t *ctx, term_t *t);

bool son(prolog_ctx_t *ctx, goal_stmt_t *cn, int *clause_idx, env_t *env,
         int env_mark, goal_stmt_t *resolvent);

typedef bool (*solution_callback_t)(prolog_ctx_t *ctx, env_t *env,
                                    void *userdata, bool has_more);

bool solve(prolog_ctx_t *ctx, goal_stmt_t *initial_goals, env_t *env);
bool solve_all(prolog_ctx_t *ctx, goal_stmt_t *initial_goals, env_t *env,
               solution_callback_t callback, void *userdata);

bool prolog_exec_query(prolog_ctx_t *ctx, char *query);
bool prolog_exec_query_multi(prolog_ctx_t *ctx, char *query,
                             solution_callback_t cb, void *ud);

void print_term(prolog_ctx_t *ctx, term_t *t, env_t *env, bool quoted);
void print_bindings(prolog_ctx_t *ctx, env_t *env);

void parse_error(prolog_ctx_t *ctx, const char *fmt, ...);
void parse_error_clear(prolog_ctx_t *ctx);
bool parse_has_error(prolog_ctx_t *ctx);
void parse_error_print(prolog_ctx_t *ctx);

void ctx_runtime_error(prolog_ctx_t *ctx, const char *fmt, ...);

builtin_result_t try_builtin(prolog_ctx_t *ctx, term_t *goal, env_t *env);

// i/o hook management
void io_hooks_init_default(prolog_ctx_t *ctx);
void io_hooks_set(prolog_ctx_t *ctx, io_hooks_t *hooks);

// i/o functions (use hooks internally)
void io_write_str(prolog_ctx_t *ctx, const char *str);
void io_write_term(prolog_ctx_t *ctx, term_t *t, env_t *env);
void io_write_term_quoted(prolog_ctx_t *ctx, term_t *t, env_t *env);
void io_writef(prolog_ctx_t *ctx, const char *fmt, ...);
void io_writef_err(prolog_ctx_t *ctx, const char *fmt, ...);
int io_read_char(prolog_ctx_t *ctx);
char *io_read_line(prolog_ctx_t *ctx, char *buf, int size);

// file i/o wrappers
void *io_file_open(prolog_ctx_t *ctx, const char *path, const char *mode);
void io_file_close(prolog_ctx_t *ctx, void *handle);
char *io_file_read_line(prolog_ctx_t *ctx, void *handle, char *buf, int size);
bool io_file_write(prolog_ctx_t *ctx, void *handle, const char *str);
bool io_file_exists(prolog_ctx_t *ctx, const char *path);
long long io_file_mtime(prolog_ctx_t *ctx, const char *path);
double io_clock_monotonic(prolog_ctx_t *ctx);

// ffi: Register custom builtins
bool ffi_register_builtin(prolog_ctx_t *ctx, const char *name, int arity,
                          builtin_handler_t handler, void *userdata);
void ffi_clear_builtins(prolog_ctx_t *ctx);
custom_builtin_t *ffi_get_builtin_userdata(prolog_ctx_t *ctx, term_t *goal);

// quad tests
typedef struct {
  int total;
  int passed;
  int failed;
  double total_time;
} quad_results_t;

quad_results_t prolog_run_quad_file(prolog_ctx_t *ctx, const char *filename);
quad_results_t prolog_run_quad_file_junit(prolog_ctx_t *ctx,
                                          const char *filename,
                                          const char *junit_dir);

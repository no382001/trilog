#include "platform_impl.h"

#ifndef ABCLOG_FREESTANDING

static void default_write_str(abclog_ctx_t *ctx, const char *str,
                              void *userdata) {
  (void)ctx;
  (void)userdata;
  printf("%s", str);
}

static void default_write_term(abclog_ctx_t *ctx, term_t *t, env_t *env,
                               void *userdata) {
  (void)userdata;
  print_term(ctx, t, env, false);
}

static void default_writef(abclog_ctx_t *ctx, const char *fmt, va_list args,
                           void *userdata) {
  (void)ctx;
  (void)userdata;
  vprintf(fmt, args);
}

static void default_writef_err(abclog_ctx_t *ctx, const char *fmt, va_list args,
                               void *userdata) {
  (void)ctx;
  (void)userdata;
  vfprintf(stderr, fmt, args);
}

static int default_read_char(abclog_ctx_t *ctx, void *userdata) {
  (void)ctx;
  (void)userdata;
  return getchar();
}

static char *default_read_line(abclog_ctx_t *ctx, char *buf, int size,
                               void *userdata) {
  (void)ctx;
  (void)userdata;
  return fgets(buf, size, stdin);
}

static void *default_file_open(abclog_ctx_t *ctx, const char *path,
                               const char *mode, void *userdata) {
  (void)ctx;
  (void)userdata;
  return fopen(path, mode);
}

static void default_file_close(abclog_ctx_t *ctx, void *handle,
                               void *userdata) {
  (void)ctx;
  (void)userdata;
  if (handle)
    fclose(handle);
}

static char *default_file_read_line(abclog_ctx_t *ctx, void *handle, char *buf,
                                    int size, void *userdata) {
  (void)ctx;
  (void)userdata;
  return fgets(buf, size, handle);
}

static bool default_file_write(abclog_ctx_t *ctx, void *handle, const char *str,
                               void *userdata) {
  (void)ctx;
  (void)userdata;
  return fputs(str, handle) >= 0;
}

static bool default_file_exists(abclog_ctx_t *ctx, const char *path,
                                void *userdata) {
  (void)ctx;
  (void)userdata;
  struct stat st;
  return stat(path, &st) == 0;
}

static long long default_file_mtime(abclog_ctx_t *ctx, const char *path,
                                    void *userdata) {
  (void)ctx;
  (void)userdata;
  struct stat st;
  return (stat(path, &st) == 0) ? (long long)st.st_mtime : -1LL;
}

static double default_clock_monotonic(abclog_ctx_t *ctx, void *userdata) {
  (void)ctx;
  (void)userdata;
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

void io_hooks_init_default(abclog_ctx_t *ctx) {
  ctx->io_hooks.write_str = default_write_str;
  ctx->io_hooks.write_term = default_write_term;
  ctx->io_hooks.writef = default_writef;
  ctx->io_hooks.writef_err = default_writef_err;
  ctx->io_hooks.read_char = default_read_char;
  ctx->io_hooks.read_line = default_read_line;
  ctx->io_hooks.file_open = default_file_open;
  ctx->io_hooks.file_close = default_file_close;
  ctx->io_hooks.file_read_line = default_file_read_line;
  ctx->io_hooks.file_write = default_file_write;
  ctx->io_hooks.file_exists = default_file_exists;
  ctx->io_hooks.file_mtime = default_file_mtime;
  ctx->io_hooks.clock_monotonic = default_clock_monotonic;
  ctx->io_hooks.userdata = NULL;
}

#endif // !ABCLOG_FREESTANDING

void io_hooks_set(abclog_ctx_t *ctx, io_hooks_t *hooks) {
  if (hooks->write_str)
    ctx->io_hooks.write_str = hooks->write_str;
  if (hooks->write_term)
    ctx->io_hooks.write_term = hooks->write_term;
  if (hooks->writef)
    ctx->io_hooks.writef = hooks->writef;
  if (hooks->writef_err)
    ctx->io_hooks.writef_err = hooks->writef_err;
  if (hooks->read_char)
    ctx->io_hooks.read_char = hooks->read_char;
  if (hooks->read_line)
    ctx->io_hooks.read_line = hooks->read_line;
  if (hooks->file_open)
    ctx->io_hooks.file_open = hooks->file_open;
  if (hooks->file_close)
    ctx->io_hooks.file_close = hooks->file_close;
  if (hooks->file_read_line)
    ctx->io_hooks.file_read_line = hooks->file_read_line;
  if (hooks->file_write)
    ctx->io_hooks.file_write = hooks->file_write;
  if (hooks->file_exists)
    ctx->io_hooks.file_exists = hooks->file_exists;
  if (hooks->file_mtime)
    ctx->io_hooks.file_mtime = hooks->file_mtime;
  if (hooks->clock_monotonic)
    ctx->io_hooks.clock_monotonic = hooks->clock_monotonic;

  ctx->io_hooks.userdata = hooks->userdata;
}

void io_write_str(abclog_ctx_t *ctx, const char *str) {
  if (ctx->io_hooks.write_str) {
    ctx->io_hooks.write_str(ctx, str, ctx->io_hooks.userdata);
  }
}

void io_write_term(abclog_ctx_t *ctx, term_t *t, env_t *env) {
  if (ctx->io_hooks.write_term) {
    ctx->io_hooks.write_term(ctx, t, env, ctx->io_hooks.userdata);
  }
}

void io_write_term_quoted(abclog_ctx_t *ctx, term_t *t, env_t *env) {
  print_term(ctx, t, env, true);
}

void io_writef(abclog_ctx_t *ctx, const char *fmt, ...) {
  if (ctx->io_hooks.writef) {
    va_list args;
    va_start(args, fmt);
    ctx->io_hooks.writef(ctx, fmt, args, ctx->io_hooks.userdata);
    va_end(args);
  }
}

void io_writef_err(abclog_ctx_t *ctx, const char *fmt, ...) {
  if (ctx->io_hooks.writef_err) {
    va_list args;
    va_start(args, fmt);
    ctx->io_hooks.writef_err(ctx, fmt, args, ctx->io_hooks.userdata);
    va_end(args);
  }
}

int io_read_char(abclog_ctx_t *ctx) {
  if (ctx->io_hooks.read_char) {
    return ctx->io_hooks.read_char(ctx, ctx->io_hooks.userdata);
  }
  return -1; // EOF
}

char *io_read_line(abclog_ctx_t *ctx, char *buf, int size) {
  if (ctx->io_hooks.read_line) {
    return ctx->io_hooks.read_line(ctx, buf, size, ctx->io_hooks.userdata);
  }
  return NULL;
}

void *io_file_open(abclog_ctx_t *ctx, const char *path, const char *mode) {
  if (ctx->io_hooks.file_open)
    return ctx->io_hooks.file_open(ctx, path, mode, ctx->io_hooks.userdata);
  return NULL;
}

void io_file_close(abclog_ctx_t *ctx, void *handle) {
  if (ctx->io_hooks.file_close)
    ctx->io_hooks.file_close(ctx, handle, ctx->io_hooks.userdata);
}

char *io_file_read_line(abclog_ctx_t *ctx, void *handle, char *buf, int size) {
  if (ctx->io_hooks.file_read_line)
    return ctx->io_hooks.file_read_line(ctx, handle, buf, size,
                                        ctx->io_hooks.userdata);
  return NULL;
}

bool io_file_write(abclog_ctx_t *ctx, void *handle, const char *str) {
  if (ctx->io_hooks.file_write)
    return ctx->io_hooks.file_write(ctx, handle, str, ctx->io_hooks.userdata);
  return false;
}

bool io_file_exists(abclog_ctx_t *ctx, const char *path) {
  if (ctx->io_hooks.file_exists)
    return ctx->io_hooks.file_exists(ctx, path, ctx->io_hooks.userdata);
  return false;
}

long long io_file_mtime(abclog_ctx_t *ctx, const char *path) {
  if (ctx->io_hooks.file_mtime)
    return ctx->io_hooks.file_mtime(ctx, path, ctx->io_hooks.userdata);
  return -1LL;
}

double io_clock_monotonic(abclog_ctx_t *ctx) {
  if (ctx->io_hooks.clock_monotonic)
    return ctx->io_hooks.clock_monotonic(ctx, ctx->io_hooks.userdata);
  return 0.0;
}

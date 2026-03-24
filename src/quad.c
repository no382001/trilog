#include "platform_impl.h"

#define QUAD_BUF_SIZE 16384
#define MAX_QUAD_ANSWERS 64
#define MAX_ANSWER_LEN 1024
#define MAX_QUAD_TESTS 512
#define MAX_FAIL_MSG 512

typedef struct {
  char name[256];
  bool pass;
  char failure[MAX_FAIL_MSG];
  double elapsed_sec;
} test_record_t;

typedef struct {
  char buf[4096];
  int pos;
} capture_buf_t;

static void cap_reset(capture_buf_t *c) {
  c->pos = 0;
  c->buf[0] = '\0';
}

static void cap_write_str(trilog_ctx_t *ctx, const char *str, void *ud) {
  (void)ctx;
  capture_buf_t *c = ud;
  int len = (int)strlen(str);
  int rem = (int)sizeof(c->buf) - c->pos - 1;
  if (len > rem)
    len = rem;
  if (len > 0) {
    memcpy(c->buf + c->pos, str, len);
    c->pos += len;
    c->buf[c->pos] = '\0';
  }
}

static void cap_writef(trilog_ctx_t *ctx, const char *fmt, va_list args,
                       void *ud) {
  (void)ctx;
  capture_buf_t *c = ud;
  int rem = (int)sizeof(c->buf) - c->pos - 1;
  if (rem > 0) {
    int n = vsnprintf(c->buf + c->pos, rem, fmt, args);
    if (n > 0) {
      if (n >= rem)
        c->pos = (int)sizeof(c->buf) - 1;
      else
        c->pos += n;
      c->buf[c->pos] = '\0';
    }
  }
}

typedef struct {
  char answers[MAX_QUAD_ANSWERS][MAX_ANSWER_LEN];
  int count;
  capture_buf_t cap;
} collector_t;

static bool collect_cb(trilog_ctx_t *ctx, env_t *env, void *ud, bool has_more) {
  collector_t *col = ud;
  if (col->count >= MAX_QUAD_ANSWERS)
    return false;

  io_hooks_t saved = ctx->io_hooks;
  cap_reset(&col->cap);
  ctx->io_hooks.write_str = cap_write_str;
  ctx->io_hooks.writef = cap_writef;
  ctx->io_hooks.userdata = &col->cap;

  print_bindings(ctx, env);

  ctx->io_hooks = saved;

  strncpy(col->answers[col->count], col->cap.buf, MAX_ANSWER_LEN - 1);
  col->answers[col->count][MAX_ANSWER_LEN - 1] = '\0';
  col->count++;

  return has_more && col->count < MAX_QUAD_ANSWERS;
}

// remove the terminating . (depth-0 dot followed by whitespace/EOF)
static void strip_terminating_dot(char *buf) {
  bool in_string = false;
  int depth = 0;
  char *dot_pos = NULL;

  for (char *p = buf; *p; p++) {
    if (in_string) {
      if (*p == '\\' && *(p + 1))
        p++;
      else if (*p == '"')
        in_string = false;
    } else {
      if (*p == '"')
        in_string = true;
      else if (*p == '(' || *p == '[')
        depth++;
      else if (*p == ')' || *p == ']')
        depth--;
      else if (*p == '.' && depth == 0) {
        char next = *(p + 1);
        if (next == '\0' || isspace((unsigned char)next))
          dot_pos = p;
      }
    }
  }

  if (dot_pos)
    *dot_pos = '\0';
}

// parse answer description into individual expected answers.
// answer alternatives are separated by ; at the start of a line.
// example: "   X = a\n;  X = b" → ["X = a", "X = b"]
static int parse_expected(const char *desc, char out[][MAX_ANSWER_LEN],
                          int max) {
  int count = 0;
  const char *p = desc;

  // skip leading whitespace
  while (*p && isspace((unsigned char)*p))
    p++;
  if (!*p)
    return 0;

  int ci = 0;

  while (*p && count < max) {
    if (*p == '\n') {
      const char *q = p + 1;
      while (*q == ' ' || *q == '\t')
        q++;
      if (*q == ';') {
        // end current answer, start next
        while (ci > 0 && isspace((unsigned char)out[count][ci - 1]))
          ci--;
        out[count][ci] = '\0';
        if (ci > 0)
          count++;
        if (count >= max)
          break;
        ci = 0;
        p = q + 1; // skip ;
        while (*p == ' ' || *p == '\t')
          p++;
        continue;
      }
      // continuation line — normalize newline to space
      if (ci > 0 && ci < MAX_ANSWER_LEN - 1)
        out[count][ci++] = ' ';
      p++;
      while (*p == ' ' || *p == '\t')
        p++;
      continue;
    }

    if (ci < MAX_ANSWER_LEN - 1)
      out[count][ci++] = *p;
    p++;
  }

  // finish last answer
  while (ci > 0 && isspace((unsigned char)out[count][ci - 1]))
    ci--;
  out[count][ci] = '\0';
  if (ci > 0)
    count++;

  return count;
}

static bool run_one_test(trilog_ctx_t *ctx, const char *query_raw,
                         const char *answer_raw, int test_num,
                         quad_results_t *res, test_record_t *rec) {
  // parse expected answers
  char answer_buf[QUAD_BUF_SIZE];
  strncpy(answer_buf, answer_raw, sizeof(answer_buf) - 1);
  answer_buf[sizeof(answer_buf) - 1] = '\0';
  strip_terminating_dot(answer_buf);

  char expected[MAX_QUAD_ANSWERS][MAX_ANSWER_LEN];
  memset(expected, 0, sizeof(expected));
  int exp_count = parse_expected(answer_buf, expected, MAX_QUAD_ANSWERS);

  // prepare query: skip "?-", strip terminating dot
  char query_buf[QUAD_BUF_SIZE];
  const char *q = query_raw;
  if (q[0] == '?' && q[1] == '-')
    q += 2;
  while (*q == ' ' || *q == '\t')
    q++;
  strncpy(query_buf, q, sizeof(query_buf) - 1);
  query_buf[sizeof(query_buf) - 1] = '\0';
  strip_terminating_dot(query_buf);

  // display name (truncated query)
  char display[256];
  strncpy(display, query_buf, sizeof(display) - 1);
  display[sizeof(display) - 1] = '\0';
  if (strlen(display) > 60) {
    display[57] = '.';
    display[58] = '.';
    display[59] = '.';
    display[60] = '\0';
  }

  // time the query execution
  double t_start = io_clock_monotonic(ctx);

  // suppress output during query execution (write/1, nl/0, errors)
  capture_buf_t query_out;
  cap_reset(&query_out);
  io_hooks_t saved_hooks = ctx->io_hooks;
  ctx->io_hooks.write_str = cap_write_str;
  ctx->io_hooks.writef = cap_writef;
  ctx->io_hooks.writef_err = cap_writef;
  ctx->io_hooks.userdata = &query_out;

  // run query
  parse_error_clear(ctx);
  ctx->has_runtime_error = false;
  ctx->thrown_ball = NULL;

  collector_t col;
  memset(&col, 0, sizeof(col));
  bool found = trilog_exec_query_multi(ctx, query_buf, collect_cb, &col);

  bool had_error = ctx->has_runtime_error;
  char error_msg[MAX_ERROR_MSG];
  error_msg[0] = '\0';
  if (had_error) {
    strncpy(error_msg, ctx->runtime_error, sizeof(error_msg) - 1);
    error_msg[sizeof(error_msg) - 1] = '\0';
    ctx->has_runtime_error = false;
  }

  // restore hooks
  ctx->io_hooks = saved_hooks;

  double elapsed = io_clock_monotonic(ctx) - t_start;

  // compare results
  bool pass = false;
  res->total++;

  bool expect_false = (exp_count == 1 && strcmp(expected[0], "false") == 0);

  // check for error(...) expected answer
  bool expect_error = false;
  char expected_error_type[MAX_ERROR_MSG] = {0};
  if (exp_count == 1 && strncmp(expected[0], "error(", 6) == 0) {
    expect_error = true;
    const char *start = expected[0] + 6;
    const char *end = strrchr(start, ')');
    if (end && end > start) {
      int len = (int)(end - start);
      if (len > (int)sizeof(expected_error_type) - 1)
        len = (int)sizeof(expected_error_type) - 1;
      memcpy(expected_error_type, start, len);
      expected_error_type[len] = '\0';
    }
  }

  if (expect_error) {
    int elen = (int)strlen(expected_error_type);
    pass = had_error && strncmp(error_msg, expected_error_type, elen) == 0 &&
           (error_msg[elen] == '\0' || error_msg[elen] == ' ');
  } else if (expect_false) {
    pass = !found && !had_error;
  } else if (had_error) {
    pass = false;
  } else if (col.count == exp_count) {
    pass = true;
    for (int i = 0; i < col.count; i++) {
      if (strcmp(col.answers[i], expected[i]) != 0) {
        pass = false;
        break;
      }
    }
  }

  res->total_time += elapsed;

  // record test result
  if (rec) {
    snprintf(rec->name, sizeof(rec->name), "%.*s", (int)(sizeof(rec->name) - 1),
             display);
    rec->pass = pass;
    rec->failure[0] = '\0';
    rec->elapsed_sec = elapsed;
  }

  // output TAP
  if (pass) {
    res->passed++;
    io_writef(ctx, "ok %d - ?- %s (%.3fms)\n", test_num, display,
              elapsed * 1000.0);
  } else {
    res->failed++;
    io_writef(ctx, "not ok %d - ?- %s (%.3fms)\n", test_num, display,
              elapsed * 1000.0);

    char failbuf[MAX_FAIL_MSG] = {0};
    int fpos = 0;

    if (expect_error) {
      io_writef_err(ctx, "#   expected: %s\n", expected[0]);
      fpos += snprintf(failbuf + fpos, sizeof(failbuf) - fpos, "expected: %s\n",
                       expected[0]);
      if (had_error) {
        io_writef_err(ctx, "#   got: error(%s)\n", error_msg);
        snprintf(failbuf + fpos, sizeof(failbuf) - fpos, "got: error(%s)",
                 error_msg);
      } else if (col.count > 0) {
        io_writef_err(ctx, "#   got: %s (no error)\n", col.answers[0]);
        snprintf(failbuf + fpos, sizeof(failbuf) - fpos, "got: %s (no error)",
                 col.answers[0]);
      } else {
        io_writef_err(ctx, "#   got: (no error)\n");
        snprintf(failbuf + fpos, sizeof(failbuf) - fpos, "got: (no error)");
      }
    } else if (expect_false) {
      io_writef_err(ctx, "#   expected: false\n");
      fpos +=
          snprintf(failbuf + fpos, sizeof(failbuf) - fpos, "expected: false\n");
      if (had_error) {
        io_writef_err(ctx, "#   got: error: %s\n", error_msg);
        snprintf(failbuf + fpos, sizeof(failbuf) - fpos, "got: error: %s",
                 error_msg);
      } else if (col.count > 0) {
        io_writef_err(ctx, "#   got: %s\n", col.answers[0]);
        snprintf(failbuf + fpos, sizeof(failbuf) - fpos, "got: %s",
                 col.answers[0]);
      }
    } else {
      for (int i = 0; i < exp_count || i < col.count; i++) {
        const char *exp_s = i < exp_count ? expected[i] : NULL;
        const char *got_s = i < col.count ? col.answers[i] : NULL;

        if (exp_s && got_s && strcmp(exp_s, got_s) != 0) {
          io_writef_err(ctx, "#   expected[%d]: %s\n", i + 1, exp_s);
          io_writef_err(ctx, "#        got[%d]: %s\n", i + 1, got_s);
          fpos += snprintf(failbuf + fpos, sizeof(failbuf) - fpos,
                           "expected[%d]: %s, got[%d]: %s\n", i + 1, exp_s,
                           i + 1, got_s);
        } else if (exp_s && !got_s) {
          io_writef_err(ctx, "#   expected[%d]: %s\n", i + 1, exp_s);
          io_writef_err(ctx, "#        got[%d]: (none)\n", i + 1);
          fpos += snprintf(failbuf + fpos, sizeof(failbuf) - fpos,
                           "expected[%d]: %s, got[%d]: (none)\n", i + 1, exp_s,
                           i + 1);
        } else if (!exp_s && got_s) {
          io_writef_err(ctx, "#   unexpected[%d]: %s\n", i + 1, got_s);
          fpos += snprintf(failbuf + fpos, sizeof(failbuf) - fpos,
                           "unexpected[%d]: %s\n", i + 1, got_s);
        }
      }
      if (had_error) {
        io_writef_err(ctx, "#   error: %s\n", error_msg);
        snprintf(failbuf + fpos, sizeof(failbuf) - fpos, "error: %s",
                 error_msg);
      }
    }

    if (rec)
      strncpy(rec->failure, failbuf, sizeof(rec->failure) - 1);
  }

  return pass;
}

// escape XML special characters into a buffer
static void xml_escape(const char *src, char *dst, int dstlen) {
  int o = 0;
  for (const char *p = src; *p && o < dstlen - 1; p++) {
    switch (*p) {
    case '<':
      if (o + 4 < dstlen) {
        memcpy(dst + o, "&lt;", 4);
        o += 4;
      }
      break;
    case '>':
      if (o + 4 < dstlen) {
        memcpy(dst + o, "&gt;", 4);
        o += 4;
      }
      break;
    case '&':
      if (o + 5 < dstlen) {
        memcpy(dst + o, "&amp;", 5);
        o += 5;
      }
      break;
    case '"':
      if (o + 6 < dstlen) {
        memcpy(dst + o, "&quot;", 6);
        o += 6;
      }
      break;
    default:
      dst[o++] = *p;
      break;
    }
  }
  dst[o] = '\0';
}

static void write_junit_xml(trilog_ctx_t *ctx, const char *filename,
                            const char *suite_name, test_record_t *records,
                            int count, quad_results_t *res) {
  void *xf = io_file_open(ctx, filename, "w");
  if (!xf)
    return;

  char line[2048];
  io_file_write(ctx, xf, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
  snprintf(line, sizeof(line),
           "<testsuite name=\"%s\" tests=\"%d\" failures=\"%d\" "
           "errors=\"0\" time=\"%.3f\">\n",
           suite_name, res->total, res->failed, res->total_time);
  io_file_write(ctx, xf, line);

  char esc_name[512];
  char esc_fail[1024];
  for (int i = 0; i < count; i++) {
    xml_escape(records[i].name, esc_name, sizeof(esc_name));
    if (records[i].pass) {
      snprintf(line, sizeof(line),
               "  <testcase name=\"%s\" classname=\"%s\" time=\"%.3f\"/>\n",
               esc_name, suite_name, records[i].elapsed_sec);
      io_file_write(ctx, xf, line);
    } else {
      xml_escape(records[i].failure, esc_fail, sizeof(esc_fail));
      snprintf(line, sizeof(line),
               "  <testcase name=\"%s\" classname=\"%s\" time=\"%.3f\">\n",
               esc_name, suite_name, records[i].elapsed_sec);
      io_file_write(ctx, xf, line);
      snprintf(line, sizeof(line), "    <failure message=\"%s\"/>\n", esc_fail);
      io_file_write(ctx, xf, line);
      io_file_write(ctx, xf, "  </testcase>\n");
    }
  }

  io_file_write(ctx, xf, "</testsuite>\n");
  io_file_close(ctx, xf);
}

static quad_results_t run_quad_file_impl(trilog_ctx_t *ctx,
                                         const char *filename,
                                         const char *junit_dir) {
  quad_results_t res = {0};

  void *f = io_file_open(ctx, filename, "r");
  if (!f) {
    io_writef_err(ctx, "Error: cannot open quad file '%s'\n", filename);
    return res;
  }

  test_record_t *records = NULL;
  if (junit_dir)
    records = calloc(MAX_QUAD_TESTS, sizeof(test_record_t));

  char line[1024];
  char clause_buf[QUAD_BUF_SIZE] = {0};
  char query_buf[QUAD_BUF_SIZE] = {0};
  char answer_buf[QUAD_BUF_SIZE] = {0};
  int test_num = 0;
  bool in_answer = false;

  while (io_file_read_line(ctx, f, line, sizeof(line))) {
    line[strcspn(line, "\n")] = 0;
    strip_line_comment(line);

    char *trimmed = line;
    while (isspace((unsigned char)*trimmed))
      trimmed++;

    if (in_answer) {
      // accumulate answer description, preserving newlines for ; splitting
      if (answer_buf[0] == '\0' && *trimmed == '\0')
        continue;
      if (answer_buf[0] != '\0')
        strncat(answer_buf, "\n", sizeof(answer_buf) - strlen(answer_buf) - 1);
      strncat(answer_buf, line, sizeof(answer_buf) - strlen(answer_buf) - 1);

      if (has_complete_clause(answer_buf)) {
        test_record_t *rec =
            (records && test_num < MAX_QUAD_TESTS) ? &records[test_num] : NULL;
        test_num++;
        run_one_test(ctx, query_buf, answer_buf, test_num, &res, rec);
        in_answer = false;
        answer_buf[0] = '\0';
      }
      continue;
    }

    // normal mode: accumulate clause or query
    if (*trimmed == '\0' && clause_buf[0] == '\0')
      continue;
    if (clause_buf[0] != '\0' && *trimmed != '\0')
      strncat(clause_buf, " ", sizeof(clause_buf) - strlen(clause_buf) - 1);
    strncat(clause_buf, trimmed, sizeof(clause_buf) - strlen(clause_buf) - 1);

    if (!has_complete_clause(clause_buf))
      continue;

    if (strncmp(clause_buf, "?-", 2) == 0) {
      // query → save and wait for answer description
      strncpy(query_buf, clause_buf, sizeof(query_buf) - 1);
      query_buf[sizeof(query_buf) - 1] = '\0';
      in_answer = true;
      answer_buf[0] = '\0';
    } else if (strncmp(clause_buf, ":-", 2) == 0) {
      // directive → execute silently
      capture_buf_t discard;
      cap_reset(&discard);
      io_hooks_t saved = ctx->io_hooks;
      ctx->io_hooks.write_str = cap_write_str;
      ctx->io_hooks.writef = cap_writef;
      ctx->io_hooks.userdata = &discard;
      trilog_exec_query(ctx, clause_buf + 2);
      ctx->io_hooks = saved;
    } else {
      // regular clause
      parse_clause(ctx, clause_buf);
    }
    clause_buf[0] = '\0';
  }

  io_file_close(ctx, f);

  io_writef(ctx, "# %s: %d tests, %d passed, %d failed (%.3fs)\n", filename,
            res.total, res.passed, res.failed, res.total_time);

  // write JUnit XML if requested
  if (junit_dir && records) {
    // extract suite name from filename (basename without extension)
    const char *base = filename;
    for (const char *p = filename; *p; p++) {
      if (*p == '/')
        base = p + 1;
    }
    char suite_name[256];
    strncpy(suite_name, base, sizeof(suite_name) - 1);
    suite_name[sizeof(suite_name) - 1] = '\0';
    char *dot = strrchr(suite_name, '.');
    if (dot)
      *dot = '\0';

    // build output path: junit_dir/suite_name.xml
    char xml_path[2048];
    snprintf(xml_path, sizeof(xml_path), "%s/%s.xml", junit_dir, suite_name);
    write_junit_xml(ctx, xml_path, suite_name, records, test_num, &res);
  }

  free(records);
  return res;
}

quad_results_t trilog_run_quad_file(trilog_ctx_t *ctx, const char *filename) {
  return run_quad_file_impl(ctx, filename, NULL);
}

quad_results_t trilog_run_quad_file_junit(trilog_ctx_t *ctx,
                                          const char *filename,
                                          const char *junit_dir) {
  return run_quad_file_impl(ctx, filename, junit_dir);
}

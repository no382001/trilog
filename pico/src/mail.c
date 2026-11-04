#include "mail.h"
#include "pico/stdlib.h"
#include "tcp.h"
#include <stdio.h>
#include <string.h>

#define MAIL_SLOTS 16
#define MAIL_BODY 512
#define LOG_SIZE 4096

typedef struct {
  int64_t id; // 0 for an empty slot
  int64_t ms;
  bool unread;
  char from[16];
  char subject[48];
  char body[MAIL_BODY];
  size_t len;
} mail_t;

static mail_t box[MAIL_SLOTS];
static int64_t last_id;
static char log_ring[LOG_SIZE];
static size_t log_total;
static char mail_handle, log_handle;

static mail_t *find(int64_t id) {
  mail_t *m = &box[id % MAIL_SLOTS];
  return id > 0 && m->id == id ? m : NULL;
}

static bool send(const char *dest, const char *buf, size_t n) {
  if (strcmp(dest, "user") != 0)
    return tcp_send(dest, buf, n);
  fwrite(buf, 1, n, stdout);
  fflush(stdout);
  return true;
}

void *mail_stream_open(const char *path) {
  if (strcmp(path, "mail") == 0)
    return find(last_id) ? &mail_handle : NULL;
  if (strcmp(path, "log") == 0)
    return &log_handle;
  return NULL;
}

bool mail_stream(void *h) { return h == &mail_handle || h == &log_handle; }

long mail_stream_write(void *h, const char *buf, size_t n) {
  if (h == &log_handle) {
    for (size_t i = 0; i < n; i++)
      log_ring[log_total++ % LOG_SIZE] = buf[i];
    fwrite(buf, 1, n, stdout);
    return (long)n;
  }
  mail_t *m = find(last_id);
  size_t k = MAIL_BODY - m->len < n ? MAIL_BODY - m->len : n;
  memcpy(m->body + m->len, buf, k);
  m->len += k;
  return (long)n;
}

static mail_t *mail_start(const char *from, const char *subject) {
  mail_t *m = &box[++last_id % MAIL_SLOTS];
  *m = (mail_t){.id = last_id,
                .ms = (int64_t)(time_us_64() / 1000),
                .unread = true};
  snprintf(m->from, sizeof m->from, "%s", from);
  snprintf(m->subject, sizeof m->subject, "%s", subject);
  return m;
}

void mail_post(const char *from, const char *subject, const char *body) {
  mail_t *m = mail_start(from, subject);
  m->len = (size_t)snprintf(m->body, sizeof m->body, "%s", body);
  if (m->len >= sizeof m->body)
    m->len = sizeof m->body - 1;
}

static bool mail_new(trilog_t *t, void *ud, const trilog_value_t *in,
                     trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  mail_start(in[0].a, in[1].a);
  return true;
}

static bool mail_ids(trilog_t *t, void *ud, const trilog_value_t *in,
                     trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  int64_t first = last_id - MAIL_SLOTS + 1;
  out[0].i = first > 1 ? first : 1;
  out[1].i = last_id;
  return true;
}

static bool mail_info(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)t, (void)ud;
  mail_t *m = find(in[0].i);
  if (!m)
    return false;
  out[0].a = m->from;
  out[1].a = m->subject;
  out[2].i = m->ms;
  out[3].i = m->unread;
  return true;
}

static bool mail_unread(trilog_t *t, void *ud, const trilog_value_t *in,
                        trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  int64_t n = 0;
  for (int i = 0; i < MAIL_SLOTS; i++)
    n += box[i].id && box[i].unread;
  out[0].i = n;
  return true;
}

static bool mail_show(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  mail_t *m = find(in[1].i);
  if (!m)
    return false;
  m->unread = false;
  return send(in[0].a, m->body, m->len);
}

// &, < and > become entities, so a body can sit inside HTML.
static bool send_html(const char *dest, const char *buf, size_t n) {
  size_t run = 0;
  for (size_t i = 0; i < n; i++) {
    const char *e = buf[i] == '&'   ? "&amp;"
                    : buf[i] == '<' ? "&lt;"
                    : buf[i] == '>' ? "&gt;"
                                    : NULL;
    if (!e)
      continue;
    if (!send(dest, buf + run, i - run) || !send(dest, e, strlen(e)))
      return false;
    run = i + 1;
  }
  return send(dest, buf + run, n - run);
}

static bool mail_show_html(trilog_t *t, void *ud, const trilog_value_t *in,
                           trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  mail_t *m = find(in[1].i);
  if (!m)
    return false;
  m->unread = false;
  return send_html(in[0].a, m->body, m->len);
}

// Once the ring has wrapped, its oldest line is cut, so it starts after that.
static bool log_show(trilog_t *t, void *ud, const trilog_value_t *in,
                     trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  if (log_total <= LOG_SIZE)
    return send(in[0].a, log_ring, log_total);
  size_t start = log_total % LOG_SIZE, skip = 0;
  while (skip < LOG_SIZE && log_ring[(start + skip) % LOG_SIZE] != '\n')
    skip++;
  start = (start + skip + 1) % LOG_SIZE;
  size_t n = LOG_SIZE - skip - 1;
  size_t first = LOG_SIZE - start < n ? LOG_SIZE - start : n;
  return send(in[0].a, log_ring + start, first) &&
         send(in[0].a, log_ring, n - first);
}

void mail_register(trilog_t *t) {
  trilog_register(t, "mail_new", "aa", mail_new, NULL);
  trilog_register(t, "mail_ids", ">ii", mail_ids, NULL);
  trilog_register(t, "mail_info", "i>aaii", mail_info, NULL);
  trilog_register(t, "mail_unread", ">i", mail_unread, NULL);
  trilog_register(t, "mail_show", "ai", mail_show, NULL);
  trilog_register(t, "mail_show_html", "ai", mail_show_html, NULL);
  trilog_register(t, "log_show", "a", log_show, NULL);
}

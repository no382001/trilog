#include "tcp.h"
#include "lwip/pbuf.h"
#include "lwip/tcp.h"
#include "pico/cyw43_arch.h"
#include "pico/stdlib.h"
#include <stdio.h>
#include <string.h>

#define MAX_CONNS 8
#define IDLE_TIMEOUT_MS 5000

typedef enum { FREE, PENDING, ACCEPTED } conn_state;

typedef struct {
  conn_state state;
  struct tcp_pcb *pcb; // NULL once lwIP has dropped the connection
  struct pbuf *rx;
  bool eof;
  int refs;
  bool sent;
  absolute_time_t deadline; // for the request to arrive
} conn_t;

static conn_t conns[MAX_CONNS];
static struct tcp_pcb *listener;
static unsigned accepted;
static u16_t listener_port;
static const char *const conn_paths[MAX_CONNS] = {
    "tcp:0", "tcp:1", "tcp:2", "tcp:3", "tcp:4", "tcp:5", "tcp:6", "tcp:7"};

static void conn_release(conn_t *c) {
  if (c->pcb) {
    tcp_arg(c->pcb, NULL);
    tcp_recv(c->pcb, NULL);
    tcp_err(c->pcb, NULL);
    if (tcp_close(c->pcb) != ERR_OK)
      tcp_abort(c->pcb);
  }
  if (c->rx)
    pbuf_free(c->rx);
  *c = (conn_t){0};
}

static err_t on_recv(void *arg, struct tcp_pcb *pcb, struct pbuf *p,
                     err_t err) {
  (void)pcb, (void)err;
  conn_t *c = arg;
  if (!p) {
    c->eof = true;
    return ERR_OK;
  }
  if (c->rx)
    pbuf_cat(c->rx, p);
  else
    c->rx = p;
  return ERR_OK;
}

static void on_err(void *arg, err_t err) {
  (void)err;
  conn_t *c = arg;
  c->pcb = NULL;
  c->eof = true;
}

static err_t on_accept(void *arg, struct tcp_pcb *pcb, err_t err) {
  (void)arg;
  if (err != ERR_OK || !pcb)
    return ERR_VAL;
  for (int i = 0; i < MAX_CONNS; i++) {
    conn_t *c = &conns[i];
    if (c->state != FREE)
      continue;
    *c = (conn_t){.state = PENDING,
                  .pcb = pcb,
                  .deadline = make_timeout_time_ms(IDLE_TIMEOUT_MS)};
    tcp_arg(pcb, c);
    tcp_recv(pcb, on_recv);
    tcp_err(pcb, on_err);
    return ERR_OK;
  }
  tcp_abort(pcb);
  return ERR_ABRT;
}

static bool tcp_listen_on(trilog_t *t, void *ud, const trilog_value_t *in,
                          trilog_value_t *out) {
  (void)ud, (void)out;
  if (in[0].i < 1 || in[0].i > 65535)
    return trilog_error(t, "domain_error(port, %d)", (int)in[0].i);
  if (listener && listener_port == in[0].i)
    return true;
  cyw43_arch_lwip_begin();
  if (listener) {
    tcp_close(listener);
    listener = NULL;
  }
  struct tcp_pcb *pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
  if (pcb && tcp_bind(pcb, IP_ANY_TYPE, (u16_t)in[0].i) == ERR_OK)
    listener = tcp_listen_with_backlog(pcb, MAX_CONNS);
  else if (pcb)
    tcp_close(pcb);
  if (listener) {
    tcp_accept(listener, on_accept);
    listener_port = (u16_t)in[0].i;
  }
  cyw43_arch_lwip_end();
  if (!listener)
    return trilog_error(t, "system_error(tcp_listen)");
  return true;
}

// Ctrl-C on the console raises an error, so a server loop can be stopped.
static bool tcp_accept_next(trilog_t *t, void *ud, const trilog_value_t *in,
                            trilog_value_t *out) {
  (void)ud, (void)in;
  if (!listener)
    return trilog_error(t, "existence_error(listener, tcp)");
  for (;;) {
    cyw43_arch_lwip_begin();
    for (int i = 0; i < MAX_CONNS; i++) {
      if (conns[i].state == PENDING) {
        conns[i].state = ACCEPTED;
        accepted++;
        cyw43_arch_lwip_end();
        out[0].a = conn_paths[i];
        return true;
      }
    }
    cyw43_arch_lwip_end();
    if (getchar_timeout_us(0) == 3)
      return trilog_error(t, "system_error(interrupted)");
    sleep_ms(1);
  }
}

void tcp_register(trilog_t *t) {
  trilog_register(t, "tcp_listen", "i", tcp_listen_on, NULL);
  trilog_register(t, "tcp_accept", ">a", tcp_accept_next, NULL);
}

void *tcp_stream_open(const char *path) {
  for (int i = 0; i < MAX_CONNS; i++) {
    if (strcmp(path, conn_paths[i]) == 0 && conns[i].state == ACCEPTED) {
      conns[i].refs++;
      return &conns[i];
    }
  }
  return NULL;
}

long tcp_stream_read(void *h, char *buf, size_t n) {
  conn_t *c = h;
  for (;;) {
    cyw43_arch_lwip_begin();
    if (c->rx) {
      u16_t k =
          pbuf_copy_partial(c->rx, buf, n > 0xffff ? 0xffff : (u16_t)n, 0);
      c->rx = pbuf_free_header(c->rx, k);
      if (c->pcb)
        tcp_recved(c->pcb, k);
      cyw43_arch_lwip_end();
      return k;
    }
    if (time_reached(c->deadline))
      c->eof = true;
    bool eof = c->eof;
    cyw43_arch_lwip_end();
    if (eof)
      return 0;
    sleep_ms(1);
  }
}

long tcp_stream_write(void *h, const char *buf, size_t n) {
  conn_t *c = h;
  absolute_time_t give_up = make_timeout_time_ms(IDLE_TIMEOUT_MS);
  for (;;) {
    cyw43_arch_lwip_begin();
    if (!c->pcb) {
      cyw43_arch_lwip_end();
      return -1;
    }
    u16_t room = tcp_sndbuf(c->pcb);
    u16_t k = n < room ? (u16_t)n : room;
    err_t e = k > 0 ? tcp_write(c->pcb, buf, k, TCP_WRITE_FLAG_COPY) : ERR_MEM;
    if (e == ERR_MEM)
      tcp_output(c->pcb);
    cyw43_arch_lwip_end();
    if (e == ERR_OK) {
      c->sent = true;
      return k;
    }
    if (e != ERR_MEM || time_reached(give_up))
      return -1;
    sleep_ms(1);
  }
}

bool tcp_send(const char *path, const char *buf, size_t n) {
  for (int i = 0; i < MAX_CONNS; i++) {
    if (strcmp(path, conn_paths[i]) != 0 || conns[i].state != ACCEPTED)
      continue;
    while (n > 0) {
      long k = tcp_stream_write(&conns[i], buf, n);
      if (k <= 0)
        return false;
      buf += k;
      n -= (size_t)k;
    }
    return true;
  }
  return false;
}

void tcp_stream_close(void *h) {
  conn_t *c = h;
  if (--c->refs > 0)
    return;
  cyw43_arch_lwip_begin();
  conn_release(c);
  cyw43_arch_lwip_end();
}

void tcp_fail_all(const char *reason) {
  for (int i = 0; i < MAX_CONNS; i++) {
    conn_t *c = &conns[i];
    if (c->state != ACCEPTED)
      continue;
    char buf[160];
    int n = c->sent ? snprintf(buf, sizeof buf, "\n\n[trilog crashed: %s]\n",
                               reason)
                    : snprintf(buf, sizeof buf,
                               "HTTP/1.0 500 Internal Server Error\r\n"
                               "Content-Type: text/plain\r\n"
                               "Connection: close\r\n\r\n"
                               "trilog crashed: %s\n",
                               reason);
    for (const char *p = buf; n > 0;) {
      long k = tcp_stream_write(c, p, (size_t)n);
      if (k <= 0)
        break;
      p += k;
      n -= (int)k;
    }
  }
}

void tcp_drop_all(void) {
  cyw43_arch_lwip_begin();
  for (int i = 0; i < MAX_CONNS; i++)
    if (conns[i].state == ACCEPTED)
      conn_release(&conns[i]);
  cyw43_arch_lwip_end();
}

unsigned tcp_accept_count(void) { return accepted; }

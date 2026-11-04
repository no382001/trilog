#include "io.h"
#include "mail.h"
#include "tcp.h"
#include <stdio.h>

static char std_in, std_out, std_err;

static bool is_std(void *h) {
  return h == &std_in || h == &std_out || h == &std_err;
}

static void *io_open(void *ud, const char *path, const char *mode) {
  (void)ud, (void)mode;
  void *h = tcp_stream_open(path);
  return h ? h : mail_stream_open(path);
}

static long io_read(void *ud, void *h, char *buf, size_t n) {
  (void)ud;
  if (h == &std_in) {
    int c = getchar();
    if (c == EOF)
      return 0;
    buf[0] = (char)c;
    return 1;
  }
  if (is_std(h) || mail_stream(h))
    return 0;
  return tcp_stream_read(h, buf, n);
}

static long io_write(void *ud, void *h, const char *buf, size_t n) {
  (void)ud;
  if (h == &std_out || h == &std_err)
    return (long)fwrite(buf, 1, n, stdout);
  if (h == &std_in)
    return -1;
  if (mail_stream(h))
    return mail_stream_write(h, buf, n);
  return tcp_stream_write(h, buf, n);
}

static void io_close(void *ud, void *h) {
  (void)ud;
  if (!is_std(h) && !mail_stream(h))
    tcp_stream_close(h);
}

static void io_flush(void *ud, void *h) {
  (void)ud;
  if (h == &std_out || h == &std_err)
    fflush(stdout);
}

const trilog_io_t board_io = {
    .open = io_open,
    .read = io_read,
    .write = io_write,
    .close = io_close,
    .flush = io_flush,
    .in = &std_in,
    .out = &std_out,
    .err = &std_err,
};

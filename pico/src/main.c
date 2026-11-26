#include "hardware/clocks.h"
#include "hardware/structs/sysinfo.h"
#include "hardware/watchdog.h"
#include "pico/stdlib.h"
#include "terminal.h"
#include "toplevel.h"
#include "trilog.h"
#include <malloc.h>
#include "io.h"
#include "mail.h"
#include "tcp.h"
#include "vfs.h"
#include "wifi.h"
#include <stdio.h>

extern char __end__, __HeapLimit;

extern char __StackTop, __scratch_x_start__;
#define STACK_TOP ((uint32_t)&__StackTop)
#define STACK_PAINT_LO ((uint32_t)&__scratch_x_start__)

static void paint_stack(void) {
  volatile uint32_t here;
  for (uint32_t *w = (uint32_t *)STACK_PAINT_LO; w < (uint32_t *)&here - 64;
       w++)
    *w = 0xDEADBEEF;
}

static unsigned stack_used(void) {
  uint32_t *w = (uint32_t *)STACK_PAINT_LO;
  while (*w == 0xDEADBEEF)
    w++;
  return STACK_TOP - (uint32_t)w;
}

static trilog_t *T;
static size_t live_bytes, peak_bytes, failed_request;

typedef struct {
  size_t n;
  size_t pad;
} block_t;

static void *count_realloc(void *ud, void *p, size_t n) {
  (void)ud;
  block_t *b = p ? (block_t *)p - 1 : NULL;
  size_t old = b ? b->n : 0;
  block_t *nb = realloc(b, sizeof *nb + n);
  if (!nb) {
    failed_request = n;
    return NULL;
  }
  nb->n = n;
  live_bytes = live_bytes - old + n;
  if (live_bytes > peak_bytes)
    peak_bytes = live_bytes;
  return nb + 1;
}

static void count_free(void *ud, void *p) {
  (void)ud;
  if (!p)
    return;
  block_t *b = (block_t *)p - 1;
  live_bytes -= b->n;
  free(b);
}

static bool version(trilog_t *t, void *ud, const trilog_value_t *in,
                    trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  out[0].a = trilog_version();
  return true;
}

static bool board_info(trilog_t *t, void *ud, const trilog_value_t *in,
                       trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  out[0].a = TRILOG_BOARD_NAME;
  uint32_t part = (sysinfo_hw->chip_id & SYSINFO_CHIP_ID_PART_BITS) >>
                  SYSINFO_CHIP_ID_PART_LSB;
  out[1].a = part == 2 ? "rp2040" : part == 4 ? "rp2350" : "unknown";
  out[2].i = clock_get_hz(clk_sys) / 1000000;
  out[3].i = PICO_FLASH_SIZE_BYTES / 1024;
  return true;
}

static bool get_time_ms(trilog_t *t, void *ud, const trilog_value_t *in,
                        trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  out[0].i = (int64_t)(time_us_64() / 1000);
  return true;
}

static bool sleep_for(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  if (in[0].i > 0)
    sleep_ms((uint32_t)in[0].i);
  return true;
}

// Survives a reset; the magic rejects power-on noise and old layouts.
#define CRASH_MAGIC (0x7c4a5e00u ^ (uint32_t)sizeof(crash_t))

typedef struct {
  uint32_t magic, count;
  char reason[24], running[48], trace[160];
  uint32_t uptime_ms, pc, lr;
  uint32_t malloc_in_use, live, peak, failed_request;
  uint32_t heap_cells, heap_capacity, atoms, clauses;
} crash_t;

static crash_t last __attribute__((section(".uninitialized_data")));

static void crash_record(const char *reason, const char *running,
                         bool trace) {
  uint32_t count = last.magic == CRASH_MAGIC ? last.count + 1 : 1;
  struct mallinfo mi = mallinfo();
  last = (crash_t){.magic = CRASH_MAGIC,
                   .count = count,
                   .uptime_ms = to_ms_since_boot(get_absolute_time()),
                   .malloc_in_use = (uint32_t)mi.uordblks,
                   .live = (uint32_t)live_bytes,
                   .peak = (uint32_t)peak_bytes,
                   .failed_request = (uint32_t)failed_request};
  snprintf(last.reason, sizeof last.reason, "%s", reason);
  snprintf(last.running, sizeof last.running, "%s", running);
  if (T && trace)
    snprintf(last.trace, sizeof last.trace, "%s", trilog_fatal_trace(T));
  if (T) {
    trilog_usage_t u;
    trilog_usage(T, &u);
    last.heap_cells = (uint32_t)u.heap_peak_cells;
    last.heap_capacity = (uint32_t)u.heap_capacity_cells;
    last.atoms = (uint32_t)u.atoms;
    last.clauses = (uint32_t)u.clauses;
  }
}

static const char *crash_text(void) {
  static char text[600];
  if (last.magic != CRASH_MAGIC)
    return NULL;
  last.reason[sizeof last.reason - 1] = '\0';
  last.running[sizeof last.running - 1] = '\0';
  last.trace[sizeof last.trace - 1] = '\0';
  snprintf(text, sizeof text,
           "crash %u: %s while running %s, %u ms after boot\n"
           "in %s\n"
           "pc 0x%08x, lr 0x%08x\n"
           "malloc in use %u B, trilog live %u B, peak %u B, last failed "
           "request %u B\n"
           "prolog heap %u/%u cells at most, %u atoms, %u clauses\n",
           (unsigned)last.count, last.reason, last.running,
           (unsigned)last.uptime_ms, last.trace, (unsigned)last.pc,
           (unsigned)last.lr,
           (unsigned)last.malloc_in_use, (unsigned)last.live,
           (unsigned)last.peak, (unsigned)last.failed_request,
           (unsigned)last.heap_cells, (unsigned)last.heap_capacity,
           (unsigned)last.atoms, (unsigned)last.clauses);
  return text;
}

static bool last_crash(trilog_t *t, void *ud, const trilog_value_t *in,
                       trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  out[0].a = crash_text();
  return out[0].a != NULL;
}

__attribute__((used)) void hard_fault(uint32_t *frame) {
  crash_record("hard fault", "", false);
  last.lr = frame[5];
  last.pc = frame[6];
  watchdog_reboot(0, 0, 0);
  for (;;)
    tight_loop_contents();
}

__attribute__((naked)) void isr_hardfault(void) {
  __asm volatile("movs r0, #4\n"
                 "mov r1, lr\n"
                 "tst r0, r1\n"
                 "beq 1f\n"
                 "mrs r0, psp\n"
                 "b 2f\n"
                 "1: mrs r0, msp\n"
                 "2: ldr r1, =hard_fault\n"
                 "bx r1\n");
}

static bool reboot(trilog_t *t, void *ud, const trilog_value_t *in,
                   trilog_value_t *out) {
  (void)t, (void)ud, (void)in, (void)out;
  fflush(stdout);
  watchdog_reboot(0, 0, 100);
  for (;;)
    tight_loop_contents();
}

extern char __flash_binary_end;

static bool flash_usage(trilog_t *t, void *ud, const trilog_value_t *in,
                        trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  out[0].i = &__flash_binary_end - (char *)XIP_BASE;
  out[1].i = PICO_FLASH_SIZE_BYTES;
  return true;
}

static bool memory_usage(trilog_t *t, void *ud, const trilog_value_t *in,
                         trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  struct mallinfo mi = mallinfo();
  out[0].i = mi.uordblks;
  out[1].i = mi.arena;
  out[2].i = &__HeapLimit - &__end__;
  out[3].i = (int64_t)live_bytes;
  out[4].i = (int64_t)peak_bytes;
  return true;
}

static bool prolog_usage(trilog_t *t, void *ud, const trilog_value_t *in,
                         trilog_value_t *out) {
  (void)ud, (void)in;
  trilog_usage_t u;
  trilog_usage(t, &u);
  out[0].i = (int64_t)u.heap_cells;
  out[1].i = (int64_t)u.heap_capacity_cells;
  out[2].i = (int64_t)u.heap_peak_cells;
  out[3].i = (int64_t)u.atoms;
  out[4].i = (int64_t)u.clauses;
  out[5].i = (int64_t)u.arena_bytes;
  return true;
}

static void print_memory(const char *when) {
  struct mallinfo mi = mallinfo();
  printf("[%s] malloc in use %d B, malloc arena %d B, heap region %d B\n", when,
         mi.uordblks, mi.arena, (int)(&__HeapLimit - &__end__));
  printf("[%s] trilog live %u B, peak %u B, last failed request %u B, "
         "stack %u B\n",
         when, (unsigned)live_bytes, (unsigned)peak_bytes,
         (unsigned)failed_request, stack_used());
  if (T) {
    trilog_usage_t u;
    trilog_usage(T, &u);
    printf("[%s] prolog heap %u/%u cells, peak %u B, arena %u B, "
           "%u atoms, %u clauses\n",
           when, (unsigned)u.heap_cells, (unsigned)u.heap_capacity_cells,
           (unsigned)u.heap_peak_bytes, (unsigned)u.arena_bytes,
           (unsigned)u.atoms, (unsigned)u.clauses);
  }
}

static bool crashed(trilog_status_t s) {
  return s == TRILOG_ABORTED ||
         (s == TRILOG_ERROR &&
          trilog_term_type(T, trilog_error_term(T)) == TRILOG_INVALID);
}

// The Prolog toplevel does not fit in the board's RAM.
static void repl(void) {
  static char line[512];
  printf("trilog %s\n", trilog_version());
  const char *crash = crash_text();
  if (crash)
    printf("last %s", crash);
  for (;;) {
    fputs("?- ", stdout);
    size_t n = 0;
    int key = toplevel_typed_ahead();
    if (key != EOF) {
      line[n++] = (char)key;
      putchar(key);
    }
    fflush(stdout);
    if (!terminal_read_line(line + n, sizeof line - n))
      return;
    const char *p = line;
    while (*p == ' ' || *p == '\t')
      p++;
    trilog_status_t s = *p ? toplevel_query(T, line, true) : TRILOG_TRUE;
    if (crashed(s))
      crash_record(s == TRILOG_ABORTED ? "aborted" : "out of memory", line,
                   true);
  }
}

int main(void) {
  paint_stack();
  stdio_init_all();

  print_memory("before boot");
  wifi_init();
  print_memory("after wifi");
  T = trilog_new(&(trilog_config_t){
      .realloc = count_realloc, .free = count_free, .gc_threshold = 1024});
  if (!T) {
    print_memory("boot failed");
    for (;;)
      tight_loop_contents();
  }
  print_memory("after boot");

  trilog_register(T, "get_time_ms", ">i", get_time_ms, NULL);
  trilog_register(T, "sleep_ms", "i", sleep_for, NULL);
  trilog_register(T, "reboot", "", reboot, NULL);
  trilog_register(T, "$trilog_version", ">a", version, NULL);
  trilog_register(T, "board_info", ">aaii", board_info, NULL);
  trilog_register(T, "memory_usage", ">iiiii", memory_usage, NULL);
  trilog_register(T, "prolog_usage", ">iiiiii", prolog_usage, NULL);
  trilog_register(T, "flash_usage", ">ii", flash_usage, NULL);
  trilog_register(T, "last_crash", ">a", last_crash, NULL);
  wifi_register(T);
  tcp_register(T);
  vfs_register(T);
  mail_register(T);
  trilog_set_io(T, &board_io);

  const char *running = "main";
  trilog_status_t s = toplevel_query(T, running, false);
  for (int idle = 0; crashed(s);) {
    crash_record(s == TRILOG_ABORTED ? "aborted" : "out of memory", running,
                 true);
    tcp_fail_all(s == TRILOG_ABORTED ? "aborted" : "out of memory");
    trilog_close_streams(T);
    tcp_drop_all();
    if (++idle == 3) {
      mail_post("trilog", "crashed 3 times",
                "The server crashed 3 times without taking a request. It "
                "stays stopped; use serve(80) at the prompt.\n");
      break;
    }
    mail_post("trilog", "crashed",
              s == TRILOG_ABORTED
                  ? "A request was aborted. The server was restarted.\n"
                  : "A request ran trilog out of memory. The server was "
                    "restarted.\n");
    unsigned before = tcp_accept_count();
    running = "serve(80)";
    s = toplevel_query(T, running, false);
    if (tcp_accept_count() != before)
      idle = 0;
  }
  for (;;)
    repl();
}

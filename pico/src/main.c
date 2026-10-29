#include "hardware/clocks.h"
#include "hardware/structs/sysinfo.h"
#include "hardware/watchdog.h"
#include "pico/stdlib.h"
#include "toplevel.h"
#include "trilog.h"
#include <malloc.h>
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

static bool reboot(trilog_t *t, void *ud, const trilog_value_t *in,
                   trilog_value_t *out) {
  (void)t, (void)ud, (void)in, (void)out;
  fflush(stdout);
  watchdog_reboot(0, 0, 100);
  for (;;)
    tight_loop_contents();
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
  wifi_register(T);
  tcp_register(T);
  vfs_register(T);
  trilog_set_io(T, &tcp_io);

  toplevel_query(T, "main", false);
  for (;;)
    toplevel_repl(T);
}

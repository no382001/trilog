#include "hd44780.h"
#include "leds.h"
#include "pico/stdlib.h"
#include "trilog.h"
#include <malloc.h>
#include <stdio.h>
#include <string.h>

extern char __end__, __HeapLimit;

extern char __StackTop, __scratch_x_start__;
#define STACK_TOP ((uint32_t)&__StackTop)
#define STACK_PAINT_LO ((uint32_t)&__scratch_x_start__)

static void paint_stack(void) {
  volatile uint32_t here;
  for (uint32_t *w = (uint32_t *)STACK_PAINT_LO; w < (uint32_t *)&here - 64; w++)
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

static bool lcd_clear(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)t, (void)ud, (void)in, (void)out;
  hd44780_clear();
  return true;
}

static bool lcd_row(trilog_t *t, void *ud, const trilog_value_t *in,
                    trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  if (in[0].i < 0 || in[0].i >= LCD_ROWS)
    return false;
  hd44780_puts((uint8_t)in[0].i, in[1].a);
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

static void print_term(trilog_term_t term) {
  char buf[256];
  size_t n = trilog_format(T, term, TRILOG_FORMAT_QUOTED, buf, sizeof buf);
  printf("%s", buf);
  if (n >= sizeof buf)
    printf("%s", "...");
}

typedef struct {
  bool any;
  bool closed;
} answer_state;

static bool on_solution(trilog_t *t, void *ud, bool has_more) {
  answer_state *st = ud;
  printf("%s", st->any ? "\n;  " : "   ");
  st->any = true;
  char buf[256];
  size_t n = trilog_format_answer(t, buf, sizeof buf);
  printf("%s", buf);
  if (n >= sizeof buf)
    printf("%s", "...");
  if (!has_more) {
    printf("%s", ".\n");
    st->closed = true;
    return false;
  }
  int key = getchar();
  if (key == ';' || key == ' ')
    return true;
  printf("%s", "\n;  ... .\n");
  st->closed = true;
  return false;
}

static bool read_line(char *buf, int size) {
  int i = 0;
  for (;;) {
    int c = getchar();
    if (c == EOF)
      return false;
    if (c == '\r' || c == '\n') {
      putchar('\n');
      break;
    }
    if (c == 127 || c == '\b') {
      if (i > 0) {
        i--;
        printf("%s", "\b \b");
      }
      continue;
    }
    if (i < size - 1) {
      buf[i++] = (char)c;
      putchar(c);
    }
  }
  buf[i] = '\0';
  return true;
}

static void query(const char *goal) {
  answer_state st = {0};
  switch (trilog_query(T, goal, on_solution, &st)) {
  case TRILOG_TRUE:
    if (!st.closed)
      printf("%s", ".\n");
    break;
  case TRILOG_ABORTED:
    break;
  case TRILOG_FALSE:
    printf("%s", "   false.\n");
    break;
  case TRILOG_ERROR:
    if (trilog_term_type(T, trilog_error_term(T)) != TRILOG_INVALID) {
      printf("%s", "uncaught exception: ");
      print_term(trilog_error_term(T));
      putchar('\n');
    }
    break;
  case TRILOG_HALT:
    break;
  }
}

int main(void) {
  paint_stack();
  stdio_init_all();
  leds_init();
  hd44780_init();
  hd44780_puts(0, "trilog");

  printf("trilog %s\n", trilog_version());
  print_memory("before boot");
  T = trilog_new(&(trilog_config_t){.realloc = count_realloc, .free = count_free});
  if (!T) {
    print_memory("boot failed");
    hd44780_puts(1, "boot failed");
    for (;;)
      tight_loop_contents();
  }
  print_memory("after boot");

  leds_register(T);
  trilog_register(T, "lcd_clear", "", lcd_clear, NULL);
  trilog_register(T, "lcd_row", "ia", lcd_row, NULL);
  trilog_load_string(T, "led(0). led(1). led(2). led(3). led(4).");

  char line[256];
  for (;;) {
    printf("%s", "?- ");
    if (!read_line(line, sizeof line))
      break;
    if (line[strspn(line, " \t")] == '\0')
      continue;
    query(line);
    print_memory("after query");
  }

  hd44780_puts(0, "halted.");
  hd44780_puts(1, "");
  return 0;
}

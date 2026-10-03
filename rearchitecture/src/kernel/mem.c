#include "mem.h"
#include "ctx.h"
#include "io.h"
#include <setjmp.h>
#include <stdint.h>

void *mem_realloc(trilog_t *T, void *p, size_t n) {
  if (n == 0) {
    mem_free(T, p);
    return NULL;
  }
  return T->alloc_realloc(T->alloc_ud, p, n);
}

void *mem_grow_n(trilog_t *T, void *p, size_t count, size_t size) {
  if (size != 0 && count > SIZE_MAX / size)
    mem_fail(T);
  void *r = mem_realloc(T, p, count * size);
  if (!r && count * size != 0)
    mem_fail(T);
  return r;
}

void mem_free(trilog_t *T, void *p) {
  if (p)
    T->alloc_free(T->alloc_ud, p);
}

_Noreturn void mem_fail(trilog_t *T) {
  io_write_err(T, "out of memory\n");
  longjmp(T->fatal_jmp, 1);
}

_Noreturn void engine_halt(trilog_t *T, int code) {
  T->halted = true;
  T->halt_code = code;
  longjmp(T->fatal_jmp, 1);
}

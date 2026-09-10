#pragma once
#include "solve.h"
#include <stddef.h>
#include <stdint.h>

// Mark-and-slide with pointer reversal loosely based on Appleby, Carlsson,
// Haridi & Sahlin 1988 Only safe to call from run_query's label A
void gc_maybe_run(size_t *cn, frame_t *frames, size_t nframes, size_t *rename,
                  int32_t nvars, size_t *active_catch);

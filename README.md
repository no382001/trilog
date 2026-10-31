# trilog

[![CI](https://github.com/no382001/trilog/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/no382001/trilog/actions/workflows/ci.yml?query=branch%3Amain)

A Prolog interpreter aiming to be embeddable.

Tri as in three, is a play on the 3 states of the the stack machine that is the ABC algorithm in M. H. van Emden's *An Algorithm for Interpreting Prolog Programs* (University of Waterloo, CS-81-28, 1981). ABC is not short for anything. A, B and C are the three labels: go down while there is an untried alternative, come back up and try the next one when there is not, and fail once you have climbed past the root. trilog's solver is built on this algorithm.

## Contents

- [Build](#build)
- [Embedding](#embedding)
- [Libraries](#libraries)
- [History](#history)
- [License](#license)

## Build

You need `build-essential` and `clang-format`.

```sh
make           # debug build: ./trilog
make release   # release build: _build/trilog and _build/release-posix/libtrilog.a
```

The release build has the Prolog core and libraries built in, so it runs without the source tree.

## Embedding

This program prints every answer to a query. Save it as `hello.c`:

```c
#include "trilog.h"
#include <stdio.h>

static bool print_answer(trilog_t *t, void *ud, bool has_more) {
  (void)ud;
  for (int i = 0; i < trilog_binding_count(t); i++) {
    char text[64];
    trilog_format(t, trilog_binding_value(t, i), 0, text, sizeof text);
    printf("%s%s = %s", i ? ", " : "", trilog_binding_name(t, i), text);
  }
  printf("\n");
  return has_more;
}

int main(void) {
  trilog_t *t = trilog_new(NULL);
  if (!t)
    return 1;
  trilog_load_string(t, "double(X, Y) :- Y is X * 2.");
  trilog_query(t, "member(X, [1, 2, 3]), double(X, Y)", print_answer, NULL);
  trilog_free(t);
  return 0;
}
```

```sh
cc -std=c11 -Iinclude hello.c _build/release-posix/libtrilog.a -lm -o hello
./hello
```

```text
X = 1, Y = 2
X = 2, Y = 4
X = 3, Y = 6
```

The public API is [`include/trilog.h`](include/trilog.h):

| Function | Use |
| --- | --- |
| `trilog_new`, `trilog_free` | create and destroy an interpreter; `trilog_config_t` sets the allocator, I/O, and how the heap and GC grow |
| `trilog_load_file`, `trilog_load_string` | load Prolog code |
| `trilog_query` | run a goal, calling back once per answer |
| `trilog_binding_count`, `trilog_binding_name`, `trilog_binding_value` | read an answer's bindings |
| `trilog_term_type`, `trilog_get_int`, `trilog_get_float`, `trilog_get_atom`, `trilog_get_functor`, `trilog_get_arg` | inspect a term |
| `trilog_format`, `trilog_format_answer` | write a term, or the current answer as the toplevel shows it, as text |
| `trilog_error_term`, `trilog_halt_code` | why a query stopped |
| `trilog_register`, `trilog_error` | define a predicate in C, and raise an error from it |
| `trilog_set_io` | replace the I/O hooks |
| `trilog_set_yield` | call back every N steps, to stop a long query |
| `trilog_usage`, `trilog_version` | memory use and build version |

[`examples/embed.c`](examples/embed.c) uses `trilog_register` and `trilog_set_yield`.

The library builds three ways:

| Build | Command | Notes |
| --- | --- | --- |
| POSIX | `make release` | the default |
| no POSIX | `make PLATFORM=no_posix release` | needs a C library but no POSIX; no `get_time_ms/1` or `file_mtime/2`, so `make/0` raises `existence_error`; relative file names are not made absolute |
| freestanding | `make PLATFORM=freestanding release` | no C library, for kernels and firmware; builds only `libtrilog.a` |

The freestanding build has no default allocator or I/O, so `trilog_new` needs both in `trilog_config_t`. It calls only `mem*`, `str*`, `setjmp`, `longjmp` and libm, plus two functions for float text that the embedder defines. You can find the list in: [`include/trilog_platform.h`](include/trilog_platform.h), and an example for the complete embedding in: [`test/api/api_freestanding_test.c`](test/api/api_freestanding_test.c).

## Libraries

The core holds the built-in predicates. Everything else is a library in [`lib/`](lib/), loaded with `ensure_loaded(library(Name))`. There is no module system yet: `use_module(library(Name))` is accepted as a placeholder and does the same as `ensure_loaded/1`.

| Library | Contents | Loaded by |
| --- | --- | --- |
| `lists` | `append/3`, `member/2`, `length/2`, `nth0/3`, `reverse/2`, `select/3`, … | the core |
| `error` | `must_be/2`, `can_be/2` | the core |
| `misc` | `forall/2`, `with_output_to/2`, `numbervars/3`, `writeln/1` | the core |
| `apply` | `maplist/2..`, `foldl/4`, `include/3`, `exclude/3` | the core |
| `dcgs` | DCG translation, `phrase/2,3` | the CLI |
| `between` | `between/3`, `succ/2`, `plus/3` | the CLI |
| `charsio` | `read_term_from_chars/3`, `write_term_to_chars/3` | the CLI |
| `make` | `make/0`, `consulted/1`, `unconsult/1` | the CLI |

`trilog_new` loads only the core. The CLI also loads the four marked "the CLI"; `./trilog -n` skips them.

## History

trilog uses the ABC algorithm because it is very simple. Van Emden himself presented it that way:

> The only novelty we believe this paper to have is the human-oriented form of the algorithm and its derivation from a mathematical description of the SLD (Selective Linear Definite clause resolution) theorem-prover. — M. H. van Emden, *An interpreting algorithm for Prolog programs*, First International Logic Programming Conference (1982)

trilog is not a WAM. The goal is the most efficient interpreter that stays this simple. A WAM would be much faster, but trilog is fast enough for now; a WAM-style backend may come later.

The first engine is on `main` ([`a3536a4`](https://github.com/no382001/trilog/commit/a3536a4597ec586ace19cc373ceccc0b86343f0b)). Lots of things already worked there, but it was getting harder to see what the engine was actually doing, and the design problems kept piling up. So it was rewritten, starting again from the solver:

> The only applicable research method is to accumulate experience by implementing a system, synthesize the experience, think for a while and start over. — E. Sandewall, *Programming in an Interactive Environment: The LISP Experience* (1978)

Both engines were measured on the same machine with `perf stat`: the current engine as a release build, the first engine with `-O2` and no sanitiser. Times are median CPU time (`task-clock`) of 7 runs (63 for start-up). Instructions are user-space instructions retired, which barely change between runs. Peak memory is measured with GNU `time`. "Now" runs `./trilog -n`, which loads only the core; the benchmarks need nothing else. `fib/2` cuts on `N < 2`, because the first engine runs out of stack on the version without the cut.

| Workload | First engine | Now | Faster | Fewer instructions | Less memory |
| --- | --- | --- | --- | --- | --- |
| start and exit | 10.0 ms, 12.5M ins, 2.6 MB | 4.3 ms, 5.7M ins, 2.2 MB | 2.3x | 2.2x | 1.2x |
| naive reverse, 300 elements | 1,418 ms, 4,222M ins, 232 MB | 49 ms, 157M ins, 2.8 MB | 29x | 27x | 84x |
| 8 queens, all solutions | 4,029 ms, 14,289M ins, 16.3 MB | 512 ms, 2,595M ins, 2.5 MB | 7.9x | 5.5x | 6.5x |
| `fib(21)` | 4,525 ms, 7,809M ins, 61 MB | 80 ms, 218M ins, 2.8 MB | 56x | 36x | 22x |
| build 20,000 atoms | 11,766 ms, 41,079M ins, 28.9 MB | 1,006 ms, 4,107M ins, 3.3 MB | 12x | 10x | 8.6x |

On average (geometric mean) the new engine is 12.8x faster, runs 10.3x fewer instructions and uses 10.4x less memory.

Without `-n`, the CLI also loads its four libraries, and start-up takes 5.2 ms, 10.1M instructions and 2.7 MB.

## License

MIT, see [LICENSE](LICENSE).

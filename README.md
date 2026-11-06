# trilog

[![CI](https://github.com/no382001/trilog/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/no382001/trilog/actions/workflows/ci.yml?query=branch%3Amain)

An embeddable Prolog interpreter written in C11, aiming for ISO conformance.

The "tri" is for three: the three states of the ABC algorithm, which trilog's solver is built on (see [How the solver works](#how-the-solver-works)). The "tri" could also, coincidentally, refer to Trismegistos, the thrice-great, quoted in [History](#history).

## Contents

- [Current goals](#current-goals)
- [Build](#build)
- [Embedding](#embedding)
- [Libraries](#libraries)
- [How the solver works](#how-the-solver-works)
- [History](#history)
- [License](#license)

## Current goals

- **Conformity.** Syntax comes first: trilog passes 336 of the 366 [syntactic conformity tests](https://www.complang.tuwien.ac.at/ulrich/iso-prolog/conformity_testing). Where the standard leaves room, as in how the toplevel prints answers or which error a library predicate throws, trilog follows [Scryer Prolog](https://codeberg.org/mthom/scryer-prolog).
- **Useful work on a Raspberry Pi Pico W.** The aim is a system that does real tasks (at least) on a 264 KB microcontroller, written in portable ISO Prolog, with C only for the hardware. [`pico/`](pico/) is the current state: an HTTP server in Prolog that serves pages, switches the LED, and shows memory stats, a mail log and the files built into the image.

## Build

You need `build-essential` and `clang-format` 21.1.8 (`pipx install clang-format==21.1.8`). Every build formats the C sources first, and an older `clang-format` rewrites some of them.

```sh
make           # debug build: ./trilog
make release   # release build: _build/trilog and _build/release-posix/libtrilog.a
```

The release build has the Prolog core and libraries built in, so it runs without the source tree.

| Command | Runs |
| --- | --- |
| `make test` | the system tests in `test/e2e/` and the C API tests |
| `make quad` | the Prolog tests in `test/quad/` |
| `make conformity` | the ISO conformity tests in `test/conformity/` |
| `make check` | every suite, as CI does; fails on a failure not in `test/known_failures.txt` |
| `make format` | `clang-format` on every C source |

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

`trilog_new(NULL)` creates an interpreter with the defaults: the C library's `realloc` and `free`, standard files for I/O, and the Prolog core built into the library. Pass a `trilog_config_t` to change any of these; a freestanding build has no defaults and the embedder must supply them.

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

[`examples/embed.c`](examples/embed.c) uses `trilog_register` and `trilog_set_yield`. [`pico/`](pico/) embeds trilog on a Raspberry Pi Pico W, with an HTTP server written as Prolog modules in [`pico/prolog/`](pico/prolog/).

The library builds three ways:

| Build | Command | Notes |
| --- | --- | --- |
| POSIX | `make release` | the default |
| no POSIX | `make PLATFORM=no_posix release` | needs a C library but no POSIX; no `get_time_ms/1` or `file_mtime/2`, so `make/0` raises `existence_error`; relative file names are not made absolute |
| freestanding | `make PLATFORM=freestanding release` | no C library, for kernels and firmware; builds only `libtrilog.a` |

The freestanding build has no default allocator or I/O, so `trilog_new` needs both in `trilog_config_t`. It calls only `mem*`, `str*`, `setjmp`, `longjmp` and libm, plus two functions for float text that the embedder defines. The list is in [`include/trilog_platform.h`](include/trilog_platform.h), and [`test/api/api_freestanding_test.c`](test/api/api_freestanding_test.c) is a complete example.

## Libraries

The core holds the built-in predicates. Everything else is a library in [`lib/`](lib/), loaded with `use_module(library(Name))` or `ensure_loaded(library(Name))`.

A file that starts with `:- module(Name, Exports).` is a module. Its exported predicates are visible everywhere, and the rest are private to it. `Module:Goal` calls a module's predicate, private or not, and `meta_predicate/1` makes goals passed into a module run in the caller's module. `lists` is a module. The module system is new and may still change: private predicates are renamed when the file loads, so there is one global predicate table rather than one per module.

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

## How the solver works

The solver is the ABC algorithm from M. H. van Emden's *An Algorithm for Interpreting Prolog Programs* (University of Waterloo, CS-81-28, 1981). It walks Prolog's search tree depth first, with an explicit stack instead of recursion, so a deep program does not use up the C stack.

ABC is not short for anything, the way WAM is short for Warren's Abstract Machine. A, B and C are the labels of the algorithm's three states. This is van Emden's stack version (Fig. 2 in the paper). `cn` is the current node, `son(cn, x)` hands out the next untried child of `cn`, and `P(cn)` is the property being searched for:

```text
initialize the stack at empty
cn := root
push cn

A: if P(cn)
      then halt with success
      else initialise son( ) for cn;
           goto B
   fi

B: if son(cn, x)
      then {x is the next son of cn}
           cn := x; push cn; goto A
      else {all sons of cn have been tried}
           pop stack; goto C
   fi

C: if stack empty
      then halt with failure
      else cn becomes top of stack
           goto B
   fi
```

- **A** asks whether we are done.
- **B** tries to go one level deeper.
- **C** climbs back up when there is nowhere left to go at the current level.

For Prolog, a node is the list of goals still to prove, and its children are the clauses whose head unifies with the first goal. `P(cn)` holds when no goals are left, so A has found an answer. trilog reports it and goes on to C to look for the next one. B tries the clauses in order, skipping the ones whose first argument cannot match, and a matching clause's body replaces the goal it matched.

The labels `A:`, `B:` and `C:` are in `solve()` in [`src/kernel/solve.c`](src/kernel/solve.c). Each stack frame (`frame_t` in [`src/kernel/solve.h`](src/kernel/solve.h)) holds what C needs to resume: the goal list, the index of the next clause to try, the heap and trail marks to undo bindings back to, and the stack depth a cut removes frames down to.

## History

trilog was started as an effort to understand how a Prolog system works by building one, because:

> Μαθεῖν θέλω τὰ ὄντα καὶ νοῆσαι τὴν τούτων φύσιν καὶ γνῶναι τὸν θεόν. "I wish to learn about the things that are, to understand their nature and to know God." — *Poimandres* (Corpus Hermeticum I.3)

trilog uses the ABC algorithm because it is simple, where an efficient solver is usually complicated. As van Emden puts it:

> The only novelty we believe this paper to have is the human-oriented form of the algorithm and its derivation from a mathematical description of the SLD (Selective Linear Definite clause resolution) theorem-prover. — M. H. van Emden, *An interpreting algorithm for Prolog programs*, First International Logic Programming Conference (1982)

trilog has no WAM. The goal is the most efficient interpreter that stays this simple. A WAM, ZIP or BinWAM backend would be much faster. trilog is fast enough for now, but one would be nice to have later.

The first engine is on [`a3536a4`](https://github.com/no382001/trilog/commit/a3536a4597ec586ace19cc373ceccc0b86343f0b). Lots of things already worked there, but it was getting harder to see what the engine was actually doing and the design problems kept piling up. It also did not fit on a Raspberry Pi Pico W, which was the goal. So it was rewritten from the ground up, because:

> The only applicable research method is to accumulate experience by implementing a system, synthesize the experience, think for a while and start over. — E. Sandewall, *Programming in an Interactive Environment: The LISP Experience* (1978)

Both engines were measured on the same machine, an AMD Ryzen 5 5600, with [`test/perf/run.sh`](test/perf/run.sh): the current engine as a release build, the first engine with `-O2` and no sanitizer. Each figure is the median of 7 runs (63 for start-up). Times are CPU time (`task-clock`). Instructions are user-space instructions retired, which barely change between runs. Peak memory is the peak resident set size. "Now" runs `_build/trilog -f -n`, which loads only the core; the benchmarks need nothing else. `fib/2` cuts on `N < 2`, because the first engine runs out of stack on the version without the cut.

| Workload | First engine | Now, v0.2.0 ([`5b8feef`](https://github.com/no382001/trilog/commit/5b8feef550df7375eab563fd1a72ab316da3899e)) | Faster | Fewer instructions | Less memory |
| --- | --- | --- | --- | --- | --- |
| start and exit | 2.35 ms, 14.3M ins, 4.5 MB | 0.52 ms, 1.1M ins, 2.4 MB | 4.5x | 13x | 1.9x |
| naive reverse, 300 elements | 308 ms, 4,373M ins, 234 MB | 7.0 ms, 105M ins, 3.0 MB | 44x | 42x | 78x |
| 8 queens, all solutions | 1,014 ms, 14,376M ins, 18.4 MB | 128 ms, 2,137M ins, 2.5 MB | 7.9x | 6.7x | 7.4x |
| `fib(21)` | 648 ms, 6,686M ins, 57.3 MB | 11.9 ms, 178M ins, 3.0 MB | 54x | 37x | 19x |
| build 20,000 atoms | 3,822 ms, 41,105M ins, 31.5 MB | 237 ms, 3,473M ins, 3.3 MB | 16x | 12x | 9.5x |

On average (geometric mean) the new engine is 16.9x faster, runs 17.5x fewer instructions and uses 11.5x less memory. Sadly the interpreter used to be marginally faster in some previous commits after the rearchitecture, but added features lost some performance.

Without `-n`, the CLI also loads its four libraries, and start-up takes 1.1 ms, 5.3M instructions and 2.9 MB.

## License

MIT, see [LICENSE](LICENSE).

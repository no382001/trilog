# trilog

A lightweight, embeddable Prolog interpreter written in C11.

## Build

```sh
make
```

## Usage

```sh
./trilog                  # interactive REPL
./trilog -f file.pl       # load file
./trilog -e "goal."       # evaluate and exit
./trilog -q tests.pl      # run quad tests
```

## Language

Standard Prolog syntax. Integers, atoms, functors, lists, rules and facts. Comments: `%` line comments and `/* */` block comments. Character code notation: `0'a` evaluates to 97.

**Operators**

| Operators | Prec | Notes |
|-----------|------|-------|
| `* / // mod >> << /\ xor` | 40 | `>>` `<<` shift; `/\` bitwise and |
| `+ - \/` | 30 | `\/` bitwise or |
| `< > =< >= =:= =\= == \== @< @> @=< @>=` | 20 | |
| `is = \= =..` | 10 | |
| `->` | 7 | if-then |
| `^` | 6 | existential quantification |
| `;` | 5 | disjunction / if-then-else |

Prefix: `\+` (negation), `\` (bitwise complement).

**Arithmetic** (`is/2`)

Integer arithmetic. Operators: `+ - * / // mod max min >> << /\ \/ xor`. Unary: `- abs \`. ISO overflow and zero-divisor errors are raised.

**Built-ins**

| | |
|-|-|
| `true` `fail` `!` | basics |
| `\+(G)` `call(G)` `once(G)` | meta-call |
| `,(G,G)` `;(G,G)` `->(G,G)` | control |
| `throw(T)` `catch(G,C,R)` | exceptions (`error(Formal, Context)` convention) |
| `findall/3` `bagof/3` `setof/3` | aggregation; `X^Goal` for existential quantification |
| `consult(F)` `include(F)` `make` | loading |
| `assertz(C)` `asserta(C)` `assert(C)` `retract(H)` `retractall(H)` | database |
| `dynamic/1` `abolish/1` | database declarations |
| `current_prolog_flag/2` | flags: `max_integer`, `min_integer`, `bounded`, `integer_rounding_function` |
| `var/nonvar/atom/integer/number/atomic/compound/callable/string/is_list` | type tests |
| `functor/3` `arg/3` `=../2` `copy_term/2` | introspection |
| `is/2` `succ/2` `plus/3` | arithmetic |
| `compare/3` | standard order |
| `sort/2` `msort/2` | sorting |
| `atom_length/2` `atom_concat/3` `atom_chars/2` `atom_codes/2` | atoms |
| `sub_atom/5` | substring search/decomposition |
| `char_code/2` `atom_number/2` `number_chars/2` `number_codes/2` | conversion |
| `atom_to_term/3` `term_to_atom/2` | term <-> atom |
| `write/1` `writeln/1` `writeq/1` `nl` | output |
| `with_output_to(+Sink, +Goal)` | capture output; Sink: `atom(A)`, `string(S)`, `codes(Cs)`, `chars(Chs)` |
| `open(+Path, +Mode, -Stream)` `close(+Stream)` | file streams; Mode: `read`, `write`, `append` |
| `read_line_to_atom(+Stream, -Atom)` | read one line; unifies `end_of_file` at EOF |
| `read_term(+Stream, -Term)` | read and parse one term from a stream |
| `get_char(-Char)` | read one character from stdin |

**Standard library (`core.pl`, loaded automatically)**

`between/3`, `forall/2`, `member/2`, `append/3`, `length/2`, `reverse/2`, `last/2`

## Embedding

### Context allocation

The context uses a flexible array member for its term pool and must be heap-allocated:

```c
trilog_ctx_t *ctx = malloc(TRILOG_CTX_SIZE(TERM_POOL_BYTES));
trilog_ctx_init(ctx, TERM_POOL_BYTES);
io_hooks_init_default(ctx);
// ... use ctx ...
free(ctx);
```

`TERM_POOL_BYTES` is 4 MB by default. Adjust as needed for your target.

### Custom builtins (FFI)

```c
builtin_result_t my_handler(trilog_ctx_t *ctx, term_t *goal, env_t *env) {
    term_t *arg = deref(env, goal->args[0]);
    // ... inspect/unify args ...
    return BUILTIN_OK; // or BUILTIN_FAIL / BUILTIN_ERROR
}
ffi_register_builtin(ctx, "my_pred", 1, my_handler, NULL);
```

See `examples/ffi_example.c` for a complete example.

### I/O hooks

All interpreter I/O goes through a hook struct, so you can redirect it entirely — useful for embedding in applications, GUIs, or constrained environments.

```c
io_hooks_t hooks = {0};
hooks.write_str  = my_write;    // void(ctx, str, userdata)
hooks.writef     = my_writef;   // void(ctx, fmt, va_list, userdata)
hooks.writef_err = my_writef;   // stderr channel
hooks.read_char  = my_getchar;  // int(ctx, userdata)
hooks.read_line  = my_readline; // char*(ctx, buf, size, userdata)
// file i/o (needed for consult/include):
hooks.file_open      = my_fopen;
hooks.file_close     = my_fclose;
hooks.file_read_line = my_freadline;
hooks.file_write     = my_fwrite;
hooks.file_exists    = my_exists;
hooks.file_mtime     = my_mtime;
hooks.clock_monotonic = my_clock; // for test timing
hooks.userdata = my_state;
io_hooks_set(ctx, &hooks);
```

Only set the callbacks you need; unset ones fall back to the defaults (`stdio`/`libc`).

### Freestanding (no libc)

Define `TRILOG_FREESTANDING` before including `trilog.h`. The header then expects no standard includes — you provide the required primitives as macros:

```c
#define TRILOG_FREESTANDING
#define strcmp   my_strcmp
#define strlen   my_strlen
#define memcpy   my_memcpy
#define vsnprintf my_vsnprintf
// ... etc.
#include "trilog.h"
```

All output must be handled through I/O hooks; there is no fallback to `printf`. See `examples/freestanding.c` for a build smoke-test.

```sh
make freestanding   # verifies the library links without libc
```

## Testing

Tests use the [quad format](https://web.liminal.cafe/~byakuren/flowlog/docs/QUAD_TESTS.html) — plain `.pl` files containing queries and their expected output:

```prolog
?- member(X, [a, b, c]).
   X = a
;  X = b
;  X = c.

?- atom_length(hello, N).
   N = 5.

?- foo(1).
   false.
```

```sh
make quad          # TAP output
make quad-junit    # JUnit XML → _build/test-results/
```

ISO 13211-1 conformance tests (`test/iso_quad.pl`) run but do not fail the build.

## Algorithm

Based on the **ABC algorithm** from M.H. van Emden's *"An Algorithm for Interpreting PROLOG Programs"* (1981): a depth-first, left-to-right SLD resolution loop with an explicit stack for backtracking. Each clause invocation gets fresh variables via an integer counter. The term pool uses a dual-ended bump allocator: temporary query terms grow up from offset 0, permanent clause terms grow down from the top.

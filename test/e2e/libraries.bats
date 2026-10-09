#!/usr/bin/env bats

# Libraries: ensure_loaded(library(Name)), use_module/1 and where libraries are found.

load common

@test "ensure_loaded(library(lists)) loads a library once" {
  run "$TRILOG" -f -e "
    ensure_loaded(library(lists)),
    ensure_loaded(library(lists)),
    findall(X-Y, append(X, Y, [a]), L),
    length(L, N),
    write(n(N)),
    nl.
  "
  [[ "$output" == *"n(2)"* ]]
}

@test "use_module(library(Name)) loads like ensure_loaded/1" {
  run "$TRILOG" -f -e "
    use_module(library(apply)),
    use_module(library(apply)),
    maplist(succ, [1, 2], L),
    write(L),
    nl.
  "
  [[ "$output" == *"[2, 3]"* ]]
}

@test "a library that does not exist raises existence_error(source_sink, library(Name))" {
  run "$TRILOG" -f -e "
    catch(ensure_loaded(library(nope)), error(E, _), true),
    writeq(E),
    nl.
  "
  [[ "$output" == *"existence_error(source_sink, library(nope))"* ]]
}

@test "library(Name) resolves next to the core, whatever the caller's directory" {
  dir="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$dir"
  printf ':- ensure_loaded(library(meta)).\nt(X) :- solve(member(X, [a, b])).\n' > "$dir/prog.pl"
  bin="$(cd "$(dirname "$TRILOG")" && pwd)/$(basename "$TRILOG")"
  cd "$dir"
  run "$bin" -f prog.pl -e "findall(X, t(X), L), write_canonical(L), nl."
  [[ "$output" == *"[a, b]"* ]]
}

@test "consulting a loaded file by another path does not add its clauses twice (regression)" {
  # regression: boot loads boot/../lib/lists.pl, and consult('lib/lists.pl') counted as a different file.
  run "$TRILOG" -f -e "
    consult('lib/lists.pl'),
    findall(X-Y, append(X, Y, [a]), L),
    length(L, N),
    write(n(N)),
    nl.
  "
  [[ "$output" == *"n(2)"* ]]
}

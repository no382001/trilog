#!/usr/bin/env bats

# The library and the build: release, no_posix and freestanding builds, exported symbols, the C++ header.

load common

@test "the release build runs from an empty directory, its libraries baked in" {
  run make -s -C "$BATS_TEST_DIRNAME/../.." release
  [ "$status" -eq 0 ]
  dir=$(mktemp -d)
  cp "$BATS_TEST_DIRNAME/../../_build/trilog" "$dir/"
  run bash -c "cd '$dir' && ./trilog -f -e \"append(X, [c], [a,b,c]), maplist(atom, X), phrase([a], [a]), consult('lib/meta.pl'), findall(Y, solve(member(Y, [1, 2])), L), write(done(L)), nl.\""
  rm -rf "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done([1, 2])"* ]]
  [[ "$output" != *"uncaught"* ]]
  [[ "$output" != *"cannot open"* ]]
}

@test "the no_posix platform build links no POSIX symbols and runs" {
  run make -s -C "$BATS_TEST_DIRNAME/../.." PLATFORM=no_posix release
  [ "$status" -eq 0 ]
  bin="$BATS_TEST_DIRNAME/../../_build/trilog"
  run bash -c "nm -u '$bin' | grep -wE 'clock_gettime|getrlimit|stat|isatty|tcgetattr|tcsetattr|readlink|fileno'"
  [ "$status" -ne 0 ]
  dir=$(mktemp -d)
  cp "$bin" "$dir/"
  run bash -c "cd '$dir' && ./trilog -f -e \"append(X, [bb], [aa,bb]), write(ok(X)), nl, catch(get_time_ms(_), error(E1, _), true), catch(make, error(E2, _), true).\""
  rm -rf "$dir"
  make -s -C "$BATS_TEST_DIRNAME/../.." release
  [[ "$output" == *"ok([aa])"* ]]
  [[ "$output" == *"E1 = existence_error(procedure, /(get_time_ms, 1))"* ]]
  [[ "$output" == *"E2 = existence_error(procedure, /(file_mtime, 2))"* ]]
}

@test "the freestanding build needs only mem*, str*, setjmp, libm and the two float functions, and runs" {
  root="$BATS_TEST_DIRNAME/../.."
  run make -s -C "$root" PLATFORM=freestanding release
  [ "$status" -eq 0 ]
  lib="$root/_build/release-no_posix-nolibc/libtrilog.a"
  printf '%s\n' memcpy memmove memset strlen strcmp strncmp strchr strrchr strncat strpbrk \
    setjmp _setjmp longjmp sin cos atan atan2 exp log pow sqrt fabs floor ceil round trunc modf \
    trilog_format_float trilog_parse_float >"$BATS_TEST_TMPDIR/allowed"
  run bash -c "nm -u '$lib' | awk '{print \$2}' | sort -u | grep -vxF -f '$BATS_TEST_TMPDIR/allowed'"
  [ -z "$output" ] || { echo "unexpected: $output"; false; }
  run cc -std=c11 -Wall -Wextra -I"$root/include" "$root/test/api/api_freestanding_test.c" "$lib" -lm \
    -o "$BATS_TEST_TMPDIR/api_freestanding_test"
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/api_freestanding_test"
  [ "$status" -eq 0 ]
  [[ "$output" != *"not ok"* ]]
}

@test "floats print without trailing zeros even when the embedder's %g keeps them, as pico-sdk printf does (regression)" {
  root="$BATS_TEST_DIRNAME/../.."
  run make -s -C "$root" PLATFORM=freestanding release
  [ "$status" -eq 0 ]
  run cc -std=c11 -I"$root/include" "$root/test/api/api_freestanding_test.c" \
    "$root/_build/release-no_posix-nolibc/libtrilog.a" -lm -o "$BATS_TEST_TMPDIR/api_freestanding_test"
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/api_freestanding_test"
  [[ "$output" == *$'\nok - strcmp(answer, "[0.25, 5.0, 1.5e+10, 0.333333, -0.5, 100.0]") == 0'* ]]
  [[ "$output" == *$'\nok - strcmp(answer, "1500.0") == 0'* ]]
}

@test "loading boot/core.pl and lib/ at startup produces no uncaught exceptions (regression)" {
  run "$TRILOG" -f -e "true."
  [ "$status" -eq 0 ]
  [[ "$output" != *"existence_error"* ]]
  [[ "$output" != *"uncaught exception"* ]]
}

@test "the engine keeps no writable global state" {
  root="$BATS_TEST_DIRNAME/../.."
  for f in "$root"/src/kernel/*.c "$root"/src/io/*.c "$root"/src/trilog.c "$root"/src/platform/*.c; do
    gcc -std=c11 -O2 -I"$root/include" -I"$root/src/kernel" -I"$root/src/io" -I"$root/src/platform" -I"$root/_build" \
      -c "$f" -o "$BATS_TEST_TMPDIR/obj.o"
    run bash -c "size -A '$BATS_TEST_TMPDIR/obj.o' | awk '\$1 ~ /^\\.(data|bss|data\\.rel|data\\.rel\\.local)\$/ && \$2 > 0'"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "$f: $output"; false; }
  done
}

@test "the library exports only the trilog_ API" {
  run make -s -C "$BATS_TEST_DIRNAME/../.." lib
  [ "$status" -eq 0 ]
  run bash -c "nm -g --defined-only '$BATS_TEST_DIRNAME/../../_build/dev-posix/libtrilog.a' | awk '\$2 ~ /[TDBR]/ {print \$3}' | grep -v '^trilog_'"
  [ -z "$output" ]
}

@test "make OPAQUE=0 exports the engine's internal symbols too" {
  run make -s -C "$BATS_TEST_DIRNAME/../.." OPAQUE=0 lib
  [ "$status" -eq 0 ]
  run bash -c "nm -g --defined-only '$BATS_TEST_DIRNAME/../../_build/dev-posix-open/libtrilog.a' | awk '\$2 ~ /T/ {print \$3}'"
  [[ "$output" == *"unify"* ]]
  [[ "$output" == *"heap_alloc"* ]]
  [[ "$output" == *"trilog_new"* ]]
}

@test "trilog.h compiles and links as C++" {
  command -v g++ >/dev/null || skip "no g++"
  root="$BATS_TEST_DIRNAME/../.."
  printf '#include "trilog.h"\nint main() { return trilog_version()[0] == 0; }\n' > "$BATS_TEST_TMPDIR/host.cpp"
  run g++ -std=c++17 -Wall -Wextra -pedantic -Werror -I"$root/include" -o "$BATS_TEST_TMPDIR/host" \
    "$BATS_TEST_TMPDIR/host.cpp" "$root/_build/dev-posix/libtrilog.a" -lm
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/host"
  [ "$status" -eq 0 ]
}

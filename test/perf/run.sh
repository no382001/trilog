#!/bin/sh
# usage: test/perf/run.sh [TRILOG]   (default: _build/trilog, a release build)
# FLAGS (default -f -n) is passed before each program; -n loads only the core.
# One Markdown table row per workload: the median task-clock, user-space
# instructions and peak RSS over the runs. Needs perf and a C compiler.
set -eu
T=${1:-_build/trilog}
F=${FLAGS:--f -n}
D=$(dirname "$0")
P=_build/perf-peak
mkdir -p _build
${CC:-cc} -O2 -o "$P" "$D/peak.c"

median() { sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'; }

bench() {
  name=$1 runs=$2; shift 2
  "$@" >/dev/null
  out=$(mktemp)
  i=0
  while [ "$i" -lt "$runs" ]; do
    # Not inside the pipeline: that would run it beside the timed run.
    kb=$("$P" "$@")
    perf stat -x, -e task-clock,instructions:u "$@" 2>&1 >/dev/null |
      awk -F, -v kb="$kb" '/task-clock/ { ms = $1 } /instructions/ { ins = $1 } END { print ms, ins, kb }' >>"$out"
    i=$((i + 1))
  done
  ms=$(cut -d' ' -f1 "$out" | median)
  ins=$(cut -d' ' -f2 "$out" | median)
  kb=$(cut -d' ' -f3 "$out" | median)
  rm -f "$out"
  awk -v n="$name" -v ms="$ms" -v ins="$ins" -v kb="$kb" \
    'BEGIN { printf "| %s | %.1f ms, %.1fM ins, %.1f MB |\n", n, ms, ins / 1e6, kb / 1024 }'
}

bench "start and exit" 63 "$T" $F -e true
bench "naive reverse, 300 elements" 7 "$T" $F "$D/nrev.pl" -e main
bench "8 queens, all solutions" 7 "$T" $F "$D/queens.pl" -e main
bench "fib(21)" 7 "$T" $F "$D/fib.pl" -e main
bench "build 20,000 atoms" 7 "$T" $F "$D/atoms.pl" -e main
bench "conformity table, every entry" 7 "$T" $F "$D/conformity.pl" -e main

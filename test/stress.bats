#!/usr/bin/env bats

TRILOG="./trilog"
STATS_FILE="/tmp/trilog_stress_stats"

setup() {
  rm -f /tmp/trilog_stress_*
  # measure baseline (just core.pl loaded, no user clauses)
  echo 'true.' | "$TRILOG" -s 2>/tmp/trilog_stress_baseline >/dev/null
  BASE_CLAUSES=$(grep "^clauses=" /tmp/trilog_stress_baseline | cut -d= -f2)
  export BASE_CLAUSES
}

teardown() {
  rm -f /tmp/trilog_stress_*
}

# helper: extract a stat value from the -s stderr output
stat_val() {
  grep "^${1}=" "$STATS_FILE" | head -1 | cut -d= -f2
}

# --- large findall ---

# template chain-walk is O(n^2) for a var threaded through recursion.
@test "stress: findall 500 integers" {
  echo 'findall(X, between(1,500,X), L), length(L, N), write(N).' \
    | timeout 10 "$TRILOG" -s 2>"$STATS_FILE" | grep -q '500'
  # temp-only query: perm and clauses unchanged from baseline
  [ "$(stat_val clauses)" -eq "$BASE_CLAUSES" ]
}

# regression: findall/setof used to block LCO for the whole nested solve.
@test "stress: findall wrapping a deep backtrack stays fast" {
  result=$(echo 'findall(S, (between(1,3000,X), X =:= 3000, atom_number(S,X)), L), length(L, N), write(N), nl.' \
    | timeout 5 "$TRILOG" -s 2>"$STATS_FILE")
  [ "$(echo "$result" | head -1)" = "1" ]
  [ "$(stat_val clauses)" -eq "$BASE_CLAUSES" ]
}

# --- sort 200 reversed integers ---

@test "stress: sort 200 elements" {
  echo 'findall(X, between(1,200,X), L), reverse(L, R), sort(R, S), length(S, N), write(N).' \
    | timeout 10 "$TRILOG" -s 2>"$STATS_FILE" | grep -q '200'
  # temp-only: no perm growth
  [ "$(stat_val clauses)" -eq "$BASE_CLAUSES" ]
}

# --- 500 dynamic asserts + query ---

@test "stress: 500 asserts then findall" {
  python3 -c "
for i in range(500):
    print(f'assert(item({i})).')
print('findall(X, item(X), L), length(L, N), write(N).')
" | timeout 15 "$TRILOG" -s 2>"$STATS_FILE" > /tmp/trilog_stress_assert.txt
  result=$(tail -1 /tmp/trilog_stress_assert.txt)
  [[ "$result" == *"500"* ]]
  # 500 asserts grow perm and clauses
  [ "$(stat_val clauses)" -eq $(( BASE_CLAUSES + 500 )) ]
}

# --- assert + retractall + re-assert ---

@test "stress: retractall clears, re-assert repopulates" {
  result=$(python3 -c "
for i in range(100):
    print(f'assert(st({i})).')
print('findall(X, st(X), L1), length(L1, N1), write(N1), write(s), nl.')
print('retractall(st(_)).')
print('findall(X, st(X), L2), length(L2, N2), write(N2), write(s), nl.')
for i in range(100):
    print(f'assert(st({i+1000})).')
print('findall(X, st(X), L3), length(L3, N3), write(N3), write(s), nl.')
" | timeout 10 "$TRILOG" -s 2>"$STATS_FILE" | grep -oP '\d+s')
  [ "$(echo "$result" | sed -n 1p)" = "100s" ]
  [ "$(echo "$result" | sed -n 2p)" = "0s" ]
  [ "$(echo "$result" | sed -n 3p)" = "100s" ]
  # final state: baseline + 100 re-asserted
  [ "$(stat_val clauses)" -eq $(( BASE_CLAUSES + 100 )) ]
}

# --- many backtracking solutions ---

@test "stress: 200 backtracking solutions in pipe" {
  count=$(echo 'between(1,200,X), write(X), write(s), nl, fail ; true.' \
    | timeout 10 "$TRILOG" -s 2>"$STATS_FILE" | grep -c 's$')
  [ "$count" -eq 200 ]
  # backtracking is temp-only
  [ "$(stat_val clauses)" -eq "$BASE_CLAUSES" ]
}

# --- large file I/O ---

@test "stress: write and read back 500 lines via Prolog I/O" {
  echo "open('/tmp/trilog_stress_io.txt', write, S), forall(between(1,500,I), (write(S, line(I)), nl(S))), close(S)." \
    | timeout 10 "$TRILOG" -s 2>"$STATS_FILE" >/dev/null
  lines=$(wc -l < /tmp/trilog_stress_io.txt)
  [ "$lines" -eq 500 ]
  head -1 /tmp/trilog_stress_io.txt | grep -q "line(1)"
  tail -1 /tmp/trilog_stress_io.txt | grep -q "line(500)"
  # file I/O doesn't grow perm
}

# --- large .pl file consult ---

@test "stress: consult 500-clause file" {
  python3 -c "
for i in range(500):
    print(f'data({i}).')
" > /tmp/trilog_stress_big.pl
  result=$(printf "consult('/tmp/trilog_stress_big.pl').\nfindall(X, data(X), L), length(L, N), write(N).\n" \
    | timeout 10 "$TRILOG" -s 2>"$STATS_FILE" | tail -1)
  [[ "$result" == *"500"* ]]
  # 500 consulted clauses: perm grows, clauses = baseline + 500
  [ "$(stat_val clauses)" -eq $(( BASE_CLAUSES + 500 )) ]
}

# --- repeated assert/retract churn ---

@test "stress: 10 rounds of assert 50 + retractall" {
  result=$(python3 -c "
for r in range(10):
    for i in range(50):
        print(f'assert(churn({r}_{i})).')
    print('retractall(churn(_)).')
for i in range(50):
    print(f'assert(churn(final_{i})).')
print('findall(X, churn(X), L), length(L, N), write(N).')
" | timeout 15 "$TRILOG" -s 2>"$STATS_FILE" | tail -1)
  [[ "$result" == *"50"* ]]
  # after 10 rounds of retractall, only baseline + 50 final remain
  [ "$(stat_val clauses)" -eq $(( BASE_CLAUSES + 50 )) ]
}

# --- long atom concat chain ---

@test "stress: chained atom_concat builds long atom" {
  result=$(echo "atom_concat(aaaaaaaaaa, bbbbbbbbbb, A), atom_concat(A, cccccccccc, B), atom_concat(B, dddddddddd, C), atom_length(C, N), write(N)." \
    | timeout 5 "$TRILOG" -s 2>"$STATS_FILE")
  [[ "$result" == "40"* ]]
  # temp-only: perm unchanged, term pool used for intermediates
}

# --- foldl over large list ---

@test "stress: foldl sum of 1..500" {
  echo 'add(X, S0, S) :- S is S0 + X.' > /tmp/trilog_stress_fold.pl
  result=$(printf "consult('/tmp/trilog_stress_fold.pl').\nfindall(X, between(1,500,X), L), foldl(add, L, 0, Sum), write(Sum).\n" \
    | timeout 10 "$TRILOG" -s 2>"$STATS_FILE" | tail -1)
  # sum 1..500 = 125250
  [[ "$result" == *"125250"* ]]
  # one extra clause (add/3)
  [ "$(stat_val clauses)" -eq $(( BASE_CLAUSES + 1 )) ]
}

# --- maplist over large list ---

@test "stress: maplist over 200-element list" {
  echo 'inc(X, Y) :- Y is X + 1.' > /tmp/trilog_stress_map.pl
  result=$(printf "consult('/tmp/trilog_stress_map.pl').\nfindall(X, between(1,200,X), L), maplist(inc, L, M), length(M, N), write(N).\n" \
    | timeout 10 "$TRILOG" -s 2>"$STATS_FILE" | tail -1)
  [[ "$result" == *"200"* ]]
  # one extra clause (inc/2)
  [ "$(stat_val clauses)" -eq $(( BASE_CLAUSES + 1 )) ]
}

# --- deep setof dedup ---

@test "stress: setof deduplicates 500 items with repeats" {
  result=$(python3 -c "
for i in range(500):
    v = i % 100
    print(f'assert(ddup({v})).')
print('setof(X, ddup(X), S), length(S, N), write(N).')
" | timeout 15 "$TRILOG" -s 2>"$STATS_FILE" | tail -1)
  [[ "$result" == *"100"* ]]
  # 500 asserts but only 100 unique values — still 500 clauses in db
  [ "$(stat_val clauses)" -eq $(( BASE_CLAUSES + 500 )) ]
}

# --- exhausting resources fails the query, doesn't crash the process ---

@test "stress: length(L, 200000) fails cleanly, does not crash" {
  run timeout 15 "$TRILOG" -e "length(L, 200000), write(done), nl."
  [ "$status" -eq 0 ]
  [[ "$output" != *"AddressSanitizer"* ]]
  [[ "$output" != *"Segmentation"* ]]
}

@test "stress: deep non-tail recursion fails cleanly, does not crash" {
  cat > /tmp/trilog_stress_nontail.pl <<'EOF'
count([], 0).
count([_|T], N) :- count(T, N0), N is N0 + 1.
EOF
  run timeout 15 "$TRILOG" -e "consult('/tmp/trilog_stress_nontail.pl'), length(L, 10000), count(L, N), write(N), nl."
  [ "$status" -eq 0 ]
  [[ "$output" != *"AddressSanitizer"* ]]
  [[ "$output" != *"Segmentation"* ]]
}

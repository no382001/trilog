#!/usr/bin/env bats

TRILOG="./trilog"

setup() {
  rm -f /tmp/trilog_ledit_*.txt /tmp/trilog_ledit_*.pl
}

teardown() {
  rm -f /tmp/trilog_ledit_*.txt /tmp/trilog_ledit_*.pl
}

# --- add lines + save ---

@test "ledit: add lines and save to file" {
  printf "consult('lib/ledit.pl').\nledit.\na\nhello\nworld\n.\nw\ns /tmp/trilog_ledit_out.txt\nq\n" \
    | timeout 5 "$TRILOG" >/dev/null 2>&1
  [ -f /tmp/trilog_ledit_out.txt ]
  run cat /tmp/trilog_ledit_out.txt
  [[ "$output" == *"hello"* ]]
  [[ "$output" == *"world"* ]]
}

# --- load + delete + save ---

@test "ledit: load file, delete line, save" {
  printf "first\nsecond\nthird\n" > /tmp/trilog_ledit_src.txt
  printf "consult('lib/ledit.pl').\nledit('/tmp/trilog_ledit_src.txt').\nf\nd\ns /tmp/trilog_ledit_out.txt\nq\n" \
    | timeout 5 "$TRILOG" >/dev/null 2>&1
  result=$(cat /tmp/trilog_ledit_out.txt)
  [[ "$result" == *"second"* ]]
  [[ "$result" == *"third"* ]]
  [[ "$result" != *"first"* ]]
}

# --- forward + backward navigation ---

@test "ledit: navigate forward and backward" {
  printf "a\nb\nc\n" > /tmp/trilog_ledit_src.txt
  result=$(printf "consult('lib/ledit.pl').\nledit('/tmp/trilog_ledit_src.txt').\nf 3\nb 2\np\nq\n" \
    | timeout 5 "$TRILOG" 2>&1)
  # after f3 we're at c, b2 takes us to a, p shows next line = b
  [[ "$result" == *"LED>"* ]]
}

# --- ledit creates prolog code that trilog runs ---

@test "ledit: generate .pl file, consult and query it" {
  printf "consult('lib/ledit.pl').\nledit.\na\nfruit(apple).\nfruit(banana).\nfruit(cherry).\n.\nw\ns /tmp/trilog_ledit_gen.pl\nq\nconsult('/tmp/trilog_ledit_gen.pl').\nfindall(X, fruit(X), L), write(L).\n" \
    | timeout 5 "$TRILOG" 2>&1 | tail -1 > /tmp/trilog_ledit_result.txt
  result=$(cat /tmp/trilog_ledit_result.txt)
  [[ "$result" == *"apple"* ]]
  [[ "$result" == *"banana"* ]]
  [[ "$result" == *"cherry"* ]]
}

# --- edit .pl file and re-consult ---

@test "ledit: edit .pl file, consult reflects edits" {
  printf "pet(cat).\npet(dog).\npet(snake).\n" > /tmp/trilog_ledit_pets.pl
  # use ledit to remove first line (cat), save to new file, then consult it
  result=$(printf "consult('lib/ledit.pl').\nledit('/tmp/trilog_ledit_pets.pl').\nf\nd\ns /tmp/trilog_ledit_edited.pl\nq\nconsult('/tmp/trilog_ledit_edited.pl').\nfindall(X, pet(X), L), write(L).\n" \
    | timeout 5 "$TRILOG" 2>&1 | tail -1)
  [[ "$result" == *"[dog, snake]"* ]]
}

# --- wind + rewind ---

@test "ledit: wind to end, rewind to top" {
  printf "line1\nline2\nline3\n" > /tmp/trilog_ledit_src.txt
  result=$(printf "consult('lib/ledit.pl').\nledit('/tmp/trilog_ledit_src.txt').\nw\np\nr\nf\np\nq\n" \
    | timeout 5 "$TRILOG" 2>&1)
  # wind goes to end (line3), p would try to advance past end
  # rewind goes back to top, f+p shows line1
  [[ "$result" == *"line3"* ]]
  [[ "$result" == *"line1"* ]]
}

# --- save preserves all lines ---

@test "ledit: load and save preserves content" {
  printf "alpha\nbeta\ngamma\ndelta\n" > /tmp/trilog_ledit_src.txt
  printf "consult('lib/ledit.pl').\nledit('/tmp/trilog_ledit_src.txt').\ns /tmp/trilog_ledit_copy.txt\nq\n" \
    | timeout 5 "$TRILOG" >/dev/null 2>&1
  run diff /tmp/trilog_ledit_src.txt /tmp/trilog_ledit_copy.txt
  [ "$status" -eq 0 ]
}

# --- ledit edits file, make/0 reloads it ---

@test "ledit: add clause via ledit, make reloads it" {
  printf "pet(cat).\npet(dog).\n" > /tmp/trilog_ledit_make.pl
  touch -t 202001010000 /tmp/trilog_ledit_make.pl
  result=$(printf "consult('/tmp/trilog_ledit_make.pl').\nconsult('lib/ledit.pl').\nledit('/tmp/trilog_ledit_make.pl').\nw\na\npet(fish).\n.\nw\ns /tmp/trilog_ledit_make.pl\nq\nmake.\nfindall(X, pet(X), L), write(L).\n" \
    | timeout 5 "$TRILOG" 2>&1 | tail -1)
  [[ "$result" == *"[cat, dog, fish]"* ]]
}

@test "ledit: delete clause via ledit, make reloads without it" {
  printf "color(red).\ncolor(green).\ncolor(blue).\n" > /tmp/trilog_ledit_make.pl
  touch -t 202001010000 /tmp/trilog_ledit_make.pl
  result=$(printf "consult('/tmp/trilog_ledit_make.pl').\nconsult('lib/ledit.pl').\nledit('/tmp/trilog_ledit_make.pl').\nf\nd\ns /tmp/trilog_ledit_make.pl\nq\nmake.\nfindall(X, color(X), L), write(L).\n" \
    | timeout 5 "$TRILOG" 2>&1 | tail -1)
  [[ "$result" == *"[green, blue]"* ]]
}

# --- unconsult ledit then query core predicates ---

@test "ledit: full lifecycle then core still works" {
  result=$(printf "consult('lib/ledit.pl').\nledit.\na\ntest line\n.\nw\ns /tmp/trilog_ledit_out.txt\nq\nunconsult('lib/ledit.pl').\nappend([1,2],[3],X), write(X).\n" \
    | timeout 5 "$TRILOG" 2>&1)
  [[ "$result" == *"[1, 2, 3]"* ]]
}

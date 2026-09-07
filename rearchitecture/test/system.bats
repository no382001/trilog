#!/usr/bin/env bats

TRILOG="./trilog"

# --- exit code contract ---

@test "exit 0 on successful query" {
  run "$TRILOG" -e "true."
  [ "$status" -eq 0 ]
}

@test "exit 0 on failed query (query failure is not process error)" {
  run "$TRILOG" -e "fail."
  [ "$status" -eq 0 ]
}

@test "exit 1 on parse error" {
  run "$TRILOG" -e "garbage@@."
  [ "$status" -eq 1 ]
}

@test "nonexistent file exits nonzero" {
  run "$TRILOG" nonexistent_file.pl -e "true."
  [ "$status" -ne 0 ]
}

# --- file loading + querying ---

@test "file arg loads clauses and -e can query them" {
  run "$TRILOG" test/family.pl -e "grandparent(tom, W)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"W=ann"* ]]
}

@test "arithmetic via is/2" {
  run "$TRILOG" test/family.pl -e "double(21, R)."
  [[ "$output" == *"R=42"* ]]
}

# --- backtracking and cut: the core of the ABC loop ---

@test "backtracking enumerates every solution" {
  run "$TRILOG" test/family.pl -e "choice(W)."
  [[ "$output" == *"W=a"* ]]
  [[ "$output" == *"W=b"* ]]
  [[ "$output" == *"W=c"* ]]
}

@test "cut prunes remaining choice points" {
  run "$TRILOG" test/family.pl -e "first_choice(W)."
  [ "$(echo "$output" | grep -c 'yes:')" -eq 1 ]
  [[ "$output" == *"W=a"* ]]
}

@test "cut is scoped to its own clause across a nested call (regression)" {
  # solving q between the call and '!' must not clobber the barrier and
  # let p(2) leak through.
  run "$TRILOG" test/family.pl -e "p(X)."
  [ "$(echo "$output" | grep -c 'yes:')" -eq 1 ]
  [[ "$output" == *"X=1"* ]]
  [[ "$output" != *"X=2"* ]]
}

@test "cut inside recursion only prunes its own call" {
  run "$TRILOG" test/family.pl -e "first_gt3([1,3,4,5,6], X)."
  [ "$(echo "$output" | grep -c 'yes:')" -eq 1 ]
  [[ "$output" == *"X=4"* ]]
}

# --- boot/core.pl control constructs, built from cut + meta-call ---

@test "disjunction tries both branches on backtrack" {
  run "$TRILOG" test/family.pl -e "(choice(W) ; W=none)."
  [[ "$output" == *"W=a"* ]]
  [[ "$output" == *"W=none"* ]]
}

@test "if-then commits to the condition's first solution only" {
  # Exactly one solution: Else must be unreachable once Cond succeeds
  # (regression: ';'/2's own cut used to miss this).
  run "$TRILOG" test/family.pl -e "(choice(W) -> true ; true)."
  [ "$(echo "$output" | grep -c 'yes:')" -eq 1 ]
  [[ "$output" == *"W=a"* ]]
}

@test "if-then-else takes the else branch on condition failure" {
  run "$TRILOG" test/family.pl -e "(fail -> W=yes ; W=no)."
  [[ "$output" == *"W=no"* ]]
}

@test "negation as failure" {
  run "$TRILOG" test/family.pl -e "(\\+ parent(ann,tom), W=ok)."
  [[ "$output" == *"W=ok"* ]]
}

@test "once commits to the first solution" {
  run "$TRILOG" test/family.pl -e "once(choice(W))."
  [ "$(echo "$output" | grep -c 'yes:')" -eq 1 ]
  [[ "$output" == *"W=a"* ]]
}

# --- raw I/O ---

@test "raw byte I/O via put_code" {
  run "$TRILOG" -e "put_code(72), put_code(105)."
  [[ "$output" == *"Hi"* ]]
}

# --- type checks, term inspection, atom/number <-> codes, compare/3 ---
# The small C primitives boot/*.pl's library builds on.

@test "type checks distinguish var/atom/number/compound" {
  run "$TRILOG" -e "var(X), nonvar(foo), atom(foo), \\+ atom(1), number(1), number(1.5), \\+ number(foo), integer(1), \\+ integer(1.5), compound(foo(1)), \\+ compound(foo), callable(foo), callable(foo(1)), \\+ callable(1)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"yes:"* ]]
}

@test "extended arithmetic: mod, abs, min, max" {
  run "$TRILOG" -e "X is 7 mod 3, Y is -7 mod 3, Z is abs(-5), W is min(3,7), V is max(3,7)."
  [[ "$output" == *"X=1"* ]]
  [[ "$output" == *"Y=2"* ]]
  [[ "$output" == *"Z=5"* ]]
  [[ "$output" == *"W=3"* ]]
  [[ "$output" == *"V=7"* ]]
}

@test "unevaluable arithmetic fails the goal instead of crashing the process (regression)" {
  # eval_arith used to exit(1) on anything unevaluable instead of just
  # failing the goal.
  run "$TRILOG" -e "X is Y."
  [ "$status" -eq 0 ]
  [[ "$output" != *"yes:"* ]]

  run "$TRILOG" -e "X < Y."
  [ "$status" -eq 0 ]
  [[ "$output" != *"yes:"* ]]

  run "$TRILOG" -e "X is 1/0."
  [ "$status" -eq 0 ]
  [[ "$output" != *"yes:"* ]]

  run "$TRILOG" -e "X is 5 mod 0."
  [ "$status" -eq 0 ]
  [[ "$output" != *"yes:"* ]]

  run "$TRILOG" -e "X is foo(1,2)."
  [ "$status" -eq 0 ]
  [[ "$output" != *"yes:"* ]]

  # ordinary arithmetic is unaffected
  run "$TRILOG" -e "X is 1 + 2 * 3, Y is X mod 5."
  [[ "$output" == *"X=7"* ]]
  [[ "$output" == *"Y=2"* ]]
}

@test "functor/3 decomposes and constructs both ways" {
  run "$TRILOG" -e "functor(foo(a,b,c), N, A), functor(T, foo, 3)."
  [[ "$output" == *"N=foo"* ]]
  [[ "$output" == *"A=3"* ]]
  [[ "$output" == *"T=foo("* ]]
}

@test "arg/3 extracts a 1-indexed argument" {
  run "$TRILOG" -e "arg(2, foo(a,b,c), X)."
  [[ "$output" == *"X=b"* ]]
}

@test "univ =.. decomposes and constructs both ways" {
  run "$TRILOG" -e "foo(a,b,c) =.. L, T =.. [foo,a,b,c]."
  [[ "$output" == *"L=[foo,a,b,c]"* ]]
  [[ "$output" == *"T=foo(a,b,c)"* ]]
}

@test "compare/3 gives standard order of terms" {
  run "$TRILOG" -e "compare(O1, 1, 2), compare(O2, foo, abc), compare(O3, foo(1), foo(1))."
  [[ "$output" == *"O1=<"* ]]
  [[ "$output" == *"O2=>"* ]]
  [[ "$output" == *'O3=='* ]]
}

@test "atom_codes, char_code, and number_codes round-trip both ways" {
  run "$TRILOG" -e "atom_codes(hi, L1), atom_codes(A, [104,105]), char_code(a, C), char_code(Ch, 97), number_codes(42, L2), number_codes(N, [52,50])."
  [[ "$output" == *"L1=[104,105]"* ]]
  [[ "$output" == *"A=hi"* ]]
  [[ "$output" == *"C=97"* ]]
  [[ "$output" == *"Ch=a"* ]]
  [[ "$output" == *"L2=[52,50]"* ]]
  [[ "$output" == *"N=42"* ]]
}

# --- boot/core.pl library ---

@test "term-order comparisons: ==, \\==, @<, @>, @=<, @>=, \\=" {
  run "$TRILOG" -e "1 == 1, 1 \\== 2, 1 @< 2, 2 @> 1, 1 @=< 1, 1 @>= 1, \\+ (1 == 2), 1 \\= 2, \\+ (1 \\= 1)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"yes:"* ]]
}

@test "if-then-else makes the else branch unreachable once cond succeeds (regression)" {
  # regression: max_list/2 (built on ->/;) used to produce multiple
  # "maximum" values instead of one.
  run "$TRILOG" -e "findall(M, max_list([3,1,4,1,5], M), L)."
  [[ "$output" == *"L=[5]"* ]]
}

@test "append, member, memberchk, reverse, length" {
  run "$TRILOG" -e "append([1,2],[3,4],L1), append(X,[3,4],[1,2,3,4]), member(2,[1,2,3]), \\+ member(5,[1,2,3]), memberchk(2,[1,2,2,3]), reverse([1,2,3],R), length([a,b,c],N), length(L2,3)."
  [[ "$output" == *"L1=[1,2,3,4]"* ]]
  [[ "$output" == *"X=[1,2]"* ]]
  [[ "$output" == *"R=[3,2,1]"* ]]
  [[ "$output" == *"N=3"* ]]
}

@test "nth0, nth1, last, is_list, sum_list, max_list, min_list, numlist" {
  run "$TRILOG" -e "nth0(1,[a,b,c],X1), nth1(1,[a,b,c],X2), last([1,2,3],X3), is_list([1,2,3]), \\+ is_list([1|foo]), sum_list([1,2,3,4],S), max_list([3,1,4,1,5],Mx), min_list([3,1,4,1,5],Mn), numlist(1,5,NL)."
  [[ "$output" == *"X1=b"* ]]
  [[ "$output" == *"X2=a"* ]]
  [[ "$output" == *"X3=3"* ]]
  [[ "$output" == *"S=10"* ]]
  [[ "$output" == *"Mx=5"* ]]
  [[ "$output" == *"Mn=1"* ]]
  [[ "$output" == *"NL=[1,2,3,4,5]"* ]]
}

@test "between enumerates and checks, forall, succ, plus" {
  run "$TRILOG" -e "findall(X, between(1,5,X), L), between(1,5,3), \\+ between(1,5,9), forall(member(Y,[1,2,3]),Y>0), succ(3,S1), succ(S2,4), plus(2,3,P)."
  [[ "$output" == *"L=[1,2,3,4,5]"* ]]
  [[ "$output" == *"S1=4"* ]]
  [[ "$output" == *"S2=3"* ]]
  [[ "$output" == *"P=5"* ]]
}

@test "call/2,3,4 dispatch through univ, including partial application" {
  run "$TRILOG" -e "call(=,1,1), call(is,X,1+2), maplist(plus(10),[1,2,3],L)."
  [[ "$output" == *"X=3"* ]]
  [[ "$output" == *"L=[11,12,13]"* ]]
}

@test "maplist/2,3,4, foldl, include, exclude, partition" {
  run "$TRILOG" test/family.pl -e "maplist(integer,[1,2,3]), \\+ maplist(integer,[1,foo,3]), maplist(succ,[1,2,3],L1), foldl(plus,[1,2,3,4],0,S), include(integer,[1,foo,2,bar,3],L2), exclude(integer,[1,foo,2,bar,3],L3), partition(integer,[1,foo,2,bar,3],Inc,Exc)."
  [[ "$output" == *"L1=[2,3,4]"* ]]
  [[ "$output" == *"S=10"* ]]
  [[ "$output" == *"L2=[1,2,3]"* ]]
  [[ "$output" == *"L3=[foo,bar]"* ]]
  [[ "$output" == *"Inc=[1,2,3]"* ]]
  [[ "$output" == *"Exc=[foo,bar]"* ]]
}

@test "sort dedups and orders, msort keeps duplicates" {
  run "$TRILOG" -e "sort([3,1,4,1,5,9,2,6], L1), msort([3,1,4,1,5,9,2,6], L2)."
  [[ "$output" == *"L1=[1,2,3,4,5,6,9]"* ]]
  [[ "$output" == *"L2=[1,1,2,3,4,5,6,9]"* ]]
}

# --- first-argument indexing ---

@test "indexing finds the right clause on a bound first argument" {
  run "$TRILOG" test/family.pl -e "item(three, X)."
  [[ "$output" == *"X=3"* ]]
}

@test "indexing does not break backtracking (regression)" {
  # regression: a stale binding from the clause that just failed used to
  # wrongly rule out every other clause by index.
  run "$TRILOG" test/family.pl -e "choice(W)."
  [[ "$output" == *"W=a"* ]]
  [[ "$output" == *"W=b"* ]]
  [[ "$output" == *"W=c"* ]]
}

@test "indexing proves determinism across predicates, not just within one (regression)" {
  # regression: the index key used to omit predicate identity, so
  # unrelated clauses looked like matches and choice points never freed.
  run env TRILOG_GC_THRESHOLD=200 timeout 10 "$TRILOG" test/family.pl -e "count(50000)."
  [ "$status" -eq 0 ]
}

# --- catch/3, throw/1 ---
# Implemented natively: an active-catch scope threaded through frame_t.

@test "catch/3 catches a matching thrown ball" {
  run "$TRILOG" -e "catch(throw(oops), oops, W=caught)."
  [[ "$output" == *"W=caught"* ]]
}

@test "catch/3 unifies structured balls" {
  run "$TRILOG" -e "catch(throw(err(1,foo)), err(N,X), true)."
  [[ "$output" == *"N=1"* ]]
  [[ "$output" == *"X=foo"* ]]
}

@test "non-matching catcher re-throws to the next outer catch/3" {
  run "$TRILOG" -e "catch(catch(throw(a), b, W=inner), a, W=outer)."
  [[ "$output" == *"W=outer"* ]]
}

@test "uncaught exception is reported, not a crash" {
  run "$TRILOG" -e "throw(oops)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"oops"* ]]
}

@test "catch/3 is transparent to a goal that just succeeds or fails" {
  run "$TRILOG" -e "catch(fail, _, true)."
  [ "$status" -eq 0 ]
  [[ "$output" != *"yes:"* ]]
}

@test "backtracking into Goal through catch/3 finds every solution (regression)" {
  # opt(a) succeeds first, so opt(b)'s later throw needs the catch scope
  # to survive independently of any one attempt.
  run "$TRILOG" test/family.pl -e "catch(opt(W), bad_b, W=recovered)."
  [[ "$output" == *"W=a"* ]]
  [[ "$output" == *"W=recovered"* ]]
}

@test "catch/3 under GC pressure stays correct (regression)" {
  # Correctness under GC pressure, with catch_stack entries as live
  # roots marked/translated/compacted every pass.
  run env TRILOG_GC_THRESHOLD=200 timeout 15 "$TRILOG" test/family.pl -e "catch(count(20000), _, true)."
  [ "$status" -eq 0 ]
}

# --- a foundational solve-loop bug, found while building findall/3 ---

@test "true as a non-final goal does not terminate the query early (regression)" {
  # regression: reaching true as the first pending goal used to end the
  # query, even with real goals still queued after it.
  run "$TRILOG" -e "(true, X=ok), Y=X."
  [[ "$output" == *"X=ok"* ]]
  [[ "$output" == *"Y=ok"* ]]
}

# --- findall/3, via assert-based accumulation ---

@test "findall/3 collects every solution in order" {
  run "$TRILOG" test/family.pl -e "findall(X, choice(X), L)."
  [[ "$output" == *"L=[a,b,c]"* ]]
}

@test "findall/3 gives an empty list, not failure, for no solutions" {
  run "$TRILOG" test/family.pl -e "findall(X, choice(nonexistent), L)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"L=[]"* ]]
}

@test "findall/3 applies the template, not just the goal's bindings" {
  run "$TRILOG" test/family.pl -e "findall(Y, (choice(X), Y = pair(X,X)), L)."
  [[ "$output" == *"L=[pair(a,a),pair(b,b),pair(c,c)]"* ]]
}

@test "nested findall/3 does not conflate inner and outer items (regression)" {
  # regression: unqualified '$findall_item' facts let a nested findall sweep up an outer call's leftover items; fixed via a unique id per call.
  run "$TRILOG" test/family.pl -e "findall(Outer, (choice(_), findall(Inner, inner_choice(Inner), Outer)), L)."
  [[ "$output" == *"L=[[a,b,c],[a,b,c],[a,b,c]]"* ]]
}

# --- assertz/1, asserta/1, retract/1 ---

@test "assertz/1 adds a fact, queryable immediately" {
  run "$TRILOG" -e "assertz(dyn_fact(1)), assertz(dyn_fact(2)), dyn_fact(X)."
  [[ "$output" == *"X=1"* ]]
  [[ "$output" == *"X=2"* ]]
}

@test "asserta/1 prepends rather than appends" {
  run "$TRILOG" -e "assertz(dyn_order(z)), asserta(dyn_order(a)), dyn_order(X)."
  [[ "$output" == *"X=a"* ]]
  [[ "$output" == *"X=z"* ]]
}

@test "assertz/1 stores a rule, not just a fact" {
  run "$TRILOG" -e "assertz((dyn_double(X,Y) :- Y is X*2)), dyn_double(21,R)."
  [[ "$output" == *"R=42"* ]]
}

@test "retract/1 removes exactly the matching clause" {
  run "$TRILOG" -e "assertz(dyn_r(1)), assertz(dyn_r(2)), retract(dyn_r(1)), dyn_r(X)."
  [[ "$output" == *"X=2"* ]]
  [[ "$output" != *"X=1"* ]]
}

@test "retract/1 fails, not errors, when nothing matches" {
  run "$TRILOG" -e "retract(dyn_nonexistent(1))."
  [ "$status" -eq 0 ]
  [[ "$output" != *"yes:"* ]]
}

# --- GC: mark-and-slide with pointer reversal ---
# Both regressions below only show up under a forced low threshold.

@test "GC does not corrupt correctness under a forced low threshold" {
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/family.pl -e "grandparent(tom, W)."
  [[ "$output" == *"W=ann"* ]]
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/family.pl -e "p(X)."
  [ "$(echo "$output" | grep -c 'yes:')" -eq 1 ]
  [[ "$output" == *"X=1"* ]]
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/family.pl -e "(choice(W) ; W=none)."
  [[ "$output" == *"W=a"* ]]
  [[ "$output" == *"W=none"* ]]
}

@test "a binding made before a still-live choice point survives GC and backtracking out of it (regression)" {
  # regression: gc_maybe_run built trail_new_index AFTER compact_trail() had already mutated trail[], wrongly unbinding a still-live variable.
  run env TRILOG_GC_THRESHOLD=100 timeout 10 "$TRILOG" -e "numlist(1,20,L), length(L,N)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"L=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]"* ]]
  [[ "$output" == *"N=20"* ]]
}

@test "cut-discarded garbage is reclaimed, not just accumulated (regression)" {
  # regression: each iteration used to permanently retain one more cell
  # than the last, making GC passes progressively more expensive.
  run env TRILOG_GC_THRESHOLD=200 timeout 10 "$TRILOG" test/family.pl -e "loop(20000)."
  [ "$status" -eq 0 ]
}

@test "deep list survives a full mark pass without stack overflow (regression)" {
  # regression: print_term used to recurse once per list element and
  # segfault well before this length.
  run timeout 10 "$TRILOG" test/family.pl -e "count_list(50000, L), list_len(L, N)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"N=50000"* ]]
}

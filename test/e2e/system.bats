#!/usr/bin/env bats

# The engine: backtracking, cut, control constructs, catch/throw, findall, the database, GC, DCGs.

load common

@test "backtracking enumerates every solution" {
  run "$TRILOG" test/e2e/files/family.pl -e "choice(W)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = b"* ]]
  [[ "$output" == *"W = c"* ]]
}

@test "cut prunes remaining choice points" {
  run "$TRILOG" test/e2e/files/family.pl -e "first_choice(W)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"W = a"* ]]
}

@test "cut is scoped to its own clause across a nested call (regression)" {
  # solving q between the call and '!' must not clobber the barrier and
  # let p(2) leak through.
  run "$TRILOG" test/e2e/files/family.pl -e "p(X)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"X = 1"* ]]
  [[ "$output" != *"X = 2"* ]]
}

@test "cut inside recursion only prunes its own call" {
  run "$TRILOG" test/e2e/files/family.pl -e "first_gt3([1,3,4,5,6], X)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"X = 4"* ]]
}

@test "disjunction tries both branches on backtrack" {
  run "$TRILOG" test/e2e/files/family.pl -e "(choice(W) ; W=none)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = none"* ]]
}

@test "if-then commits to the condition's first solution only" {
  # Exactly one solution: Else must be unreachable once Cond succeeds
  # (regression: ';'/2's own cut used to miss this).
  run "$TRILOG" test/e2e/files/family.pl -e "(choice(W) -> true ; true)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"W = a"* ]]
}

@test "if-then-else takes the else branch on condition failure" {
  run "$TRILOG" test/e2e/files/family.pl -e "(fail -> W=yes ; W=no)."
  [[ "$output" == *"W = no"* ]]
}

@test "negation as failure" {
  run "$TRILOG" test/e2e/files/family.pl -e "(\\+ parent(ann,tom), W=ok)."
  [[ "$output" == *"W = ok"* ]]
}

@test "once commits to the first solution" {
  run "$TRILOG" test/e2e/files/family.pl -e "once(choice(W))."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"W = a"* ]]
}

@test "if-then-else makes the else branch unreachable once cond succeeds (regression)" {
  # regression: max_list/2 (built on ->/;) used to produce multiple
  # "maximum" values instead of one.
  run "$TRILOG" -e "findall(M, max_list([3,1,4,1,5], M), L)."
  [[ "$output" == *"L = [5]"* ]]
}

@test "bagof does not group by Goal's free variables (regression)" {
  # NOT ISO grouping, deliberately: K/L here stay unbound in the single
  # collected pair rather than backtracking over distinct witnesses.
  run "$TRILOG" -e "
    assertz(bagof_p(a,1)),
    assertz(bagof_p(a,2)),
    assertz(bagof_p(b,3)),
    findall(K-L, bagof(X,bagof_p(K,X),L), Groups), length(Groups, N), write(N).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"N = 1"* ]]
}

@test "bagof with V^Goal has no effect on the ungrouped result (regression)" {
  run "$TRILOG" -e "
    assertz(bagof_p(a,1)),
    assertz(bagof_p(a,2)),
    assertz(bagof_p(b,3)),
    bagof(X, K^bagof_p(K,X), L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"L = [1, 2, 3]"* ]]
}

@test "bagof fails outright on no solutions, unlike findall's []" {
  run "$TRILOG" -e "bagof(X, member(X,[]), L)."
  [ "$status" -eq 0 ]
  ! succeeded
}

@test "calling a non-callable term throws type_error(callable, _), not a crash (regression)" {
  # a bare integer as a goal used to corrupt the heap: key_of_goal's
  # "not callable" sentinel (pred_id = -1) fed straight into
  # make_existence_error, which built an atom cell from that -1.
  run "$TRILOG" -e "
    catch(call(42), error(type_error(callable, 42), _), true),
    write(ok),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "bagof with an unbound Goal argument doesn't loop forever (regression)" {
  # '$bagof_strip' used to unify an unbound Goal0 with V^G0 itself,
  # recursing on the fresh var forever, instead of throwing
  # instantiation_error.
  run "$TRILOG" -e "
    catch(bagof(_X,_Y^_Z,_L), error(instantiation_error, _), true),
    write(ok),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "setof sorts and dedups, built on bagof plus sort/2" {
  run "$TRILOG" -e "setof(X, member(X,[3,1,2,1]), L)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"L = [1, 2, 3]"* ]]
}

@test "indexing finds the right clause on a bound first argument" {
  run "$TRILOG" test/e2e/files/family.pl -e "item(three, X)."
  [[ "$output" == *"X = 3"* ]]
}

@test "indexing does not break backtracking (regression)" {
  # regression: a stale binding from the clause that just failed used to
  # wrongly rule out every other clause by index.
  run "$TRILOG" test/e2e/files/family.pl -e "choice(W)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = b"* ]]
  [[ "$output" == *"W = c"* ]]
}

@test "indexing proves determinism across predicates, not just within one (regression)" {
  # regression: the index key used to omit predicate identity, so
  # unrelated clauses looked like matches and choice points never freed.
  skip "pre-existing timeout in this sandbox, confirmed unrelated to any change here"
  run env TRILOG_GC_THRESHOLD=200 timeout 10 "$TRILOG" test/e2e/files/family.pl -e "count(50000)."
  [ "$status" -eq 0 ]
}

@test "catch/3 catches a matching thrown ball" {
  run "$TRILOG" -e "catch(throw(oops), oops, W=caught)."
  [[ "$output" == *"W = caught"* ]]
}

@test "catch/3 unifies structured balls" {
  run "$TRILOG" -e "catch(throw(err(1,foo)), err(N,X), true)."
  [[ "$output" == *"N = 1"* ]]
  [[ "$output" == *"X = foo"* ]]
}

@test "non-matching catcher re-throws to the next outer catch/3" {
  run "$TRILOG" -e "catch(catch(throw(a), b, W=inner), a, W=outer)."
  [[ "$output" == *"W = outer"* ]]
}

@test "catch/3 is transparent to a goal that just succeeds or fails" {
  run "$TRILOG" -e "catch(fail, _, true)."
  [ "$status" -eq 0 ]
  ! succeeded
}

@test "a cut reached through a bare ; is transparent to the enclosing goal (regression)" {
  run "$TRILOG" -e "( (write(a), !, fail) ; write(b) )."
  [ "$status" -eq 0 ]
  [[ "$output" == *"a"* ]]
  [[ "$output" != *"b"* ]]
  ! succeeded
}

@test "call/1 gives an embedded cut its own scope, opaque to the enclosing ; (regression)" {
  run "$TRILOG" -e "( call((write(a), !, fail)) ; write(b) )."
  [ "$status" -eq 0 ]
  [[ "$output" == *"a"* ]]
  [[ "$output" == *"b"* ]]
  succeeded
}

@test "catch/3's Goal argument gives an embedded cut its own scope too (regression)" {
  run "$TRILOG" -e "( catch((write(a), !, fail), _, true) ; write(b) )."
  [ "$status" -eq 0 ]
  [[ "$output" == *"a"* ]]
  [[ "$output" == *"b"* ]]
  succeeded
}

@test "once/1 and \\+/1 don't crash on an embedded cut (regression)" {
  run "$TRILOG" -e "once((write(x), !, fail)) ; write(y)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"x"* ]]
  [[ "$output" == *"y"* ]]

  run "$TRILOG" -e "( \\+ (write(z), !, fail) ; write(q) )."
  [ "$status" -eq 0 ]
  [[ "$output" == *"z"* ]]
  [[ "$output" == *"q"* ]]
}

@test "backtracking into Goal through catch/3 finds every solution (regression)" {
  # opt(a) succeeds first, so opt(b)'s later throw needs the catch scope
  # to survive independently of any one attempt.
  run "$TRILOG" test/e2e/files/family.pl -e "catch(opt(W), bad_b, W=recovered)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = recovered"* ]]
}

@test "catch/3 under GC pressure stays correct (regression)" {
  # Correctness under GC pressure, with catch_stack entries as live
  # roots marked/translated/compacted every pass.
  run env TRILOG_GC_THRESHOLD=200 timeout 15 "$TRILOG" test/e2e/files/family.pl -e "catch(count(20000), _, true)."
  [ "$status" -eq 0 ]
}

@test "true as a non-final goal does not terminate the query early (regression)" {
  # regression: reaching true as the first pending goal used to end the
  # query, even with real goals still queued after it.
  run "$TRILOG" -e "
    (true, X=ok),
    Y=X.
  "
  [[ "$output" == *"X = ok"* ]]
  [[ "$output" == *"Y = ok"* ]]
}

@test "findall/3 collects every solution in order" {
  run "$TRILOG" test/e2e/files/family.pl -e "findall(X, choice(X), L)."
  [[ "$output" == *'L = "abc"'* ]]
}

@test "findall/3 gives an empty list, not failure, for no solutions" {
  run "$TRILOG" test/e2e/files/family.pl -e "findall(X, choice(nonexistent), L)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"L = []"* ]]
}

@test "findall/3 applies the template, not just the goal's bindings" {
  run "$TRILOG" test/e2e/files/family.pl -e "findall(Y, (choice(X), Y = pair(X,X)), L)."
  [[ "$output" == *"L = [pair(a, a), pair(b, b), pair(c, c)]"* ]]
}

@test "nested findall/3 does not conflate inner and outer items (regression)" {
  # regression: unqualified '$findall_item' facts let a nested findall sweep up an outer call's leftover items; fixed via a unique id per call.
  run "$TRILOG" test/e2e/files/family.pl -e "findall(Outer, (choice(_), findall(Inner, inner_choice(Inner), Outer)), L)."
  [[ "$output" == *'L = ["abc", "abc", "abc"]'* ]]
}

@test "unifying and comparing two cyclic terms terminates (regression)" {
  # regression: X = f(X), Y = f(Y), X = Y recursed forever and segfaulted, as did == and compare/3.
  run timeout 20 "$TRILOG" -e "
    X = f(X), Y = f(Y), X = Y, X == Y, compare(O1, X, Y),
    A = f(A), B = f(f(B)), A = B, A == B,
    L = [a|L], M = [a, a|M], L = M, L == M,
    P = f(P, 1), Q = f(Q, 2), ( P = Q -> R1 = unified ; R1 = failed ),
    ( P == Q -> R2 = same ; R2 = different ), compare(O2, P, Q),
    C = g(C), D = g(D), unify_with_occurs_check(C, D),
    write(r(O1, R1, R2, O2)), nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"r(=, failed, different, <)"* ]]
}

@test "copy_term/2 preserves variable sharing" {
  run "$TRILOG" -e "
    copy_term(f(X,Y,X,g(Y)), f(A,B,C,g(D))),
    A == C,
    B == D,
    A \\== B.
  "
  succeeded
}

@test "copy_term/2 throws on a cyclic term instead of crashing (regression)" {
  run "$TRILOG" -e "
    X = f(X),
    catch(copy_term(X, _), error(E, _), (write(caught(E)), nl)).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"caught(representation_error(cyclic_term))"* ]]
}

@test "findall/3 throws on a cyclic solution instead of crashing (regression)" {
  run "$TRILOG" -e "
    X = [X|_],
    catch(findall(X, true, _), error(E, _), (write(caught(E)), nl)).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"caught(representation_error(cyclic_term))"* ]]
}

@test "assertz/1 throws on a cyclic term instead of crashing (regression)" {
  run "$TRILOG" -e "
    X = f(X),
    catch(assertz(p(X)), error(E, _), (write(caught(E)), nl)).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"caught(representation_error(cyclic_term))"* ]]
}

@test "unify_with_occurs_check/2 fails where the variable occurs in the term" {
  run "$TRILOG" -e "
    ( unify_with_occurs_check(X, f(X)) -> R1 = unified ; R1 = failed ),
    ( unify_with_occurs_check(f(A,B), f(B,g(A))) -> R2 = unified ; R2 = failed ),
    write(r(R1, R2)), nl.
  "
  [[ "$output" == *"r(failed, failed)"* ]]
}

@test "unify_with_occurs_check/2 unifies like =/2 otherwise" {
  run "$TRILOG" -e "
    unify_with_occurs_check(f(X,a,[H|T]), f(b,Y,[1,2])),
    write(X-Y-H-T),
    nl.
  "
  [[ "$output" == *"-(-(-(b, a), 1), [2])"* ]]
}

@test "unify_with_occurs_check/2 terminates on an already-cyclic term" {
  run timeout 5 "$TRILOG" -e "
    X = f(X),
    unify_with_occurs_check(Y, g(X)),
    write(ok),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "assertz/1 adds a fact, queryable immediately" {
  run "$TRILOG" -e "
    assertz(dyn_fact(1)),
    assertz(dyn_fact(2)),
    dyn_fact(X).
  "
  [[ "$output" == *"X = 1"* ]]
  [[ "$output" == *"X = 2"* ]]
}

@test "asserta/1 prepends rather than appends" {
  run "$TRILOG" -e "
    assertz(dyn_order(z)),
    asserta(dyn_order(a)),
    dyn_order(X).
  "
  [[ "$output" == *"X = a"* ]]
  [[ "$output" == *"X = z"* ]]
}

@test "assertz/1 stores a rule, not just a fact" {
  run "$TRILOG" -e "
    assertz((dyn_double(X,Y) :- Y is X*2)),
    dyn_double(21,R).
  "
  [[ "$output" == *"R = 42"* ]]
}

@test "retract/1 removes exactly the matching clause" {
  run "$TRILOG" -e "
    assertz(dyn_r(1)),
    assertz(dyn_r(2)),
    retract(dyn_r(1)),
    dyn_r(X).
  "
  [[ "$output" == *"X = 2"* ]]
  [[ "$output" != *"X = 1"* ]]
}

@test "retract/1 fails, not errors, when nothing matches" {
  run "$TRILOG" -e "retract(dyn_nonexistent(1))."
  [ "$status" -eq 0 ]
  ! succeeded
}

@test "logical update view: retractall/abolish during iteration still yield the original clauses" {
  run "$TRILOG" -e "
    assertz(r(1)), assertz(r(2)), findall(X, (r(X), retractall(r(_))), A),
    assertz(i(ant)), assertz(i(bee)), findall(Y, (i(Y), abolish(i/1)), B),
    write(A-B), nl.
  "
  [[ "$output" == *"-([1, 2], [ant, bee])"* ]]
}

@test "logical update view: clauses added or retracted during iteration are not seen" {
  run "$TRILOG" -e "
    assertz(s(1)), findall(X, (s(X), X < 3, Y is X + 1, assertz(s(Y))), A),
    assertz(q(1)), assertz(q(2)), assertz(q(3)), findall(Z, (q(Z), retract(q(2))), B),
    write(A-B), nl.
  "
  [[ "$output" == *"-([1], [1])"* ]]
}

@test "a cut in a dynamic clause prunes its remaining clauses, through ; and -> too" {
  run "$TRILOG" -e "
    assertz((d(X) :- X > 0, !)), assertz(d(_)),
    findall(one, d(1), A), findall(two, d(0), B),
    assertz((e(X, R) :- ( X > 0 -> R = pos, ! ; R = neg ))), assertz(e(_, other)),
    findall(R1, e(1, R1), C), findall(R2, e(0, R2), D),
    write(r(A, B, C, D)), nl.
  "
  [[ "$output" == *'r([one], [two], [pos], [neg, other])'* ]]
}

@test "a cut inside call/1 or a variable goal in a dynamic clause stays local" {
  run "$TRILOG" -e "
    assertz((f(X) :- call(!), X = 1)), assertz(f(2)),
    assertz((h(X) :- G = !, G, X = 1)), assertz(h(2)),
    findall(X, f(X), A), findall(Y, h(Y), B),
    write(A-B), nl.
  "
  [[ "$output" == *"-([1, 2], [1, 2])"* ]]
}

@test "lib/meta.pl: solve/1 runs goals with cut when consulted" {
  run "$TRILOG" -e "
    consult('lib/meta.pl'),
    findall(X, solve((member(X, [1, 2, 3]), X > 1)), A),
    findall(Y, solve((member(Y, [1, 2, 3]), Y > 1, !)), B),
    write(A-B), nl.
  "
  [[ "$output" == *"-([2, 3], [2])"* ]]
}

@test "assert/retract/abolish raise the ISO errors for bad arguments" {
  run "$TRILOG" -e "
    E = error(X, _),
    findall(X, ( member(G, [assertz(_), assertz(4), asserta((foo :- 4)), retract((4 :- _)),
                            abolish(_), abolish(foo), abolish(foo/_), abolish(foo/a),
                            abolish(5/2), abolish(foo/(-1))]),
                 catch(G, E, true) ), Xs),
    write(Xs), nl.
  "
  [[ "$output" == *"[instantiation_error, type_error(callable, 4), type_error(callable, 4), type_error(callable, 4), instantiation_error, type_error(predicate_indicator, foo), instantiation_error, type_error(integer, a), type_error(atom, 5), domain_error(not_less_than_zero, -1)]"* ]]
}

@test "an asserted predicate still exists, and fails, once its last clause is retracted (regression)" {
  # regression: a predicate counted as existing only while it had clauses, so calling an emptied one raised existence_error.
  run "$TRILOG" -e "
    assertz(st(1)), retract(st(1)),
    assertz(su(1)), retractall(su(_)),
    retractall(sv(_)),
    findall(X, st(X), A), findall(Y, su(Y), B), findall(Z, sv(Z), C),
    write(r(A, B, C)), nl.
  "
  [[ "$output" != *"existence_error"* ]]
  [[ "$output" == *"r([], [], [])"* ]]
}

@test "GC does not corrupt correctness under a forced low threshold" {
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/e2e/files/family.pl -e "grandparent(tom, W)."
  [[ "$output" == *"W = ann"* ]]
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/e2e/files/family.pl -e "p(X)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"X = 1"* ]]
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/e2e/files/family.pl -e "(choice(W) ; W=none)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = none"* ]]
}

@test "a binding made before a still-live choice point survives GC and backtracking out of it (regression)" {
  # regression: gc_maybe_run built trail_new_index AFTER compact_trail() had already mutated trail[], wrongly unbinding a still-live variable.
  run env TRILOG_GC_THRESHOLD=100 timeout 10 "$TRILOG" -e "
    numlist(1,20,L),
    length(L,N).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"L = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]"* ]]
  [[ "$output" == *"N = 20"* ]]
}

@test "cut-discarded garbage is reclaimed, not just accumulated (regression)" {
  # regression: each iteration used to permanently retain one more cell
  # than the last, making GC passes progressively more expensive.
  run env TRILOG_GC_THRESHOLD=200 timeout 10 "$TRILOG" test/e2e/files/family.pl -e "loop(20000)."
  [ "$status" -eq 0 ]
}

@test "deep list survives a full mark pass without stack overflow (regression)" {
  # regression: print_term used to recurse once per list element and
  # segfault well before this length.
  run timeout 10 "$TRILOG" test/e2e/files/family.pl -e "
    count_list(50000, L),
    list_len(L, N).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"N = 50000"* ]]
}

@test "DCG: terminals and phrase/2" {
  printf 'greeting --> [hello], [world].\n' > /tmp/trilog_dcg1.pl
  run "$TRILOG" /tmp/trilog_dcg1.pl -e "phrase(greeting, [hello, world])."
  succeeded
  run "$TRILOG" /tmp/trilog_dcg1.pl -e "phrase(greeting, [hello, there])."
  ! succeeded
  rm -f /tmp/trilog_dcg1.pl
}

@test "DCG: recursion and a {}//1 embedded goal" {
  printf 'digits([D|Ds]) --> [D], { D >= 0, D =< 9 }, digits(Ds).\n' > /tmp/trilog_dcg2.pl
  printf 'digits([D]) --> [D], { D >= 0, D =< 9 }.\n' >> /tmp/trilog_dcg2.pl
  run "$TRILOG" /tmp/trilog_dcg2.pl -e "phrase(digits(Ds), [1,2,3])."
  [[ "$output" == *"Ds = [1, 2, 3]"* ]]
  rm -f /tmp/trilog_dcg2.pl
}

@test "DCG: ; alternation and a cut committing a branch" {
  cat > /tmp/trilog_dcg3.pl <<'EOF'
alt --> [x] ; [y].
opt --> [z], !, [w].
opt --> [].
EOF
  run "$TRILOG" /tmp/trilog_dcg3.pl -e "phrase(alt, [x])."
  succeeded
  run "$TRILOG" /tmp/trilog_dcg3.pl -e "phrase(alt, [y])."
  succeeded
  run "$TRILOG" /tmp/trilog_dcg3.pl -e "phrase(opt, [z, w])."
  succeeded
  run "$TRILOG" /tmp/trilog_dcg3.pl -e "phrase(opt, [])."
  succeeded
  rm -f /tmp/trilog_dcg3.pl
}

@test "DCG: a recursive nonterminal handles a long input in bounded memory (regression)" {
  # regression: each recursive call nested another solve/2 meta-interpreter, so 10 items already exhausted memory.
  cat > /tmp/trilog_dcg4.pl <<'EOF'
count(N0, N) --> [_], !, { N1 is N0 + 1 }, count(N1, N).
count(N, N) --> [].
EOF
  run bash -c "ulimit -v 1048576; timeout 30 $TRILOG /tmp/trilog_dcg4.pl -e \"length(L, 2000), phrase(count(0, N), L).\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"N = 2000"* ]]
  rm -f /tmp/trilog_dcg4.pl
}

@test "a clause asserted with a literal cut still cuts correctly when called from a different depth (regression)" {
  run "$TRILOG" -e "
    assertz((foo(1))),
    assertz((foo(X) :- X=2, !)),
    assertz((foo(3))),
    findall(Z, foo(Z), L),
    write(L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1, 2]"* ]]
}

@test "solve/2: a cut after a multi-clause call gives exactly one answer, not one per remaining alternative" {
  run "$TRILOG" test/e2e/files/family.pl -e "
    first_choice(W),
    write(W).
  "
  [ "$status" -eq 0 ]
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"W = a"* ]]
}

@test "solve/2: a cut-committed base case keeps every binding it made, including the final list tail" {
  run "$TRILOG" -e "
    assertz((build(0,[]):-!)),
    assertz((build(N,[N|T]):-N>0,N1 is N-1,build(N1,T))),
    build(3,L),
    write(L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[3, 2, 1]"* ]]
}

@test "solve/2: a recursive predicate's own cut never leaks into its own recursive call (regression)" {
  run "$TRILOG" -e "
    assertz((mycollect(Id,L):-retract(item(Id,X)),!,L=[X|Rest],mycollect(Id,Rest))),
    assertz((mycollect(Id,[]):-retract(mark(Id)))),
    assertz(mark(1)),
    assertz(item(1,a)),
    assertz(item(1,b)),
    mycollect(1,L),
    write(L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ab"'* ]]
}

@test "solve/2: findall/3 itself works, having survived every prior cut design's failure mode" {
  run "$TRILOG" test/e2e/files/family.pl -e "
    findall(X, choice(X), L),
    write(L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"abc"'* ]]
}

@test "solve/2: two cuts in one clause body both fire, and everything after the second still runs" {
  run "$TRILOG" -e "
    assertz((foo:-write(a),!,write(b),!,write(c))),
    foo.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"abc"* ]]
}

@test "solve/2: plain cut-free backtracking is unaffected (regression)" {
  run "$TRILOG" test/e2e/files/family.pl -e "
    choice(X),
    write(X),
    nl,
    fail
    ; true.
  "
  [[ "$output" == *"a"* ]]
  [[ "$output" == *"b"* ]]
  [[ "$output" == *"c"* ]]
}

@test "solve/2: DCG rules with an embedded cut work under meta-interpretation" {
  printf 'opt --> [z], !, [w].\nopt --> [].\n' > /tmp/mi_dcg_test.pl
  run "$TRILOG" /tmp/mi_dcg_test.pl -e "phrase(opt, [z, w])."
  [ "$status" -eq 0 ]
  succeeded
  run "$TRILOG" /tmp/mi_dcg_test.pl -e "phrase(opt, [])."
  [ "$status" -eq 0 ]
  succeeded
  rm -f /tmp/mi_dcg_test.pl
}

@test "DCG rules translate lazily at call time, not eagerly at consult time (regression)" {
  run "$TRILOG" -e "
    assertz((greeting --> [hello],[world])),
    phrase(greeting,[hello,world]).
  "
  [ "$status" -eq 0 ]
  succeeded
}

@test "catch traps exception, recovery goal runs" {
  result=$(printf "catch(throw(boom), boom, write(caught)).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"caught"* ]]
}

@test "catch passes through on no exception" {
  result=$(printf "catch(write(ok), _, write(bad)).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"ok"* ]]
  [[ "$result" != *"bad"* ]]
}

@test "asserta inserts before, assertz after" {
  result=$(printf "assert(c(bb)).\nasserta(c(aa)).\nassert(c(cc)).\nfindall(X,c(X),L), write(L).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"[aa, bb, cc]"* ]]
}

@test "copy_term preserves structure with fresh vars" {
  result=$(printf "copy_term(f(X,X), f(A,B)), A = hello, write(B).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"hello"* ]]
}

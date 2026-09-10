% mi standard library. '$$name' = raw kernel primitive; '$name' = private helper.

% --- meta-interpreter ---

%!  solve(+Goal) is nondet.
%   Cut: '$$choice_mark'/'$$cut_to' discard choice points, not the trail.
solve(Goal) :- '$$choice_mark'(Mark), solve(Goal, Mark).

solve(true, _Mark) :- !.
solve((A, B), Mark) :- !, solve(A, Mark), solve(B, Mark).
solve(!, Mark) :- !, '$$cut_to'(Mark).
solve(A, _Mark) :-
    '$$clause_candidates'(A, Cands),
    ( Cands == [] ->
        call(A)
    ; '$$choice_mark'(NewMark),
      member(A - Body, Cands),
      solve(Body, NewMark)
    ).

% --- operators ---

%!  op(+Priority, +Type, +Name) is det.
%   Declares Name as an operator for the parser.
op(Priority, Type, Name) :- '$$assertz'('$$op'(Priority, Type, Name)).

% --- control ---

%!  ;/2, ->/2 is nondet.
%   Disjunction and if-then, including if-then-else.
';'('->'(If, Then), _) :- If, !, Then.
';'('->'(_, _), Else) :- !, Else.
';'(A, _) :- A.
';'(_, B) :- B.

'->'(Cond, Then) :- Cond, !, Then.

%!  call(:Goal), call(:Goal, +A1..+A3) is nondet.
%   call/1: fresh cut scope (native). call/2-4: extend via univ, then call/1.
call(G) :- G.

call(G, A1) :- G =.. L, append(L, [A1], L2), G2 =.. L2, call(G2).
call(G, A1, A2) :- G =.. L, append(L, [A1,A2], L2), G2 =.. L2, call(G2).
call(G, A1, A2, A3) :- G =.. L, append(L, [A1,A2,A3], L2), G2 =.. L2, call(G2).

%!  once(:Goal) is semidet.
once(G) :- call(G), !.

%!  \+(:Goal) is semidet.
'\\+'(G) :- call(G), !, fail.
'\\+'(_).

%!  forall(:Cond, :Action) is semidet.
forall(Cond, Action) :- \+ (Cond, \+ Action).

%!  halt is det.
halt :- halt(0).

%!  [], [+File|+Files] is det.
%   Classic consult shorthand: [foo] == consult(foo); [foo,bar] loads both in order.
[].
[File|Files] :- consult(File), call(Files).

% --- lists ---

%!  append(?List1, ?List2, ?List3) is nondet.
append([], L, L).
append([H|T], L, [H|R]) :- append(T, L, R).

%!  member(?Elem, ?List) is nondet.
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

%!  memberchk(?Elem, ?List) is semidet.
memberchk(X, L) :- member(X, L), !.

%!  length(?List, ?N) is det.
length(L, N) :- nonvar(N), !, '$length_make'(N, L).
length(L, N) :- '$length_count'(L, 0, N).
'$length_make'(0, []) :- !.
'$length_make'(N, [_|T]) :- N > 0, N1 is N - 1, '$length_make'(N1, T).
'$length_count'([], N, N).
'$length_count'([_|T], N0, N) :- N1 is N0 + 1, '$length_count'(T, N1, N).

%!  reverse(?List, ?Reversed) is det.
reverse(L, R) :- '$reverse'(L, [], R).
'$reverse'([], Acc, Acc).
'$reverse'([H|T], Acc, R) :- '$reverse'(T, [H|Acc], R).

%!  is_list(@Term) is semidet.
is_list([]) :- !.
is_list([_|T]) :- is_list(T).

%!  last(+List, ?Last) is semidet.
last([X], X) :- !.
last([_|T], X) :- last(T, X).

%!  nth0(?Index, ?List, ?Elem) is nondet.
nth0(I, L, E) :- integer(I), !, I >= 0, '$nth0_det'(I, L, E).
nth0(I, L, E) :- var(I), '$nth0_gen'(L, E, 0, I).
'$nth0_det'(0, [X|_], X) :- !.
'$nth0_det'(N, [_|T], X) :- N > 0, N1 is N - 1, '$nth0_det'(N1, T, X).
'$nth0_gen'([X|_], X, I, I).
'$nth0_gen'([_|T], X, I0, I) :- I1 is I0 + 1, '$nth0_gen'(T, X, I1, I).

%!  nth1(?Index, ?List, ?Elem) is nondet.
nth1(I, L, E) :- integer(I), !, I >= 1, I0 is I - 1, '$nth0_det'(I0, L, E).
nth1(I, L, E) :- var(I), '$nth0_gen'(L, E, 1, I).

%!  sum_list(+List, -Sum) is det.
sum_list(L, S) :- '$sum_list'(L, 0, S).
'$sum_list'([], S, S).
'$sum_list'([H|T], S0, S) :- S1 is S0 + H, '$sum_list'(T, S1, S).

%!  max_list(+List, -Max) is det.
max_list([H|T], M) :- '$max_list'(T, H, M).
'$max_list'([], M, M).
'$max_list'([H|T], M0, M) :- (H > M0 -> M1 = H ; M1 = M0), '$max_list'(T, M1, M).

%!  min_list(+List, -Min) is det.
min_list([H|T], M) :- '$min_list'(T, H, M).
'$min_list'([], M, M).
'$min_list'([H|T], M0, M) :- (H < M0 -> M1 = H ; M1 = M0), '$min_list'(T, M1, M).

%!  select(?Elem, ?List, ?Rest) is nondet.
select(E, [E|Xs], Xs).
select(E, [X|Xs], [X|Ys]) :- select(E, Xs, Ys).

%!  delete(+List, @Elem, -Result) is det.
delete([], _, []).
delete([X|Xs], Y, Zs) :- \+ X \= Y, !, delete(Xs, Y, Zs).
delete([X|Xs], Y, [X|Zs]) :- delete(Xs, Y, Zs).

%!  subtract(+Set1, +Set2, -Difference) is det.
subtract([], _, []).
subtract([X|Xs], Ys, Zs) :-
    ( memberchk(X, Ys) -> subtract(Xs, Ys, Zs)
    ; Zs = [X|Zs1], subtract(Xs, Ys, Zs1)
    ).

%!  intersection(+Set1, +Set2, -Intersection) is det.
intersection([], _, []).
intersection([X|Xs], Ys, Zs) :-
    ( memberchk(X, Ys) -> Zs = [X|Zs1] ; Zs = Zs1 ),
    intersection(Xs, Ys, Zs1).

%!  union(+Set1, +Set2, -Union) is det.
union([], L, L).
union([X|Xs], Ys, Zs) :-
    ( memberchk(X, Ys) -> union(Xs, Ys, Zs)
    ; Zs = [X|Zs1], union(Xs, Ys, Zs1)
    ).

%!  flatten(+NestedList, -FlatList) is det.
flatten(List, FlatList) :- '$flatten'(List, [], FlatList).
'$flatten'(Var, Tl, [Var|Tl]) :- var(Var), !.
'$flatten'([], Tl, Tl) :- !.
'$flatten'([Hd|Tl], Tail, List) :-
    !, '$flatten'(Hd, FlatHeadTail, List), '$flatten'(Tl, Tail, FlatHeadTail).
'$flatten'(NonList, Tl, [NonList|Tl]).

%!  list_to_set(+List, -Set) is det.
list_to_set(List, Set) :- '$list_to_set'(List, [], Set).
'$list_to_set'([], _, []).
'$list_to_set'([X|Xs], Seen, Set) :-
    ( memberchk(X, Seen) -> '$list_to_set'(Xs, Seen, Set)
    ; Set = [X|Set1], '$list_to_set'(Xs, [X|Seen], Set1)
    ).

%!  max_member(-Max, +List) is semidet.
max_member(Max, [X|Xs]) :- foldl('$max_member', Xs, X, Max).
'$max_member'(X, M0, M) :- ( X @> M0 -> M = X ; M = M0 ).

%!  min_member(-Min, +List) is semidet.
min_member(Min, [X|Xs]) :- foldl('$min_member', Xs, X, Min).
'$min_member'(X, M0, M) :- ( X @< M0 -> M = X ; M = M0 ).

%!  permutation(?List, ?Perm) is nondet.
permutation([], []).
permutation(List, [X|Perm]) :- select(X, List, Rest), permutation(Rest, Perm).

%!  repeat is nondet.
repeat.
repeat :- repeat.

%!  numlist(+Low, +High, -List) is det.
numlist(L, H, []) :- L > H, !.
numlist(L, H, [L|T]) :- L =< H, L1 is L + 1, numlist(L1, H, T).

%!  between(+Low, +High, ?X) is nondet.
between(L, H, X) :- integer(X), !, X >= L, X =< H.
between(L, H, L) :- L =< H.
between(L, H, X) :- L < H, L1 is L + 1, between(L1, H, X).

%!  succ(?X, ?Y) is det.
succ(X, Y) :- integer(X), !, Y is X + 1.
succ(X, Y) :- integer(Y), X is Y - 1.

%!  plus(?A, ?B, ?C) is det.
plus(A, B, C) :- integer(A), integer(B), !, C is A + B.
plus(A, B, C) :- integer(A), integer(C), !, B is C - A.
plus(A, B, C) :- integer(B), integer(C), A is C - B.

% --- term comparison ---
% ==, \==, @<, @>, @=<, @>=, <, >, =<, >=, =:=, =\= are native

%!  compare(-Order, @A, @B) is det.
%   '$$var_addr'/2 gives two unbound variables their own heap cell index.
compare(O, A, B) :-
    '$term_rank'(A, RA),
    '$term_rank'(B, RB),
    ( RA \== RB ->
        ( RA < RB -> O = < ; O = > )
    ; '$compare_same_rank'(RA, A, B, O)
    ).

'$term_rank'(X, 0) :- var(X), !.
'$term_rank'(X, 1) :- number(X), !.
'$term_rank'(X, 2) :- atom(X), !.
'$term_rank'(_, 3).

'$compare_same_rank'(0, A, B, O) :-
    !,
    '$$var_addr'(A, AA),
    '$$var_addr'(B, BA),
    ( AA < BA -> O = < ; AA > BA -> O = > ; O = = ).
'$compare_same_rank'(1, A, B, O) :-
    !,
    ( A < B -> O = < ; A > B -> O = > ; O = = ).
'$compare_same_rank'(2, A, B, O) :-
    !,
    ( A == B ->
        O = =
    ; atom_codes(A, CA), atom_codes(B, CB), '$codes_compare'(CA, CB, O)
    ).
'$compare_same_rank'(3, A, B, O) :-
    functor(A, NA, AA),
    functor(B, NB, BA),
    ( AA \== BA ->
        ( AA < BA -> O = < ; O = > )
    ; NA \== NB ->
        atom_codes(NA, CNA), atom_codes(NB, CNB), '$codes_compare'(CNA, CNB, O)
    ; '$args_compare'(1, AA, A, B, O)
    ).

'$codes_compare'([], [], =) :- !.
'$codes_compare'([], [_ | _], <) :- !.
'$codes_compare'([_ | _], [], >) :- !.
'$codes_compare'([X | Xs], [Y | Ys], O) :-
    ( X < Y -> O = < ; X > Y -> O = > ; '$codes_compare'(Xs, Ys, O) ).

'$args_compare'(I, N, _, _, =) :- I > N, !.
'$args_compare'(I, N, A, B, O) :-
    arg(I, A, AI),
    arg(I, B, BI),
    compare(OI, AI, BI),
    ( OI \== = -> O = OI ; I1 is I + 1, '$args_compare'(I1, N, A, B, O) ).

%!  \=(@A, @B) is semidet.
'\\='(X, Y) :- \+ X = Y.

% --- type checks ---
% var/1, atom/1, integer/1, float/1, compound/1 are native.

%!  nonvar(@Term) is semidet.
nonvar(X) :- \+ var(X).

%!  number(@Term) is semidet.
number(X) :- integer(X).
number(X) :- float(X).

%!  atomic(@Term) is semidet.
atomic(X) :- atom(X).
atomic(X) :- number(X).

%!  callable(@Term) is semidet.
callable(X) :- atom(X).
callable(X) :- compound(X).

%!  boolean(@Term) is semidet.
boolean(true).
boolean(false).

%!  character(@Term) is semidet.
character(C) :- atom(C), atom_length(C, 1).

%!  must_be(+Type, @Term) is det.
%   Throws instead of failing; Type is any unary type-check predicate, dispatched via call/2.
must_be(Type, _) :-
    var(Type),
    !,
    throw(error(instantiation_error, must_be/2)).
must_be(var, Term) :-
    !,
    ( var(Term) -> true ; throw(error(uninstantiation_error(Term), must_be/2)) ).
must_be(list, Term) :- !, '$must_be_list'(Term).
must_be(not_less_than_zero, Term) :-
    !,
    '$must_be_type'(integer, Term),
    ( Term >= 0 -> true ; throw(error(domain_error(not_less_than_zero, Term), must_be/2)) ).
must_be(Type, Term) :- '$must_be_type'(Type, Term).

'$must_be_type'(_, Term) :-
    var(Term),
    !,
    throw(error(instantiation_error, must_be/2)).
'$must_be_type'(Type, Term) :- call(Type, Term), !.
'$must_be_type'(Type, Term) :- throw(error(type_error(Type, Term), must_be/2)).

'$must_be_list'([]) :- !.
'$must_be_list'([_|T]) :- !, '$must_be_list'(T).
'$must_be_list'(Term) :-
    ( var(Term) -> throw(error(instantiation_error, must_be/2))
    ; throw(error(type_error(list, Term), must_be/2))
    ).

%!  can_be(+Type, @Term) is semidet.
%   Like must_be/2, but an unbound Term passes without throwing.
can_be(Type, _) :-
    var(Type),
    !,
    throw(error(instantiation_error, can_be/2)).
can_be(_, Term) :- var(Term), !.
can_be(Type, Term) :- must_be(Type, Term).

% --- higher-order ---

%!  maplist(:Goal, ?List[, ?List2[, ?List3]]) is nondet.
maplist(_, []).
maplist(G, [X|Xs]) :- call(G, X), maplist(G, Xs).

maplist(_, [], []).
maplist(G, [X|Xs], [Y|Ys]) :- call(G, X, Y), maplist(G, Xs, Ys).

maplist(_, [], [], []).
maplist(G, [X|Xs], [Y|Ys], [Z|Zs]) :- call(G, X, Y, Z), maplist(G, Xs, Ys, Zs).

%!  foldl(:Goal, +List, +Acc0, -Acc) is nondet.
foldl(_, [], Acc, Acc).
foldl(G, [X|Xs], Acc0, Acc) :- call(G, X, Acc0, Acc1), foldl(G, Xs, Acc1, Acc).

%!  include(:Goal, +List, -Included) is det.
include(_, [], []).
include(P, [X|Xs], Result) :-
    (call(P, X) -> Result = [X|Rest] ; Result = Rest),
    include(P, Xs, Rest).

%!  exclude(:Goal, +List, -Excluded) is det.
exclude(_, [], []).
exclude(P, [X|Xs], Result) :-
    (call(P, X) -> Result = Rest ; Result = [X|Rest]),
    exclude(P, Xs, Rest).

%!  partition(:Goal, +List, -Included, -Excluded) is det.
partition(_, [], [], []).
partition(P, [X|Xs], Inc, Exc) :-
    (call(P, X) -> Inc = [X|Inc1], Exc = Exc1 ; Inc = Inc1, Exc = [X|Exc1]),
    partition(P, Xs, Inc1, Exc1).

% --- sorting ---
% TODO: O(n^2) insertion sort.

%!  msort(+List, -Sorted) is det.
msort(L, Sorted) :- '$isort'(L, [], Sorted).
'$isort'([], Acc, Acc).
'$isort'([H|T], Acc, Sorted) :- '$insert'(H, Acc, Acc1), '$isort'(T, Acc1, Sorted).
'$insert'(X, [], [X]).
'$insert'(X, [H|T], [X,H|T]) :- X @=< H, !.
'$insert'(X, [H|T], [H|T1]) :- '$insert'(X, T, T1).

%!  sort(+List, -Sorted) is det.
sort(L, Sorted) :- msort(L, M), '$dedup'(M, Sorted).
'$dedup'([], []).
'$dedup'([X], [X]) :- !.
'$dedup'([X,Y|T], R) :- X == Y, !, '$dedup'([Y|T], R).
'$dedup'([X,Y|T], [X|R]) :- '$dedup'([Y|T], R).

% --- database ---

%!  assertz/assert/asserta(+Clause), retract(+Clause).
%   Refuses static (consulted) predicates with ISO permission_error unless declared dynamic/1; '$$'-prefixed primitives are the raw, unprotected versions.
assertz(Clause) :- '$check_static'(Clause), '$$assertz'(Clause).
assert(Clause) :- '$check_static'(Clause), '$$assert'(Clause).
asserta(Clause) :- '$check_static'(Clause), '$$asserta'(Clause).
retract(Clause) :- '$check_static'(Clause), '$$retract'(Clause).

'$check_static'(Clause) :-
    '$clause_head'(Clause, Head),
    functor(Head, Name, Arity),
    ( '$$is_static'(Name, Arity)
    -> throw(error(permission_error(modify, static_procedure, Name/Arity), _))
    ;  true
    ).

'$clause_head'((Head :- _), Head) :- !.
'$clause_head'(Head, Head).

%!  findall(+Template, :Goal, -List) is det.
%   FIXME: Goal throwing leaks this call's mark/items as orphaned facts.
findall(Template, Goal, List) :-
    '$next_id'(Id),
    '$$assertz'('$findall_mark'(Id)),
    (call(Goal), '$$assertz'('$findall_item'(Id, Template)), fail ; true),
    '$findall_collect'(Id, List).

'$next_id'(Id) :- '$$retract'('$id_counter'(N0)), !, Id is N0 + 1, '$$assertz'('$id_counter'(Id)).
'$next_id'(0) :- '$$assertz'('$id_counter'(0)).

'$findall_collect'(Id, List) :-
    '$$retract'('$findall_item'(Id, X)), !,
    List = [X|Rest],
    '$findall_collect'(Id, Rest).
'$findall_collect'(Id, []) :-
    '$$retract'('$findall_mark'(Id)).

%!  clause(?Head, ?Body) is nondet.
clause(Head, Body) :-
    '$$clause_candidates'(Head, Candidates),
    member(Head - Body, Candidates).

%!  term_variables(@Term, -Vars) is det.
%   Vars in first-occurrence order, each exactly once.
term_variables(Term, Vars) :-
    '$term_variables'(Term, [], Vs0),
    reverse(Vs0, Vars).

'$term_variables'(Term, Seen, Vars) :-
    var(Term),
    !,
    ( '$var_memberchk'(Term, Seen) -> Vars = Seen ; Vars = [Term|Seen] ).
'$term_variables'(Term, Seen, Vars) :-
    compound(Term),
    !,
    functor(Term, _, Arity),
    '$term_variables_args'(1, Arity, Term, Seen, Vars).
'$term_variables'(_, Seen, Seen).

'$term_variables_args'(I, N, _, Seen, Seen) :- I > N, !.
'$term_variables_args'(I, N, Term, Seen0, Vars) :-
    arg(I, Term, A),
    '$term_variables'(A, Seen0, Seen1),
    I1 is I + 1,
    '$term_variables_args'(I1, N, Term, Seen1, Vars).

'$var_memberchk'(V, [W|_]) :- V == W, !.
'$var_memberchk'(V, [_|T]) :- '$var_memberchk'(V, T).

'$var_subtract'([], _, []).
'$var_subtract'([V|Vs], Excl, Result) :-
    ( '$var_memberchk'(V, Excl) -> '$var_subtract'(Vs, Excl, Result)
    ; Result = [V|Rest], '$var_subtract'(Vs, Excl, Rest)
    ).

%!  bagof(+Template, :Goal, -Bag) is nondet.
%   Backtracks over one Bag per distinct binding of Goal's free variables
%   (unlike findall/3, fails outright if Goal has no solutions at all).
bagof(Template, Goal0, Bag) :-
    '$bagof_strip'(Goal0, ExVars, Goal),
    term_variables(Goal, GoalVars),
    term_variables(Template, TemplVars),
    '$var_subtract'(GoalVars, TemplVars, FreeVars0),
    '$var_subtract'(FreeVars0, ExVars, FreeVars),
    Witness =.. [w|FreeVars],
    findall(Witness - Template, Goal, Pairs),
    Pairs \= [],
    '$bagof_group'(Pairs, Groups),
    member(Witness - Bag, Groups).

% nonvar first: an unbound Goal0 would otherwise unify with V^G0
% itself (binding fresh vars) and recurse on that fresh var forever.
'$bagof_strip'(Goal0, [V|Vs], G) :-
    nonvar(Goal0),
    Goal0 = V ^ G0,
    !,
    '$bagof_strip'(G0, Vs, G).
'$bagof_strip'(G, [], G).

'$bagof_group'([], []).
'$bagof_group'([W - T|Rest], [W - Bag|Groups]) :-
    '$bagof_partition'(Rest, W, Same, Diff),
    Bag = [T|Same],
    '$bagof_group'(Diff, Groups).

'$bagof_partition'([], _, [], []).
'$bagof_partition'([W1 - T1|Rest], W, [T1|Same], Diff) :-
    W1 == W,
    !,
    '$bagof_partition'(Rest, W, Same, Diff).
'$bagof_partition'([Pair|Rest], W, Same, [Pair|Diff]) :-
    '$bagof_partition'(Rest, W, Same, Diff).

%!  setof(+Template, :Goal, -Set) is nondet.
setof(Template, Goal, Set) :-
    bagof(Template, Goal, Bag),
    sort(Bag, Set).

% --- I/O ---
% put_code/1, get_code/1 are native.

%!  with_output_to(+Sink, :Goal) is semidet.
%   Sink is atom(-A) or codes(-Cs).
with_output_to(atom(A), Goal) :-
    '$$capture_start',
    % must pop the capture level even if Goal throws, or output stays silently swallowed after.
    ( catch(call(Goal), Ball, ('$$capture_stop'(_), throw(Ball)))
    -> '$$capture_stop'(A)
    ;  '$$capture_stop'(_), fail
    ).
with_output_to(codes(Cs), Goal) :- with_output_to(atom(A), Goal), atom_codes(A, Cs).

'$stream_alias'(user_output, 0).
'$stream_alias'(user_error, 1).
'$resolve_stream'(S, N) :- '$stream_alias'(S, N), !.
'$resolve_stream'('$stream'(Id), '$stream'(Id)) :- !.
'$resolve_stream'(S, _) :- throw(error(domain_error(stream_or_alias, S), _)).

%!  write(@Term), write(+Stream, @Term) is det.
%   TODO: no operator-aware output.
write(T) :- '$$write_raw'(0, T, 0).
write(S, T) :-
    '$resolve_stream'(S, N),
    ( '$$write_raw'(N, T, 0) -> true ; throw(error(existence_error(stream, S), write/2)) ).

%!  writeq(@Term) is det.
%!  writeq(+Stream, @Term) is det.
writeq(T) :- '$$write_raw'(0, T, 1).
writeq(S, T) :-
    '$resolve_stream'(S, N),
    ( '$$write_raw'(N, T, 1) -> true ; throw(error(existence_error(stream, S), writeq/2)) ).

%!  nl is det.
%!  nl(+Stream) is det.
nl :- write('\n').
nl(S) :- write(S, '\n').

%!  writeln(@Term) is det.
%!  writeln(+Stream, @Term) is det.
writeln(T) :- write(T), nl.
writeln(S, T) :- write(S, T), nl(S).

%!  char_code(?Char, ?Code) is det.
char_code(Char, Code) :- atom_codes(Char, [Code]).

%!  get_char(-Char) is det.
get_char(Char) :- get_code(C), (C == -1 -> Char = end_of_file ; char_code(Char, C)).

%!  atom_length(+Atom, -Length) is det.
atom_length(A, L) :- atom_codes(A, C), length(C, L).

%!  atom_concat(?Atom1, ?Atom2, ?Atom3) is nondet.
%   Nondet split falls out of append/3's own backtracking.
atom_concat(A, B, C) :-
    nonvar(A),
    nonvar(B),
    !,
    atom_codes(A, CA),
    atom_codes(B, CB),
    append(CA, CB, CC),
    atom_codes(C, CC).
atom_concat(A, B, C) :-
    atom_codes(C, CC),
    append(CA, CB, CC),
    atom_codes(A, CA),
    atom_codes(B, CB).

%!  sub_atom(+Atom, ?Before, ?Length, ?After, ?Sub) is nondet.
sub_atom(Atom, Before, Length, After, Sub) :-
    atom_codes(Atom, Codes),
    append(BC, RestC, Codes),
    length(BC, Before),
    append(SC, AC, RestC),
    length(SC, Length),
    length(AC, After),
    atom_codes(Sub, SC).

%!  atom_chars(?Atom, ?Chars) is det.
atom_chars(A, Chars) :-
    nonvar(A),
    !,
    atom_codes(A, Codes),
    maplist(char_code, Chars, Codes).
atom_chars(A, Chars) :-
    maplist(char_code, Chars, Codes),
    atom_codes(A, Codes).

%!  atom_number(?Atom, ?Number) is semidet.
atom_number(A, N) :-
    nonvar(A),
    !,
    atom_codes(A, C),
    number_codes(N, C).
atom_number(A, N) :-
    number_codes(N, C),
    atom_codes(A, C).

%!  number_chars(?Number, ?Chars) is det.
number_chars(N, Chars) :-
    nonvar(N),
    !,
    number_codes(N, Codes),
    maplist(char_code, Chars, Codes).
number_chars(N, Chars) :-
    maplist(char_code, Chars, Codes),
    number_codes(N, Codes).

%!  retractall(+Head) is det.
%   Fresh copy_term per attempt: retract/1 binds Head on success, so reusing it would re-search for that value, not the pattern.
retractall(Head) :-
    ( copy_term(Head, Fresh), retract(Fresh) -> retractall(Head) ; true ).

%!  abolish(+Name/Arity) is det.
abolish(Name/Arity) :- functor(Head, Name, Arity), retractall(Head).

%!  current_op(?Priority, ?Type, ?Name) is nondet.
%   Just queries '$$op'/3, the same bucket op/3 asserts into.
current_op(P, T, N) :- '$$op'(P, T, N).

% --- DCG ---

:- op(1200, xfx, '-->').

dcg_constr([]).
dcg_constr([_|_]).
dcg_constr((_, _)).
dcg_constr((_ ; _)).
dcg_constr((_ -> _)).
dcg_constr({_}).
dcg_constr(!).
dcg_constr(call(_)).

dcg_body(Var, S0, S, phrase(Var, S0, S)) :- var(Var), !.
dcg_body(GRBody, S0, S, Body) :-
    nonvar(GRBody),
    dcg_constr(GRBody),
    !,
    dcg_cbody(GRBody, S0, S, Body).
dcg_body(NonTerminal, S0, S, phrase(NonTerminal, S0, S)).

dcg_cbody([], S0, S, S0 = S) :- !.
dcg_cbody([T|Ts], S0, S, Goal) :-
    !,
    dcg_terminals([T|Ts], S0, S, Goal).
dcg_cbody((A, B), S0, S, (AT, BT)) :-
    !,
    dcg_body(A, S0, S1, AT),
    dcg_body(B, S1, S, BT).
dcg_cbody((A ; B), S0, S, (AT ; BT)) :-
    !,
    dcg_body(A, S0, S, AT),
    dcg_body(B, S0, S, BT).
dcg_cbody((A -> B), S0, S, (AT -> BT)) :-
    !,
    dcg_body(A, S0, S1, AT),
    dcg_body(B, S1, S, BT).
dcg_cbody({G}, S0, S, (G, S0 = S)) :- !.
dcg_cbody(!, S0, S, (!, S0 = S)) :- !.
dcg_cbody(call(G), S0, S, call(G, S0, S)) :- !.

dcg_terminals(Terminals, S0, S, S0 = List) :-
    append(Terminals, S, List).

%!  phrase(:Body, ?List) is nondet.
%!  phrase(:Body, ?List, ?Rest) is nondet.
phrase(GRBody, S0) :- phrase(GRBody, S0, []).

phrase(GRBody, S0, S) :-
    ( var(GRBody) ->
        throw(error(instantiation_error, phrase/3))
    ; dcg_constr(GRBody) ->
        dcg_body(GRBody, S0, S, Goal), call(Goal)
    ; '$$choice_mark'(Mark),
      '$$clause_candidates'('-->'(GRBody, RawBody), Cands),
      member('-->'(GRBody, RawBody) - true, Cands),
      dcg_body(RawBody, S0, S, Goal),
      solve(Goal, Mark)
    ).

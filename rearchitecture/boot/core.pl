% if-then-else
';'('->'(If, Then), _) :- If, !, Then.
';'('->'(_, _), Else) :- !, Else.
';'(A, _) :- A.
';'(_, B) :- B.

% if-then
'->'(Cond, Then) :- Cond, !, Then.

call(G) :- G.

call(G, A1) :- G =.. L, append(L, [A1], L2), G2 =.. L2, call(G2).
call(G, A1, A2) :- G =.. L, append(L, [A1,A2], L2), G2 =.. L2, call(G2).
call(G, A1, A2, A3) :- G =.. L, append(L, [A1,A2,A3], L2), G2 =.. L2, call(G2).

once(G) :- G, !.

'\\+'(G) :- G, !, fail.
'\\+'(_).

'$next_id'(Id) :- retract('$id_counter'(N0)), !, Id is N0 + 1, assertz('$id_counter'(Id)).
'$next_id'(0) :- assertz('$id_counter'(0)).

% FIXME: Goal throwing leaks this call's mark/items as orphaned facts.
findall(Template, Goal, List) :-
    '$next_id'(Id),
    asserta('$findall_mark'(Id)),
    (call(Goal), assertz('$findall_item'(Id, Template)), fail ; true),
    '$findall_collect'(Id, List).

'$findall_collect'(Id, List) :-
    retract('$findall_item'(Id, X)), !,
    List = [X|Rest],
    '$findall_collect'(Id, Rest).
'$findall_collect'(Id, []) :-
    retract('$findall_mark'(Id)).

% --- term-order comparisons ---

'=='(X, Y) :- compare(=, X, Y).
'\\=='(X, Y) :- \+ compare(=, X, Y).
'@<'(X, Y) :- compare(<, X, Y).
'@>'(X, Y) :- compare(>, X, Y).
'@=<'(X, Y) :- compare(O, X, Y), '$le_order'(O).
'$le_order'(<).
'$le_order'(=).
'@>='(X, Y) :- compare(O, X, Y), '$ge_order'(O).
'$ge_order'(>).
'$ge_order'(=).

'\\='(X, Y) :- \+ X = Y.

% --- lists ---

append([], L, L).
append([H|T], L, [H|R]) :- append(T, L, R).

member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

memberchk(X, L) :- member(X, L), !.

length(L, N) :- nonvar(N), !, '$length_make'(N, L).
length(L, N) :- '$length_count'(L, 0, N).
'$length_make'(0, []) :- !.
'$length_make'(N, [_|T]) :- N > 0, N1 is N - 1, '$length_make'(N1, T).
'$length_count'([], N, N).
'$length_count'([_|T], N0, N) :- N1 is N0 + 1, '$length_count'(T, N1, N).

reverse(L, R) :- '$reverse'(L, [], R).
'$reverse'([], Acc, Acc).
'$reverse'([H|T], Acc, R) :- '$reverse'(T, [H|Acc], R).

is_list([]) :- !.
is_list([_|T]) :- is_list(T).

last([X], X) :- !.
last([_|T], X) :- last(T, X).

nth0(I, L, E) :- integer(I), !, I >= 0, '$nth0_det'(I, L, E).
nth0(I, L, E) :- var(I), '$nth0_gen'(L, E, 0, I).
'$nth0_det'(0, [X|_], X) :- !.
'$nth0_det'(N, [_|T], X) :- N > 0, N1 is N - 1, '$nth0_det'(N1, T, X).
'$nth0_gen'([X|_], X, I, I).
'$nth0_gen'([_|T], X, I0, I) :- I1 is I0 + 1, '$nth0_gen'(T, X, I1, I).

nth1(I, L, E) :- integer(I), !, I >= 1, I0 is I - 1, '$nth0_det'(I0, L, E).
nth1(I, L, E) :- var(I), '$nth0_gen'(L, E, 1, I).

sum_list(L, S) :- '$sum_list'(L, 0, S).
'$sum_list'([], S, S).
'$sum_list'([H|T], S0, S) :- S1 is S0 + H, '$sum_list'(T, S1, S).

max_list([H|T], M) :- '$max_list'(T, H, M).
'$max_list'([], M, M).
'$max_list'([H|T], M0, M) :- (H > M0 -> M1 = H ; M1 = M0), '$max_list'(T, M1, M).

min_list([H|T], M) :- '$min_list'(T, H, M).
'$min_list'([], M, M).
'$min_list'([H|T], M0, M) :- (H < M0 -> M1 = H ; M1 = M0), '$min_list'(T, M1, M).

numlist(L, H, []) :- L > H, !.
numlist(L, H, [L|T]) :- L =< H, L1 is L + 1, numlist(L1, H, T).

between(L, H, X) :- integer(X), !, X >= L, X =< H.
between(L, H, L) :- L =< H.
between(L, H, X) :- L < H, L1 is L + 1, between(L1, H, X).

succ(X, Y) :- integer(X), !, Y is X + 1.
succ(X, Y) :- integer(Y), X is Y - 1.

plus(A, B, C) :- integer(A), integer(B), !, C is A + B.
plus(A, B, C) :- integer(A), integer(C), !, B is C - A.
plus(A, B, C) :- integer(B), integer(C), A is C - B.

forall(Cond, Action) :- \+ (Cond, \+ Action).

% --- higher-order ---

maplist(_, []).
maplist(G, [X|Xs]) :- call(G, X), maplist(G, Xs).

maplist(_, [], []).
maplist(G, [X|Xs], [Y|Ys]) :- call(G, X, Y), maplist(G, Xs, Ys).

maplist(_, [], [], []).
maplist(G, [X|Xs], [Y|Ys], [Z|Zs]) :- call(G, X, Y, Z), maplist(G, Xs, Ys, Zs).

foldl(_, [], Acc, Acc).
foldl(G, [X|Xs], Acc0, Acc) :- call(G, X, Acc0, Acc1), foldl(G, Xs, Acc1, Acc).

include(_, [], []).
include(P, [X|Xs], Result) :-
    (call(P, X) -> Result = [X|Rest] ; Result = Rest),
    include(P, Xs, Rest).

exclude(_, [], []).
exclude(P, [X|Xs], Result) :-
    (call(P, X) -> Result = Rest ; Result = [X|Rest]),
    exclude(P, Xs, Rest).

partition(_, [], [], []).
partition(P, [X|Xs], Inc, Exc) :-
    (call(P, X) -> Inc = [X|Inc1], Exc = Exc1 ; Inc = Inc1, Exc = [X|Exc1]),
    partition(P, Xs, Inc1, Exc1).

% --- sort/2, msort/2, on compare/3 --- insertion sort
% TODO: these are O(n^2)

msort(L, Sorted) :- '$isort'(L, [], Sorted).
'$isort'([], Acc, Acc).
'$isort'([H|T], Acc, Sorted) :- '$insert'(H, Acc, Acc1), '$isort'(T, Acc1, Sorted).
'$insert'(X, [], [X]).
'$insert'(X, [H|T], [X,H|T]) :- compare(O, X, H), '$le_order'(O), !.
'$insert'(X, [H|T], [H|T1]) :- '$insert'(X, T, T1).

sort(L, Sorted) :- msort(L, M), '$dedup'(M, Sorted).
'$dedup'([], []).
'$dedup'([X], [X]) :- !.
'$dedup'([X,Y|T], R) :- compare(=, X, Y), !, '$dedup'([Y|T], R).
'$dedup'([X,Y|T], [X|R]) :- '$dedup'([Y|T], R).

% --- with_output_to/2 ---
% $capture_start/$capture_stop (solve.c) swap the write_str hook for a
% buffer; same known gap as findall - a throw from Goal skips $capture_stop.
with_output_to(atom(A), Goal) :-
    '$capture_start',
    (call(Goal) -> '$capture_stop'(A) ; '$capture_stop'(_), fail).
with_output_to(codes(Cs), Goal) :- with_output_to(atom(A), Goal), atom_codes(A, Cs).

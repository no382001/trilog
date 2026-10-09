
%!  append(?List1, ?List2, ?List3) is nondet.
append([], L, L).
append([H|T], L, [H|R]) :- append(T, L, R).

%!  member(?Elem, ?List) is nondet.
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

%!  memberchk(?Elem, ?List) is semidet.
memberchk(X, L) :- member(X, L), !.

%!  length(?List, ?N) is nondet.
length(L, N) :-
    (   var(N) -> true
    ;   integer(N) ->
        ( N >= 0 -> true ; throw(error(domain_error(not_less_than_zero, N), length/2)) )
    ;   throw(error(type_error(integer, N), length/2))
    ),
    '$$skip_list'(L, K, T),
    (   T == [] -> N = K
    ;   var(T) -> '$length_open'(T, K, N)
    ).
'$length_open'(T, K, N) :-
    (   integer(N) -> M is N - K, M >= 0, '$length_make'(M, T)
    ;   '$length_enum'(T, K, N)
    ).
'$length_make'(0, []) :- !.
'$length_make'(N, [_|T]) :- N1 is N - 1, '$length_make'(N1, T).
'$length_enum'([], N, N).
'$length_enum'([_|T], N0, N) :- N1 is N0 + 1, '$length_enum'(T, N1, N).

%!  reverse(?List, ?Reversed) is det.
reverse(L, R) :- '$reverse'(L, [], R).
'$reverse'([], Acc, Acc).
'$reverse'([H|T], Acc, R) :- '$reverse'(T, [H|Acc], R).

%!  is_list(@Term) is semidet.
is_list(L) :- '$$skip_list'(L, _, T), T == [].

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

%!  numlist(+Low, +High, -List) is det.
numlist(L, H, []) :- L > H, !.
numlist(L, H, [L|T]) :- L =< H, L1 is L + 1, numlist(L1, H, T).

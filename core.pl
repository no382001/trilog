append([], L, L).
append([H|T], L, [H|R]) :- append(T, L, R).

member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

length([], 0).
length([_|T], N) :- length(T, N1), N is N1 + 1.

reverse(L, R) :- reverse(L, [], R).

reverse([], Acc, Acc).
reverse([H|T], Acc, R) :- reverse(T, [H|Acc], R).

last(X, [X]).
last(X, [_|T]) :- last(X, T).

perm([], []).
perm([H|T], P) :- perm(T, PT), insert(H, PT, P).

insert(X, L, [X|L]).
insert(X, [H|T], [H|R]) :- insert(X, T, R).

between(Low, High, Low) :- Low =< High.
between(Low, High, X) :- Low < High, Low1 is Low + 1, between(Low1, High, X).

once(Goal) :- call(Goal), !.

repeat.
repeat :- repeat.

forall_fail(Cond, Action) :- call(Cond), \+ call(Action).
forall(Cond, Action) :- \+ forall_fail(Cond, Action).
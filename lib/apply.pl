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

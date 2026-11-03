:- module(shapes, [area/2, shape//1, bump/0, squares/2, total/2, sq_list/1,
                   words/1, smallest/1, dyn/1, run/1]).

:- use_module(library(lists)).
:- use_module(library(dcgs)).

:- dynamic(counter/1).

area(square(S), A) :- sq(S, A).
area(circle(R), A) :- A is 3 * R * R.

sq(X, Y) :- Y is X * X.

helper(private).

shape(S) --> word(S).

word(square) --> "square".
word(circle) --> "circle".

counter(0).

bump :- retract(counter(N)), N1 is N + 1, assertz(counter(N1)).

twice(G) :- ( G -> true ; false ), \+ \+ G.

checked(A) :- twice(area(square(2), A)).

squares(Xs, Ys) :- maplist(sq, Xs, Ys).

total(Xs, T) :- foldl(add_sq, Xs, 0, T).

add_sq(X, T0, T) :- sq(X, Y), T is T0 + Y.

sq_list(L) :- findall(Y, (member(X, [1, 2, 3]), sq(X, Y)), L).

words(Ws) :- findall(W, phrase(word(W), _), Ws).

smallest(S) :- setof(A-X, R^(member(X-R, [a-2, b-1]), sq(R, A)), [S|_]).

dyn(Y) :- G = sq(3, Y), call(G).

:- meta_predicate(run(0)).

run(G) :- G.

help.

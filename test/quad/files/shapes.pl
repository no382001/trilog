:- module(shapes, [area/2, shape//1, bump/0]).

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

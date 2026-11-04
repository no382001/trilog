:- module(callers, [c1/1, c2/1, c3/1, c4/1, c5/1]).

:- use_module(library(dcgs)).
:- use_module(shapes).

c1(X) :- shapes:sq(3, X).
c2(A) :- shapes:area(square(2), A).
c3(X) :- callers:later(X).
c4(W) :- phrase(shapes:word(W), "circle").
c5(X) :- notyet:f(X).

later(ok).

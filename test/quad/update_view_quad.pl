:- dynamic(c/1).
:- dynamic(d/1).
:- dynamic(e/0).
:- dynamic(g/1).

?- retractall(c(_)), assertz(c(1)), assertz(c(2)), findall(X, ( c(X), assertz(c(9)) ), L), findall(Y, c(Y), M).
   L = [1,2], M = [1,2,9,9].

?- retractall(c(_)), assertz(c(1)), assertz(c(2)), findall(X, ( c(X), retractall(c(_)) ), L), findall(Y, c(Y), M).
   L = [1,2], M = [].

?- retractall(c(_)), assertz(c(1)), assertz(c(2)), assertz(c(3)), findall(X, ( c(X), retract(c(2)) ), L).
   L = [1].

?- retractall(c(_)), assertz(c(1)), findall(X, ( c(X), asserta(c(0)) ), L), findall(Y, c(Y), M).
   L = [1], M = [0,1].

?- retractall(d(_)), assertz((d(X) :- member(X, [a,b,c]), !)), assertz(d(z)), findall(X, d(X), L).
   L = [a].

?- e.
   false.

?- retractall(g(_)), forall(between(1, 3000, I), assertz(g(I))), findall(I, g(I), _Is), length(_Is, N), retractall(g(_)).
   N = 3000.

?- consult('test/quad/files/update_view.pl'), findall(X, ( uv(X), consult('test/quad/files/update_view.pl') ), L), findall(Y, uv(Y), M).
   L = [a,b], M = [a,b].

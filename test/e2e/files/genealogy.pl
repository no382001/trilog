parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).

male(tom).
male(bob).
male(pat).

female(liz).
female(ann).

father(X, Y)   :- parent(X, Y), male(X).
mother(X, Y)   :- parent(X, Y), female(X).
son(X, Y)      :- parent(Y, X), male(X).
daughter(X, Y) :- parent(Y, X), female(X).
sibling(X, Y)  :- parent(Z, X), parent(Z, Y), X \= Y.

grandparent(X, Z) :- parent(X, Y), parent(Y, Z).

ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).

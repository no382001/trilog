:- module(flags, [toggle/1, save/1, saved/1]).

:- dynamic(flag/0).

toggle(State) :-
    ( flag -> retract(flag), State = off ; assertz(flag), State = on ).

:- dynamic(fact/1).

save(X) :- C = fact(X), assertz(C).
saved(Xs) :- findall(X, fact(X), Xs).

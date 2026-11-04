:- module(flags, [toggle/1, save/1, saved/1, save_rule/1, ruled/1]).

:- dynamic(flag/0).

toggle(State) :-
    ( flag -> retract(flag), State = off ; assertz(flag), State = on ).

:- dynamic(fact/1).

save(X) :- C = fact(X), assertz(C).
saved(Xs) :- findall(X, fact(X), Xs).

:- dynamic(rule/1).

save_rule(X) :- C = (rule(X) :- positive(X)), assertz(C).
ruled(X) :- rule(X).

positive(X) :- X > 0.

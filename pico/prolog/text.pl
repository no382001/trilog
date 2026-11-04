:- module(text, [emit/2,
                 atom//1,
                 int//1,
                 age//1,
                 path//1
                ]).

:- use_module(library(dcgs)).

:- meta_predicate(emit(?, '//')).

emit(Out, Body) :-
    forall(once(phrase(Body, Cs)), write_chars(Out, Cs)).

write_chars(_, []).
write_chars(Out, [C|Cs]) :-
    write(Out, C),
    write_chars(Out, Cs).

atom(A) --> { atom_chars(A, Cs) }, Cs.

int(N) --> { number_chars(N, Cs) }, Cs.

age(Ms) -->
    { S is Ms // 1000, D is Ms mod 1000 // 100 },
    "+", int(S), ".", int(D), "s".

path([C|Cs]) --> [C], { C \== ' ' }, path(Cs).
path([]) --> [].

:- '$builtin_file'.

:- module(error, [must_be/2,
                  can_be/2,
                  domain_error/3,
                  type_error/3,
                  character/1,
                  call_with_error_context/2]).

%!  boolean(@Term) is semidet.
boolean(true).
boolean(false).

pair(_-_).

%!  character(@Term) is semidet.
character(C) :- atom(C), atom_length(C, 1).

%!  must_be(+Type, @Term) is det.
must_be(Type, Term) :- must_be_(Type, Term, must_be/2).

must_be_(Type, _, Ctx) :-
    var(Type),
    !,
    throw(error(instantiation_error, Ctx)).
must_be_(Type, Term, Ctx) :- check(Type, Term, Ctx), !.
must_be_(Type, _, Ctx) :- throw(error(type_error(type, Type), Ctx)).

check(integer, T, C) :- ( integer(T) -> true ; not_type(integer, T, C) ).
check(atom, T, C) :- ( atom(T) -> true ; not_type(atom, T, C) ).
check(number, T, C) :- ( number(T) -> true ; not_type(number, T, C) ).
check(character, T, C) :- ( character(T) -> true ; not_type(character, T, C) ).
check(boolean, T, C) :- ( var(T) -> not_type(boolean, T, C) ; boolean(T) -> true ; not_type(boolean, T, C) ).
check(pair, T, C) :- ( var(T) -> not_type(pair, T, C) ; pair(T) -> true ; not_type(pair, T, C) ).
check(type, T, C) :- ( var(T) -> not_type(type, T, C) ; type(T) -> true ; not_type(type, T, C) ).
check(term, T, C) :-
    (   acyclic_term(T)
    ->  ( ground(T) -> true ; throw(error(instantiation_error, C)) )
    ;   throw(error(type_error(term, T), C))
    ).
check(var, T, C) :- ( var(T) -> true ; throw(error(uninstantiation_error(T), C)) ).
check(list, T, C) :- must_be_list(T, C).
check(chars, T, C) :- must_be_list(T, C), must_be_chars(T, C).
check(not_less_than_zero, T, C) :-
    check(integer, T, C),
    ( T >= 0 -> true ; throw(error(domain_error(not_less_than_zero, T), C)) ).

not_type(_, T, C) :- var(T), !, throw(error(instantiation_error, C)).
not_type(Type, T, C) :- throw(error(type_error(Type, T), C)).

type(integer).
type(atom).
type(number).
type(character).
type(boolean).
type(pair).
type(type).
type(term).
type(var).
type(list).
type(chars).
type(not_less_than_zero).

must_be_list(L, Ctx) :-
    '$$skip_list'(L, _, T),
    (   var(T) -> throw(error(instantiation_error, Ctx))
    ;   T == [] -> true
    ;   throw(error(type_error(list, L), Ctx))
    ).

must_be_chars([], _).
must_be_chars([C|Cs], Ctx) :-
    (   var(C) -> throw(error(instantiation_error, Ctx))
    ;   character(C) -> must_be_chars(Cs, Ctx)
    ;   throw(error(type_error(character, C), Ctx))
    ).

%!  can_be(+Type, @Term) is semidet.
%   Like must_be/2, but a Term that can still become Type passes: an unbound
%   Term, or a partial list for list and chars.
can_be(Type, _) :-
    var(Type),
    !,
    throw(error(instantiation_error, can_be/2)).
can_be(Type, Term) :-
    var(Term),
    !,
    ( type(Type) -> true ; throw(error(type_error(type, Type), can_be/2)) ).
can_be(term, Term) :-
    !,
    ( acyclic_term(Term) -> true ; throw(error(type_error(term, Term), can_be/2)) ).
can_be(list, Term) :- !, can_be_list(Term).
can_be(chars, Term) :- !, can_be_list(Term), can_be_chars(Term).
can_be(Type, Term) :- must_be_(Type, Term, can_be/2).

can_be_list(L) :-
    '$$skip_list'(L, _, T),
    ( var(T) -> true ; T == [] -> true ; throw(error(type_error(list, L), can_be/2)) ).

can_be_chars(Cs) :- var(Cs), !.
can_be_chars([]).
can_be_chars([C|Cs]) :-
    (   var(C) -> true
    ;   character(C) -> true
    ;   throw(error(type_error(character, C), can_be/2))
    ),
    can_be_chars(Cs).

%!  domain_error(+Domain, @Culprit, +Context) is det.
%!  type_error(+Type, @Culprit, +Context) is det.
%   Throw error(domain_error(Domain, Culprit), Context), or the type error.
domain_error(Domain, Culprit, Context) :-
    throw(error(domain_error(Domain, Culprit), Context)).
type_error(Type, Culprit, Context) :-
    throw(error(type_error(Type, Culprit), Context)).

:- meta_predicate(call_with_error_context(0, +)).

%!  call_with_error_context(:Goal, +Pair) is nondet.
%   Calls Goal; an error it raises gets Pair in front of its context.
call_with_error_context(G_0, Pair) :-
    must_be(pair, Pair),
    catch(G_0, error(E, Pairs), throw(error(E, [Pair|Pairs]))).

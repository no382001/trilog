:- '$builtin_file'.

%!  boolean(@Term) is semidet.
boolean(true).
boolean(false).

%!  character(@Term) is semidet.
character(C) :- atom(C), atom_length(C, 1).

%!  must_be(+Type, @Term) is det.
must_be(Type, Term) :- '$must_be'(Type, Term, must_be/2).

'$must_be'(Type, _, Ctx) :-
    var(Type),
    !,
    throw(error(instantiation_error, Ctx)).
'$must_be'(var, Term, Ctx) :-
    !,
    ( var(Term) -> true ; throw(error(uninstantiation_error(Term), Ctx)) ).
'$must_be'(_, Term, Ctx) :-
    var(Term),
    !,
    throw(error(instantiation_error, Ctx)).
'$must_be'(list, Term, Ctx) :- !, '$must_be_list'(Term, Ctx).
'$must_be'(chars, Term, Ctx) :-
    !,
    '$must_be_list'(Term, Ctx),
    '$must_be_chars'(Term, Ctx).
'$must_be'(not_less_than_zero, Term, Ctx) :-
    !,
    '$must_be'(integer, Term, Ctx),
    ( Term >= 0 -> true ; throw(error(domain_error(not_less_than_zero, Term), Ctx)) ).
'$must_be'(Type, Term, _) :- call(Type, Term), !.
'$must_be'(Type, Term, Ctx) :- throw(error(type_error(Type, Term), Ctx)).

'$must_be_list'(L, Ctx) :-
    '$$skip_list'(L, _, T),
    (   var(T) -> throw(error(instantiation_error, Ctx))
    ;   T == [] -> true
    ;   throw(error(type_error(list, L), Ctx))
    ).

'$must_be_chars'([], _).
'$must_be_chars'([C|Cs], Ctx) :-
    (   var(C) -> throw(error(instantiation_error, Ctx))
    ;   character(C) -> '$must_be_chars'(Cs, Ctx)
    ;   throw(error(type_error(character, C), Ctx))
    ).

%!  can_be(+Type, @Term) is semidet.
%   Like must_be/2, but a Term that can still become Type passes: an unbound
%   Term, or a partial list for list and chars.
can_be(Type, _) :-
    var(Type),
    !,
    throw(error(instantiation_error, can_be/2)).
can_be(_, Term) :- var(Term), !.
can_be(list, Term) :- !, '$can_be_list'(Term).
can_be(chars, Term) :- !, '$can_be_list'(Term), '$can_be_chars'(Term).
can_be(Type, Term) :- '$must_be'(Type, Term, can_be/2).

'$can_be_list'(L) :-
    '$$skip_list'(L, _, T),
    ( var(T) -> true ; T == [] -> true ; throw(error(type_error(list, L), can_be/2)) ).

'$can_be_chars'(Cs) :- var(Cs), !.
'$can_be_chars'([]).
'$can_be_chars'([C|Cs]) :-
    (   var(C) -> true
    ;   character(C) -> true
    ;   throw(error(type_error(character, C), can_be/2))
    ),
    '$can_be_chars'(Cs).

%!  domain_error(+Domain, @Culprit, +Context) is det.
%!  type_error(+Type, @Culprit, +Context) is det.
%   Throw error(domain_error(Domain, Culprit), Context), or the type error.
domain_error(Domain, Culprit, Context) :-
    throw(error(domain_error(Domain, Culprit), Context)).
type_error(Type, Culprit, Context) :-
    throw(error(type_error(Type, Culprit), Context)).

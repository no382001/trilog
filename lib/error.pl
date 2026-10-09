%!  boolean(@Term) is semidet.
boolean(true).
boolean(false).

%!  character(@Term) is semidet.
character(C) :- atom(C), atom_length(C, 1).

%!  must_be(+Type, @Term) is det.
must_be(Type, _) :-
    var(Type),
    !,
    throw(error(instantiation_error, must_be/2)).
must_be(var, Term) :-
    !,
    ( var(Term) -> true ; throw(error(uninstantiation_error(Term), must_be/2)) ).
must_be(list, Term) :- !, '$must_be_list'(Term).
must_be(not_less_than_zero, Term) :-
    !,
    '$must_be_type'(integer, Term),
    ( Term >= 0 -> true ; throw(error(domain_error(not_less_than_zero, Term), must_be/2)) ).
must_be(Type, Term) :- '$must_be_type'(Type, Term).

'$must_be_type'(_, Term) :-
    var(Term),
    !,
    throw(error(instantiation_error, must_be/2)).
'$must_be_type'(Type, Term) :- call(Type, Term), !.
'$must_be_type'(Type, Term) :- throw(error(type_error(Type, Term), must_be/2)).

'$must_be_list'([]) :- !.
'$must_be_list'([_|T]) :- !, '$must_be_list'(T).
'$must_be_list'(Term) :-
    ( var(Term) -> throw(error(instantiation_error, must_be/2))
    ; throw(error(type_error(list, Term), must_be/2))
    ).

%!  can_be(+Type, @Term) is semidet.
%   Like must_be/2, but an unbound Term passes without throwing.
can_be(Type, _) :-
    var(Type),
    !,
    throw(error(instantiation_error, can_be/2)).
can_be(_, Term) :- var(Term), !.
can_be(Type, Term) :- must_be(Type, Term).

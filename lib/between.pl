:- '$builtin_file'.

%!  between(+Low, +High, ?X) is nondet.
between(L, H, X) :-
    '$with_context'(( must_be(integer, L),
                      must_be(integer, H),
                      can_be(integer, X) ), between/3),
    (   integer(X)
    ->  X >= L, X =< H
    ;   '$between'(L, H, X)
    ).

'$between'(L, H, L) :- L =< H.
'$between'(L, H, X) :- L < H, L1 is L + 1, '$between'(L1, H, X).

%!  succ(?X, ?S) is semidet.
%   S is the successor of the non-negative integer X.
succ(X, S) :-
    (   var(X), var(S)
    ->  throw(error(instantiation_error, succ/2))
    ;   true
    ),
    '$with_context'(( can_be(not_less_than_zero, X),
                      can_be(not_less_than_zero, S) ), succ/2),
    (   nonvar(S)
    ->  S > 0, X is S - 1
    ;   S is X + 1
    ).

%!  plus(?A, ?B, ?C) is det.
plus(A, B, C) :- integer(A), integer(B), !, C is A + B.
plus(A, B, C) :- integer(A), integer(C), !, B is C - A.
plus(A, B, C) :- integer(B), integer(C), A is C - B.

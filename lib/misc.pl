:- '$builtin_file'.

%!  forall(:Cond, :Action) is semidet.
forall(Cond, Action) :- \+ (Cond, \+ Action).

%!  with_output_to(+Sink, :Goal) is semidet.
%   Sink is atom(-A) or codes(-Cs).
with_output_to(atom(A), Goal) :-
    '$$capture_start',
    % must pop the capture level even if Goal throws, or output stays silently swallowed after.
    ( catch(call(Goal), Ball, ('$$capture_stop'(_), throw(Ball)))
    -> '$$capture_stop'(A)
    ;  '$$capture_stop'(_), fail
    ).
with_output_to(codes(Cs), Goal) :- with_output_to(atom(A), Goal), '$$atom_codes'(A, Cs).
with_output_to(chars(Cs), Goal) :- with_output_to(atom(A), Goal), atom_chars(A, Cs).

%!  numbervars(?Term, +Start, -End) is det.
%   Binds each variable of Term to '$VAR'(N), N counting up from Start.
numbervars(T, S, E) :-
    (   var(S) -> throw(error(instantiation_error, numbervars/3))
    ;   integer(S) -> true
    ;   throw(error(type_error(integer, S), numbervars/3))
    ),
    term_variables(T, Vs),
    '$numbervars'(Vs, S, E).
'$numbervars'([], N, N).
'$numbervars'(['$VAR'(N)|Vs], N, E) :-
    N1 is N + 1,
    '$numbervars'(Vs, N1, E).

%!  writeln(@Term) is det.
%!  writeln(+Stream, @Term) is det.
writeln(T) :- write(T), nl.
writeln(S, T) :- write(S, T), nl(S).

%!  atom_number(?Atom, ?Number) is semidet.
atom_number(A, N) :-
    nonvar(A),
    !,
    '$$atom_codes'(A, C),
    '$$number_codes'(N, C).
atom_number(A, N) :-
    '$$number_codes'(N, C),
    '$$atom_codes'(A, C).

%!  countall(:Goal, ?N) is det.
%   N is the number of answers of Goal.
countall(G, N) :-
    '$must_be_callable'(G),
    '$must_be_count'(N),
    findall(t, G, Ts),
    length(Ts, N).

%!  call_nth(:Goal, ?Nth) is nondet.
%   Goal's Nth answer; with Nth unbound, each answer with its position.
call_nth(G, Nth) :-
    '$must_be_count'(Nth),
    Nth \== 0,
    State = count(0),
    call(G),
    arg(1, State, C0),
    C is C0 + 1,
    '$$nb_setarg'(1, State, C),
    ( integer(Nth) -> C =:= Nth, ! ; Nth = C ).

'$must_be_callable'(G) :- var(G), !, throw(error(instantiation_error, _)).
'$must_be_callable'(G) :- callable(G), !.
'$must_be_callable'(G) :- throw(error(type_error(callable, G), _)).

'$must_be_count'(N) :- var(N), !.
'$must_be_count'(N) :- integer(N), !, ( N >= 0 -> true ; throw(error(domain_error(not_less_than_zero, N), _)) ).
'$must_be_count'(N) :- throw(error(type_error(integer, N), _)).

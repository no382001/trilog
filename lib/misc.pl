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

:- '$builtin_file'.

:- ensure_loaded(library(misc)).

%!  write_term_to_chars(@Term, +Options, -Chars) is det.
write_term_to_chars(T, Opts, Cs) :-
    '$with_context'('$write_options'(Opts, _), write_term_to_chars/3),
    with_output_to(chars(Cs0), write_term(T, Opts)),
    Cs = Cs0.

%!  read_from_chars(+Chars, -Term) is det.
read_from_chars(Cs, T) :-
    '$with_context'('$read_term_from_chars'(Cs, T, []), read_from_chars/2).

%!  read_term_from_chars(+Chars, -Term, +Options) is det.
%   Options: variable_names(-Pairs), variables(-Vars), singletons(-Pairs).
%   Blank Chars read as end_of_file.
read_term_from_chars(Cs, T, Opts) :-
    '$with_context'('$read_term_from_chars'(Cs, T, Opts), read_term_from_chars/3).

'$read_term_from_chars'(Cs, T, Opts) :-
    '$options_list'(Opts),
    '$read_options_check'(Opts),
    '$chars_list'(Cs),
    (   '$blank_chars'(Cs)
    ->  T0 = end_of_file, Names = []
    ;   atom_chars(A, Cs),
        catch(atom_to_term(A, T0, Names), error(syntax_error(M), _),
              throw(error(syntax_error(M), _)))
    ),
    term_variables(T0, Vars),
    '$read_options_bind'(Opts, T0, Names, Vars),
    T = T0.

'$blank_chars'([]).
'$blank_chars'([C|Cs]) :- memberchk(C, [' ', '\t', '\n', '\r']), '$blank_chars'(Cs).

%!  read_line_to_chars(+Stream, -Chars) is det.
read_line_to_chars(S, Cs) :-
    read_line_to_atom(S, A),
    ( A == end_of_file -> Cs = end_of_file ; atom_chars(A, Cs) ).

%!  put_chars(+Chars) is det.
put_chars(Cs) :- atom_chars(A, Cs), write(A).
put_chars(S, Cs) :- atom_chars(A, Cs), write(S, A).

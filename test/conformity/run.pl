conformity(Setup, AnswerFile) :-
    (   Setup == ''
    ->  true
    ;   open(Setup, read, S),
        set_input(S),
        with_output_to(atom(_), goals(S, _)),
        set_input(user_input),
        close(S)
    ),
    open(AnswerFile, read, A),
    read_line_to_atom(A, Answer),
    close(A),
    with_output_to(chars(Out0), goals(user_input, Outcome)),
    renumber(Out0, Out),
    (   alternatives(Answer, Alts), member(Alt, Alts), judge(Alt, Out, Outcome)
    ->  write(pass), nl
    ;   atom_chars(Got, Out),
        write(fail), nl,
        write('expected: '), write(Answer), nl,
        write('got:      '), writeq(Got), write(' '), writeq(Outcome), nl
    ),
    halt.

goals(S, Outcome) :- goals(S, true([]), Outcome).

% A goal that fails or throws does not end the entry: earlier ones set up ops.

goals(S, Last, Outcome) :-
    catch(read_term(S, G, [variable_names(Names)]), error(E, _), true),
    (   nonvar(E)
    ->  read_error(E, Outcome)
    ;   G == end_of_file
    ->  Outcome = Last
    ;   catch(( call(G) -> R = true(Names) ; R = false ), Ball, R = thrown(Ball)),
        (   R = thrown(error(Formal, _)) -> O = error(Formal)
        ;   R = thrown(Other) -> O = error(Other)
        ;   O = R
        ),
        goals(S, O, Outcome)
    ).

read_error(syntax_error('end of file inside a term'), waits) :- !.
read_error(syntax_error(_), syntax_error) :- !.
read_error(E, error(E)).

alternatives('syntax err./waits', ['syntax err.', waits]) :- !.
alternatives('syntax/repr. err.', ['syntax err.', 'repr. err.']) :- !.
alternatives(Answer, Alts) :- split_or(Answer, Alts).

split_or(A, [B|Bs]) :-
    (   sub_atom(A, Before, _, After, ' or ')
    ->  sub_atom(A, 0, Before, _, B0),
        sub_atom(A, _, After, 0, Rest),
        example(B0, B),
        split_or(Rest, Bs)
    ;   example(A, B),
        Bs = []
    ).

% "e.g. X": X is one right answer; the variable names in it are examples.
example(A, B) :- ( atom_concat('e.g. ', B0, A) -> B = B0 ; B = A ).

judge('syntax err.', _, syntax_error) :- !.
judge(waits, _, waits) :- !.
judge(succeeds, _, true(_)) :- !.
judge(fails, _, false) :- !.
judge(A, _, error(E)) :- !,
    catch(error_answer(A, Exp), _, fail),
    subsumes_term(Exp, E).
judge(A, Out, true(Names)) :-
    (   bindings(A, Exp)
    ->  Out == [],
        bindings_match(Exp, Names)
    ;   sub_atom(A, Before, 1, _, ' '),
        sub_atom(A, 0, Before, _, Text),
        Skip is Before + 1,
        sub_atom(A, Skip, _, 0, Rest),
        bindings(Rest, Exp)
    ->  atom_chars(Text, Out),
        bindings_match(Exp, Names)
    ;   atom_chars(A, Out)
    ).

error_answer('repr. err.', representation_error(_)) :- !.
error_answer('rep._e.', representation_error(_)) :- !.
error_answer('ex._e.(..)', existence_error(_, _)) :- !.
error_answer(A, E) :-
    atom_chars(A, Cs0),
    foldl(expand, [ "p._e."-"permission_error", "d._e."-"domain_error",
                    "op._s."-"operator_specifier", "m."-"modify",
                    "c."-"create", "o."-"operator", ",op,"-",operator," ],
          Cs0, Cs),
    atom_chars(T, Cs),
    term_to_atom(E, T).

expand(From-To, Cs0, Cs) :-
    (   append(Before, Rest0, Cs0), append(From, After, Rest0)
    ->  expand(From-To, After, After1),
        append(Before, To, Cs1),
        append(Cs1, After1, Cs)
    ;   Cs = Cs0
    ).

bindings(A, Pairs) :-
    catch(atom_to_term(A, T, VNs), _, fail),
    conj_pairs(T, VNs, Pairs).

conj_pairs(T, _, _) :- var(T), !, fail.
conj_pairs((A, B), VNs, Ps) :- !,
    conj_pairs(A, VNs, P1), conj_pairs(B, VNs, P2), append(P1, P2, Ps).
conj_pairs(V = Value, VNs, [Name = Value]) :-
    var(V), member(Name = V0, VNs), V0 == V, !.

bindings_match([], _).
bindings_match([Name = Exp|Ps], Names) :-
    member(Name = Got, Names),
    subsumes_term(Exp, Got),
    subsumes_term(Got, Exp),
    bindings_match(Ps, Names).

% Ulrich writes fresh variables as _1, _2, ...; trilog prints _G123.
renumber(Cs, Out) :- renumber(Cs, [], Out).

renumber([], _, []).
renumber(['_', 'G', D|Cs0], Seen0, Out) :-
    digit(D),
    !,
    digits([D|Cs0], Ds, Cs),
    (   nth1(K, Seen0, Ds)
    ->  Seen = Seen0
    ;   append(Seen0, [Ds], Seen),
        length(Seen, K)
    ),
    number_chars(K, Ks),
    append(['_'|Ks], Out1, Out),
    renumber(Cs, Seen, Out1).
renumber([C|Cs], Seen, [C|Out]) :- renumber(Cs, Seen, Out).

digits([D|Cs0], [D|Ds], Cs) :- digit(D), !, digits(Cs0, Ds, Cs).
digits(Cs, [], Cs).

digit(D) :- char_code(D, C), C >= 0'0, C =< 0'9.

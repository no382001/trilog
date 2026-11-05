% Ulrich's conformity table on the pico: each entry runs from a slice of the
% table in flash, as conformity.sh runs it from stdin, with double_quotes put
% back after it; operators are not, as listing them all overflows the heap.
:- module(board, [conf/1, page/2]).

:- use_module(library(dcgs)).

%!  conf(+N) is det.
%   Runs the table's first N entries and prints a line for each: its result,
%   its time, and the atoms and trilog bytes it added.
conf(N) :- run(N, line).

%!  page(+Out, +N) is det.
%   The same lines as HTML on Out, each shown as soon as its entry is done.
page(Out, N) :-
    text:emit(Out, "<pre>\n"),
    run(N, row(Out)),
    text:emit(Out, "</pre>\n").

run(N, Report) :-
    open('test/conformity/conformity.txt', read, S),
    catch(entries(S, 0, N, none, 0-0, Report), E, ( close(S), throw(E) )),
    close(S).

entries(S, O0, K, Setup0, P0-F0, Report) :-
    field(S, O0, O1, NumCs, Sep),
    (   ( Sep == eof ; K =:= 0 )
    ->  report_total(Report, P0, F0)
    ;   field(S, O1, O2, QCs, _),
        field(S, O2, O3, ACs, _),
        number_chars(Num, NumCs),
        query(O1, QCs, Setup0, Setup, Run),
        % Backtracking out of \+ \+ frees all the entry made.
        (   \+ \+ ( run_entry(Run, ACs, Ok, Cost),
                    report(Report, Num, QCs, ACs, Ok, Cost),
                    Ok == pass )
        ->  P1 is P0 + 1, F1 = F0
        ;   P1 = P0, F1 is F0 + 1
        ),
        K1 is K - 1,
        entries(S, O3, K1, Setup, P1-F1, Report)
    ).

report(line, N, _, _, Ok, cost(Ms, DA, DL)) :-
    write(N), write(' '), write(Ok), write(' '), write(Ms), write(' ms, '),
    write(DA), write(' atoms, '), write(DL), write(' B'), nl.
% A piece at a time: one list for the whole line does not fit the heap.
report(row(Out), N, QCs, ACs, Ok, cost(Ms, DA, DL)) :-
    text:emit(Out, (text:int(N), " ", text:atom(Ok), " ", text:int(Ms), " ms, ",
                    text:int(DA), " atoms, ", text:int(DL), " B: ")),
    emit_escaped(Out, QCs),
    text:emit(Out, "  \x2192\  "),
    emit_escaped(Out, ACs),
    text:emit(Out, "\n").

emit_escaped(Out, Cs) :- forall(member(C, Cs), text:emit(Out, esc_char(C))).

report_total(line, P, F) :- write(passed(P, failed(F))), nl.
report_total(row(Out), P, F) :-
    text:emit(Out, ("\n", text:int(P), " passed, ", text:int(F), " failed\n")).

esc_char('<') --> !, "&lt;".
esc_char('>') --> !, "&gt;".
esc_char('&') --> !, "&amp;".
esc_char('\n') --> !, " \x23CE\ ".
esc_char(C) --> [C].

% A field's text without the newlines around it, and where the next begins.
field(S, O0, O, Cs, Sep) :-
    chars(S, O0, O, Cs0, Sep),
    ( Cs0 = ['\n'|Cs1] -> true ; Cs1 = Cs0 ),
    ( append(Cs, ['\n'], Cs1) -> true ; Cs = Cs1 ).

chars(S, O0, O, Cs, Sep) :-
    get_char(S, C),
    O1 is O0 + 1,
    (   C == end_of_file -> Cs = [], O = O1, Sep = eof
    ;   C == '\x1e\' -> Cs = [], O = O1, Sep = rs
    ;   C == '\x1d\' -> Cs = [], O = O1, Sep = gs
    ;   Cs = [C|Cs1], chars(S, O1, O, Cs1, Sep)
    ).

% Run is setup(SetupOff-Len, Off-Len) or plain(Off-Len): offsets of the text
% in the table. The page's /**/ stands for the last entry before without one.
query(O1, QCs, Setup0, Setup, Run) :-
    Start0 is O1 + 1,
    (   append(['/', '*', '*', '/'], Rest0, QCs)
    ->  ( Rest0 = [' '|Rest] -> Skip = 5 ; Rest = Rest0, Skip = 4 ),
        Start is Start0 + Skip,
        length(Rest, L),
        Setup = Setup0,
        Run = setup(Setup0, Start-L)
    ;   length(QCs, L),
        Setup = Start0-L,
        Run = plain(Start0-L)
    ).

run_entry(Run, ACs, Ok, cost(Ms, DA, DL)) :-
    current_prolog_flag(double_quotes, DQ),
    usage(A0, L0, T0),
    (   Run = setup(SO-SL, Q)
    ->  ( SO-SL == none -> true ; text(SO-SL, _, _) )
    ;   Run = plain(Q)
    ),
    text(Q, Out0, Outcome),
    renumber(Out0, Out),
    atom_chars(Answer, ACs),
    (   alternatives(Answer, Alts), member(Alt, Alts), judge(Alt, Out, Outcome)
    ->  Ok = pass
    ;   Ok = fail
    ),
    set_prolog_flag(double_quotes, DQ),
    usage(A1, L1, T1),
    Ms is T1 - T0, DA is A1 - A0, DL is L1 - L0.

usage(Atoms, Live, Ms) :-
    prolog_usage(_, _, _, Atoms, _, _),
    memory_usage(_, _, _, Live, _),
    get_time_ms(Ms).

text(Off-Len, Out, Outcome) :-
    Len1 is Len + 1,
    vfs_slice('test/conformity/conformity.txt', Off, Len1),
    open('vfs:slice', read, Q),
    set_input(Q),
    catch(with_output_to(chars(Out), goals(Q, Outcome)), E,
          ( Out = [], Outcome = error(E) )),
    set_input(user_input),
    close(Q).

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
    ->  true
    ;   same_float(A, Out)
    ).

% Float text that reads back as the same float is the same answer: the table
% writes 1.0e+100 where Scryer and trilog write 1.0e100.
same_float(A, Out) :-
    catch(( atom_chars(A, Cs), number_chars(X, Cs), number_chars(Y, Out) ),
          _, fail),
    float(X),
    X == Y.

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

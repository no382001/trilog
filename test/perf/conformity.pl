% Ulrich's conformity table in one process, as board.pl runs it on the pico:
% each entry's text goes to a file read as a stream, the operators and
% double_quotes are put back after it, and every entry must pass.
:- consult('../conformity/run.pl').

main :-
    findall(op(P, T, N), current_op(P, T, N), Ops),
    open('test/conformity/conformity.txt', read, S),
    entries(S, none, Ops, 0-0, Total-Passed),
    close(S),
    (   Passed =:= Total
    ->  true
    ;   throw(error(conformity(passed(Passed), of(Total)), main/0))
    ).

entries(S, Setup0, Ops, N0-P0, Total) :-
    field(S, NumCs, Sep),
    (   Sep == eof, NumCs == []
    ->  Total = N0-P0
    ;   field(S, QCs, _),
        field(S, ACs, _),
        (   QCs = ['/', '*', '*', '/'|Q0]
        ->  ( Q0 = [' '|Q] -> true ; Q = Q0 ),
            Pre = Setup0, Setup = Setup0
        ;   Q = QCs, Pre = none, Setup = QCs
        ),
        current_prolog_flag(double_quotes, DQ),
        ( \+ \+ entry(Pre, Q, ACs) -> P1 is P0 + 1 ; P1 = P0 ),
        set_prolog_flag(double_quotes, DQ),
        restore_ops(Ops),
        N1 is N0 + 1,
        entries(S, Setup, Ops, N1-P1, Total)
    ).

entry(Pre, Q, ACs) :-
    ( Pre == none -> true ; run_text(Pre, _, _) ),
    run_text(Q, Out0, Outcome),
    renumber(Out0, Out),
    atom_chars(Answer, ACs),
    alternatives(Answer, Alts),
    member(Alt, Alts),
    judge(Alt, Out, Outcome),
    !.

run_text(Cs, Out, Outcome) :-
    File = '_build/conformity_entry.pl',
    open(File, write, W),
    forall(member(C, Cs), put_char(W, C)),
    nl(W),
    close(W),
    open(File, read, R),
    set_input(R),
    catch(with_output_to(chars(Out), goals(R, Outcome)), E,
          ( Out = [], Outcome = error(E) )),
    set_input(user_input),
    close(R).

restore_ops(Ops) :-
    forall(( current_op(P, T, N), \+ memberchk(op(P, T, N), Ops) ),
           catch(op(0, T, N), _, true)),
    forall(( member(op(P, T, N), Ops), \+ current_op(P, T, N) ),
           catch(op(P, T, N), _, true)).

% A field's text without the newlines around it, up to its separator.
field(S, Cs, Sep) :-
    chars(S, Cs0, Sep),
    ( Cs0 = ['\n'|Cs1] -> true ; Cs1 = Cs0 ),
    ( append(Cs, ['\n'], Cs1) -> true ; Cs = Cs1 ).

chars(S, Cs, Sep) :-
    get_char(S, C),
    (   C == end_of_file -> Cs = [], Sep = eof
    ;   C == '\x1e\' -> Cs = [], Sep = rs
    ;   C == '\x1d\' -> Cs = [], Sep = gs
    ;   Cs = [C|Cs1], chars(S, Cs1, Sep)
    ).

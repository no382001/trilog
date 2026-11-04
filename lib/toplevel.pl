:- '$builtin_file'.

:- module(toplevel, [toplevel/0]).

:- use_module(library(editline)).

:- dynamic(answered/0).
:- dynamic(show_all/0).
:- dynamic(pending/1).

%!  toplevel is det.
%   Reads and runs queries until end of input or halt/0,1.
toplevel :-
    repeat,
    (   read_query(Q)
    ->  run_query(Q),
        fail
    ;   !
    ).

% A query is the lines up to one that ends in a full stop; at end of input,
% whatever was read. Fails at end of input with nothing read. A query typed
% in the editor goes into its history whole.
read_query(Q) :-
    read_text('?- ', '', Text, Edited),
    (   Edited == true -> add_history(Text) ; true ),
    catch(( atom_to_term(Text, Goal, VNs), Q = query(Goal, VNs) ),
          error(syntax_error(M), _),
          ( parse_error(M), Q = skip )).

read_text(Prompt, Text0, Text, Edited) :-
    (   read_line(Prompt, Line, Edited)
    ->  atom_concat(Text0, Line, Text1),
        (   blank(Text1)
        ->  read_text('?- ', '', Text, Edited)
        ;   ends_query(Line)
        ->  Text = Text1
        ;   atom_concat(Text1, '\n', Text2),
            read_text('', Text2, Text, Edited)
        )
    ;   \+ blank(Text0),
        Text = Text0
    ).

% With the terminal in raw mode, the line is edited and Edited is true;
% otherwise it is read as the host gives it. A key typed after an answer
% starts it.
read_line(Prompt, Line, Edited) :-
    (   retract(pending(K)) -> Initial = [K] ; Initial = [] ),
    (   '$tl_raw'(1)
    ->  Edited = true,
        edit_line(Prompt, Initial, Line)
    ;   (   '$tl_tty' -> write(Prompt), flush_output ; true ),
        atom_codes(Typed, Initial),
        write(Typed),
        '$tl_read_line'(Line0),
        atom_concat(Typed, Line0, Line)
    ).

blank(A) :- atom_chars(A, Cs), skip_layout(Cs, []).

ends_query(Line) :-
    atom_chars(Line, Cs),
    reverse(Cs, Rs),
    skip_layout(Rs, ['.'|_]).

skip_layout([C|Cs], Rest) :- memberchk(C, [' ', '\t', '\r']), !, skip_layout(Cs, Rest).
skip_layout(Cs, Cs).

parse_error(M) :-
    flush_output,
    write(user_error, 'parse error: '),
    write(user_error, M),
    nl(user_error).

run_query(skip).
run_query(query(Goal, VNs)) :-
    retractall(answered),
    retractall(show_all),
    catch(answers(Goal, VNs), E, uncaught(E)).

% The query runs in user, not in this module. The mark is taken inside the
% condition, past the if-then-else's own frame, so a goal that leaves no
% choice point is seen as done.
answers(Goal, VNs) :-
    (   '$$choice_mark'(M0),
        call(user:Goal),
        '$$choice_mark'(M1),
        show(VNs, M0, M1)
    ->  true
    ;   answered
    ->  write('.'), nl
    ;   write('   false.'), nl
    ).

% Succeeds to stop at this answer, fails to look for the next one.
show(VNs, M0, M1) :-
    (   answered -> nl, write(';  ') ; assertz(answered), write('   ') ),
    write_answer(VNs),
    (   M1 == M0
    ->  write('.'), nl
    ;   stop
    ).

% An answer as the toplevel shows it: "X = f(_A), Y = X", or "true". Each
% unbound variable takes the last query name bound to it; the rest are _A,
% _B, ... skipping the query's own names.
write_answer(VNs) :-
    reverse(VNs, RVNs),
    claims(RVNs, [], Claims),
    bindings(VNs, Claims, Shown),
    values(Shown, Vs),
    term_variables(Vs, Free),
    fresh(Free, Claims, VNs, 0, Claims, Names),
    (   Shown == []
    ->  write(true)
    ;   write_pairs(Shown, Names, '')
    ).

% term_variables/2 does not end on a cyclic term, so those are left out.
values([], []).
values([_-S|Ps], Vs) :-
    (   S = value(V), acyclic_term(V) -> Vs = [V|Vs1] ; Vs = Vs1 ),
    values(Ps, Vs1).

claims([], Cs, Cs).
claims([N=V|Ps], Cs0, Cs) :-
    (   var(V), \+ claimed(V, Cs0, _)
    ->  claims(Ps, [N=V|Cs0], Cs)
    ;   claims(Ps, Cs0, Cs)
    ).

claimed(V, [N=W|Cs], Name) :-
    (   W == V -> Name = N ; claimed(V, Cs, Name) ).

bindings([], _, []).
bindings([N=V|Ps], Cs, Shown) :-
    (   var(V), claimed(V, Cs, M)
    ->  ( M == N -> Shown = Shown1 ; Shown = [N-alias(M)|Shown1] )
    ;   Shown = [N-value(V)|Shown1]
    ),
    bindings(Ps, Cs, Shown1).

fresh([], _, _, _, Names, Names).
fresh([V|Vs], Cs, VNs, K0, Names0, Names) :-
    (   claimed(V, Cs, _)
    ->  fresh(Vs, Cs, VNs, K0, Names0, Names)
    ;   fresh_name(K0, VNs, K, Name),
        K1 is K + 1,
        fresh(Vs, Cs, VNs, K1, [Name=V|Names0], Names)
    ).

fresh_name(K0, VNs, K, Name) :-
    L is 0'A + K0 mod 26,
    char_code(C, L),
    (   K0 // 26 =:= 0
    ->  atom_concat('_', C, Name0)
    ;   N is K0 // 26,
        number_codes(N, Ds),
        atom_codes(D, Ds),
        atom_concat('_', C, Name1),
        atom_concat(Name1, D, Name0)
    ),
    (   memberchk(Name0=_, VNs)
    ->  K1 is K0 + 1,
        fresh_name(K1, VNs, K, Name)
    ;   K = K0,
        Name = Name0
    ).

write_pairs([], _, _).
write_pairs([N-S|Ps], Names, Sep) :-
    write(Sep),
    write(N),
    write(' = '),
    (   S = alias(M)
    ->  write(M)
    ;   S = value(V),
        write_value(V, Names)
    ),
    write_pairs(Ps, Names, ', ').

% The right side of =, so an operator atom or a term whose operator binds
% looser than 699 is bracketed.
write_value(V, Names) :-
    Opts = [quoted(true), double_quotes(true), variable_names(Names)],
    (   bracket(V)
    ->  write('('), write_term(V, Opts), write(')')
    ;   write_term(V, Opts)
    ).

bracket(V) :- atom(V), !, current_op(_, _, V).
bracket(V) :-
    compound(V),
    functor(V, F, A),
    current_op(P, T, F),
    P > 699,
    (   A =:= 2 -> memberchk(T, [xfx, xfy, yfx])
    ;   A =:= 1 -> memberchk(T, [fy, fx, xf, yf])
    ),
    !.

stop :-
    \+ show_all,
    '$tl_tty',
    flush_output,
    '$tl_key'(K),
    (   K =:= 0'a
    ->  assertz(show_all),
        fail
    ;   ( K =:= 0'; ; K =:= 0'  )
    ->  fail
    ;   (   K > 0'  , K < 127, K =\= 0'. -> assertz(pending(K)) ; true ),
        nl, write(';  ... .'), nl
    ).

uncaught(E) :-
    flush_output,
    write(user_error, 'uncaught exception: '),
    writeq(user_error, E),
    nl(user_error).

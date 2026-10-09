% --- line-buffering utilities ---

ws_code(32).
ws_code(0'\t).
ws_code(0'\n).
ws_code(0'\r).

trim_leading(Atom, Trimmed) :-
    atom_codes(Atom, Cs),
    tl_codes(Cs, Cs2),
    atom_codes(Trimmed, Cs2).
tl_codes([C|Cs], Out) :-
    (C =:= 32 ; C =:= 0'\t), !,
    tl_codes(Cs, Out).
tl_codes(Cs, Cs).

% strip_line_comment(+Line, -Stripped): drop a trailing "% ..." comment
strip_line_comment(Line, Stripped) :-
    atom_codes(Line, Cs),
    slc(Cs, out, Out),
    atom_codes(Stripped, Out).

slc([], _, []) :- !.
slc([0'0, 0'\', 0'\\, Esc|Cs], out, [0'0, 0'\', 0'\\, Esc|Out]) :- !, slc(Cs, out, Out).
slc([0'0, 0'\', Ch|Cs], out, [0'0, 0'\', Ch|Out]) :- !, slc(Cs, out, Out).
slc([0'\\, E|Cs], dq, [0'\\, E|Out]) :- !, slc(Cs, dq, Out).
slc([0'\\, E|Cs], sq, [0'\\, E|Out]) :- !, slc(Cs, sq, Out).
slc([0'\', 0'\'|Cs], sq, [0'\', 0'\'|Out]) :- !, slc(Cs, sq, Out).
slc([0'"|Cs], dq, [0'"|Out]) :- !, slc(Cs, out, Out).
slc([0'"|Cs], out, [0'"|Out]) :- !, slc(Cs, dq, Out).
slc([0'\'|Cs], sq, [0'\'|Out]) :- !, slc(Cs, out, Out).
slc([0'\'|Cs], out, [0'\'|Out]) :- !, slc(Cs, sq, Out).
slc([0'%|_], out, []) :- !.
slc([C|Cs], State, [C|Out]) :- slc(Cs, State, Out).

% has_complete_clause(+Buf): true if Buf contains a terminating '.' at
% bracket depth 0, outside any quoted region, not part of "=..".
has_complete_clause(Buf) :- atom_codes(Buf, Cs), hcc(Cs, out, 0, 32).

hcc([], _, _, _) :- fail.
hcc([0'0, 0'\', 0'\\, _Esc|Cs], out, D, _) :- !, hcc(Cs, out, D, 0'0).
hcc([0'0, 0'\', _Ch|Cs], out, D, _) :- !, hcc(Cs, out, D, 0'0).
hcc([0'\\, _|Cs], dq, D, _) :- !, hcc(Cs, dq, D, 0'\\).
hcc([0'\\, _|Cs], sq, D, _) :- !, hcc(Cs, sq, D, 0'\\).
hcc([0'\', 0'\'|Cs], sq, D, _) :- !, hcc(Cs, sq, D, 0'\').
hcc([0'"|Cs], dq, D, _) :- !, hcc(Cs, out, D, 0'").
hcc([0'"|Cs], out, D, _) :- !, hcc(Cs, dq, D, 0'").
hcc([0'\'|Cs], sq, D, _) :- !, hcc(Cs, out, D, 0'\').
hcc([0'\'|Cs], out, D, _) :- !, hcc(Cs, sq, D, 0'\').
hcc([C|Cs], out, D, _) :- ( C =:= 0'( ; C =:= 0'[ ), !, D1 is D + 1, hcc(Cs, out, D1, C).
hcc([C|Cs], out, D, _) :- ( C =:= 0') ; C =:= 0'] ), !, D1 is D - 1, hcc(Cs, out, D1, C).
hcc([0'.|Cs], out, 0, Prev) :-
    !,
    ( Prev =:= 0'.
    -> hcc(Cs, out, 0, 0'.)
    ;  ( Cs == []
       -> true
       ;  Cs = [N|_], ws_code(N)
       -> true
       ;  hcc(Cs, out, 0, 0'.)
       )
    ).
hcc([C|Cs], State, D, _) :- hcc(Cs, State, D, C).

% dcg_accumulate/3: plain multi-line buffer join
dcg_accumulate(Buf0, Line, Buf) :-
    trim_leading(Line, Trimmed),
    ( Buf0 == '', Trimmed == '' -> Buf = Buf0
    ; Buf0 == '' -> Buf = Trimmed
    ; atom_concat(Buf0, ' ', Buf1), atom_concat(Buf1, Trimmed, Buf)
    ).

% --- line splitting ---

split_nl(Atom, Lines) :-
    atom_codes(Atom, Cs),
    split_nl_codes(Cs, LinesCodes),
    codes_lists_to_atoms(LinesCodes, Lines).

codes_lists_to_atoms([], []).
codes_lists_to_atoms([Cs|Css], [A|As]) :- atom_codes(A, Cs), codes_lists_to_atoms(Css, As).

split_nl_codes(Cs, [Line|Rest]) :- append(Line, [0'\n|Tail], Cs), !, split_nl_codes(Tail, Rest).
split_nl_codes(Cs, [Cs]).

trim_trailing(Atom, Trimmed) :-
    atom_codes(Atom, Cs),
    reverse(Cs, R0),
    tt_codes(R0, R1),
    reverse(R1, Cs2),
    atom_codes(Trimmed, Cs2).

tt_codes([C|Cs], Out) :- ws_code(C), !, tt_codes(Cs, Out).
tt_codes(Cs, Cs).

% --- answer parsing: "x = a\n;  x = b" -> ['x = a', 'x = b'] ---

strip_terminating_dot(Buf, Stripped) :-
    atom_codes(Buf, Cs),
    std_codes(Cs, out, 0, 32, Cs2),
    atom_codes(Stripped, Cs2).

std_codes([], _, _, _, []).
std_codes([0'0, 0'\', 0'\\, Esc|Cs], out, D, _, [0'0, 0'\', 0'\\, Esc|Out]) :-
    !, std_codes(Cs, out, D, Esc, Out).
std_codes([0'0, 0'\', Ch|Cs], out, D, _, [0'0, 0'\', Ch|Out]) :-
    !, std_codes(Cs, out, D, Ch, Out).
std_codes([0'\\, E|Cs], dq, D, _, [0'\\, E|Out]) :- !, std_codes(Cs, dq, D, 0'\\, Out).
std_codes([0'\\, E|Cs], sq, D, _, [0'\\, E|Out]) :- !, std_codes(Cs, sq, D, 0'\\, Out).
std_codes([0'\', 0'\'|Cs], sq, D, _, [0'\', 0'\'|Out]) :- !, std_codes(Cs, sq, D, 0'\', Out).
std_codes([0'"|Cs], dq, D, _, [0'"|Out]) :- !, std_codes(Cs, out, D, 0'", Out).
std_codes([0'"|Cs], out, D, _, [0'"|Out]) :- !, std_codes(Cs, dq, D, 0'", Out).
std_codes([0'\'|Cs], sq, D, _, [0'\'|Out]) :- !, std_codes(Cs, out, D, 0'\', Out).
std_codes([0'\'|Cs], out, D, _, [0'\'|Out]) :- !, std_codes(Cs, sq, D, 0'\', Out).
std_codes([C|Cs], out, D, _, [C|Out]) :-
    (C =:= 0'( ; C =:= 0'[), !, D1 is D + 1, std_codes(Cs, out, D1, C, Out).
std_codes([C|Cs], out, D, _, [C|Out]) :-
    (C =:= 0') ; C =:= 0']), !, D1 is D - 1, std_codes(Cs, out, D1, C, Out).
std_codes([0'.|Cs], out, 0, Prev, Out) :-
    !,
    ( Prev =:= 0'.
    -> Out = [0'.|Out1], std_codes(Cs, out, 0, 0'., Out1)
    ;  ( Cs == []
       -> Out = []
       ;  Cs = [N|_], ws_code(N)
       -> Out = []
       ;  Out = [0'.|Out1], std_codes(Cs, out, 0, 0'., Out1)
       )
    ).
std_codes([C|Cs], State, D, _, [C|Out]) :- std_codes(Cs, State, D, C, Out).

parse_expected(AnswerRaw, Expected, Mode) :-
    strip_terminating_dot(AnswerRaw, Answer),
    split_nl(Answer, Lines),
    pe_group(Lines, Groups),
    maplist(pe_join_trim, Groups, Expected0),
    exclude(==(''), Expected0, Expected1),
    ( append(Prefix, ['..., ad_infinitum'], Expected1)
    -> Mode = ad_infinitum, Expected = Prefix
    ;  Mode = exact, Expected = Expected1
    ).

pe_group([], []).
pe_group([L|Ls], Groups) :- pe_group_(Ls, [L], Groups).

pe_group_([], CurRev, [Cur]) :- reverse(CurRev, Cur).
pe_group_([L|Ls], CurRev, Groups) :-
    trim_leading(L, T),
    ( T == ''
    -> pe_group_(Ls, CurRev, Groups)
    ;  sub_atom(T, 0, 1, _, ';')
    -> reverse(CurRev, Cur),
       sub_atom(T, 1, _, 0, Rest0),
       trim_leading(Rest0, Rest),
       pe_group_(Ls, [Rest], Groups0),
       Groups = [Cur|Groups0]
    ;  pe_group_(Ls, [L|CurRev], Groups)
    ).

pe_join_trim(Group, Joined) :- pe_join(Group, J0), trim_leading(J0, J1), trim_trailing(J1, Joined).

pe_join([L], L) :- !.
pe_join([L|Ls], Joined) :-
    pe_join(Ls, Rest),
    atom_concat(L, ' ', L1),
    atom_concat(L1, Rest, Joined).

% --- solution collection, capped at MAX_QUAD_ANSWERS ---

:- dynamic(quad_solution_count/1).

collect_solutions(Query, NameVars, Max, Strs, Snaps) :-
    retractall(quad_solution_count(_)),
    assertz(quad_solution_count(0)),
    with_output_to(atom(_), findall(Str-Snap, capped_snapshot(Query, NameVars, Max, Str, Snap), Sols)),
    pairs_keys_values_(Sols, Strs, Snaps).

% Cyclic bindings can't be copied - text comparison only.
capped_snapshot(Query, NameVars, Max, Str, Snap) :-
    capped_solution(Query, NameVars, Max, Str),
    ( catch(copy_term(NameVars, _), error(representation_error(cyclic_term), _), fail)
    -> Snap = NameVars
    ;  Snap = none
    ).

pairs_keys_values_([], [], []).
pairs_keys_values_([K-V|KVs], [K|Ks], [V|Vs]) :- pairs_keys_values_(KVs, Ks, Vs).

capped_solution(Query, NameVars, Max, Str) :-
    call(Query),
    format_bindings(NameVars, Str),
    retract(quad_solution_count(N)),
    N1 is N + 1,
    assertz(quad_solution_count(N1)),
    ( N1 >= Max -> ! ; true ).

% "Name = Val, ..." over NameVars pairs still bound after Query ran, skipping '_'-named ones - "true" if none remain.
format_bindings(NameVars, Str) :-
    '$format_bindings_pairs'(NameVars, Pairs),
    ( Pairs == [] -> Str = true ; with_output_to(atom(Str), '$write_bindings'(Pairs)) ).

'$format_bindings_pairs'([], []).
'$format_bindings_pairs'([Name=Val|Rest], Pairs) :-
    ( sub_atom(Name, 0, 1, _, '_') -> Pairs = Pairs1
    ; var(Val) -> Pairs = Pairs1
    ; Pairs = [Name=Val|Pairs1]
    ),
    '$format_bindings_pairs'(Rest, Pairs1).

'$write_bindings'([N=V]) :- !, write(N), write(' = '), writeq(V).
'$write_bindings'([N=V|Rest]) :- write(N), write(' = '), writeq(V), write(', '), '$write_bindings'(Rest).

% --- running one test ---

quad_display(Query, Display) :-
    ( atom_length(Query, Len), Len > 60
    -> sub_atom(Query, 0, 57, _, Head), atom_concat(Head, '...', Display)
    ;  Display = Query
    ).

strip_query_prefix(Raw, Query) :-
    ( sub_atom(Raw, 0, 2, _, '?-')
    -> sub_atom(Raw, 2, _, 0, Rest)
    ;  Rest = Raw
    ),
    trim_leading(Rest, Query).

% Timings read 0 on a platform without get_time_ms/1.
quad_now(T) :-
    catch(get_time_ms(T), error(existence_error(procedure, _), _), T = 0).

run_one_test(QueryRaw, AnswerRaw, Pass) :-
    strip_query_prefix(QueryRaw, Query0),
    strip_terminating_dot(Query0, Query),
    parse_expected(AnswerRaw, Expected, Mode),
    quad_display(Query, Display),
    quad_ckpt_before(Display),
    quad_now(T0),
    ( catch(atom_to_term(Query, QueryTerm, NameVars), error(syntax_error(_), _), fail)
    -> ( catch(
             ( collect_solutions(QueryTerm, NameVars, 64, Got, Snaps), Error = none ),
             Ball,
             ( Got = [], Snaps = [], quad_error_type(Ball, Error) )
         )
       -> true
       ;  Got = [], Snaps = [], Error = none
       )
    ;  Got = [], Snaps = [], Error = quad_unparseable
    ),
    quad_now(T1),
    ElapsedMs is T1 - T0,
    quad_judge(Expected, Got, Snaps, Error, Mode, Pass, Reason),
    retract(quad_stat(TN0, P0, F0, TMs0)),
    TestNum is TN0 + 1,
    ( Pass == true -> P1 is P0 + 1, F1 = F0 ; P1 = P0, F1 is F0 + 1 ),
    TMs1 is TMs0 + ElapsedMs,
    assertz(quad_stat(TestNum, P1, F1, TMs1)),
    assertz(quad_record(TestNum, Display, Pass, Reason, ElapsedMs)),
    quad_ckpt_after(Display, Pass, Reason, ElapsedMs),
    quad_report(TestNum, Display, Pass, Reason, ElapsedMs),
    !.

% JUnit-mode crash checkpointing: when set, each test durably records itself before/after, so a crash mid-file is recoverable (quad_cli_junit/3).
:- dynamic(quad_ckpt_ctx/3).

quad_ckpt_before(Display) :-
    ( quad_ckpt_ctx(ProgressPath, _, _)
    -> catch((open(ProgressPath, write, S), write(S, Display), nl(S), close(S)), _, true)
    ;  true
    ).

quad_ckpt_after(Display, Pass, Reason, ElapsedMs) :-
    ( quad_ckpt_ctx(_, PartialPath, Suite)
    -> catch((open(PartialPath, append, S),
              write_testcase(S, Suite, Display, Pass, Reason, ElapsedMs),
              close(S)), _, true)
    ;  true
    ).

% error(Type, _) balls reduce to Type; any other thrown term is used as-is.
quad_error_type(error(Type, _), Type) :- !.
quad_error_type(Ball, Ball).

quad_judge(Expected, Got, Snaps, Error, Mode, Pass, Reason) :-
    ( Mode == ad_infinitum
    -> quad_judge_ad_infinitum(Expected, Got, Snaps, Error, Pass, Reason)
    ;  quad_judge_exact(Expected, Got, Snaps, Error, Pass, Reason)
    ).

quad_ad_infinitum_witness(8).

quad_judge_ad_infinitum(Expected, Got, Snaps, Error, Pass, Reason) :-
    ( Error \== none
    -> Pass = false, format_atom('error: ~w', [Error], Reason)
    ;  length(Expected, PrefixLen),
       quad_ad_infinitum_witness(Witness),
       MinLen is PrefixLen + Witness,
       length(GotPrefix, PrefixLen),
       append(GotPrefix, _, Got),
       length(SnapPrefix, PrefixLen),
       append(SnapPrefix, _, Snaps),
       quad_answers_match(Expected, GotPrefix, SnapPrefix),
       length(Got, GotLen),
       GotLen >= MinLen
    -> Pass = true, Reason = ''
    ;  quad_ad_infinitum_witness(Witness2),
       format_atom('expected: ~w, then ..., ad_infinitum (at least ~w more)~ngot: ~w',
                   [Expected, Witness2, quad_got(Got, Error)], Reason),
       Pass = false
    ).

quad_judge_exact(Expected, Got, Snaps, Error, Pass, Reason) :-
    ( Expected = [false]
    -> ( Got == [], Error == none -> Pass = true, Reason = ''
       ;  Pass = false, format_atom('expected: false~ngot: ~w', [quad_got(Got, Error)], Reason)
       )
    ;  Expected = [ExpErr], is_error_expectation(ExpErr, ExpType)
    -> ( Error \== none, matches_error(Error, ExpType)
       -> Pass = true, Reason = ''
       ;  Pass = false,
          format_atom('expected: ~w~ngot: ~w', [ExpErr, quad_got(Got, Error)], Reason)
       )
    ;  Error \== none
    -> Pass = false, format_atom('error: ~w', [Error], Reason)
    ;  quad_answers_match(Expected, Got, Snaps)
    -> Pass = true, Reason = ''
    ;  Pass = false, format_atom('expected: ~w~ngot: ~w', [Expected, Got], Reason)
    ).

% --- answer comparison, as terms ---

quad_answers_match([], [], []).
quad_answers_match([E|Es], [G|Gs], [S|Ss]) :-
    ( E == G -> true ; quad_answer_match(E, S) ),
    quad_answers_match(Es, Gs, Ss).

quad_answer_match(ExpAtom, Snap) :-
    Snap \== none,
    catch(atom_to_term(ExpAtom, ET, ENames), _, fail),
    qa_exp_pairs(ET, ENames, EPairs0),
    \+ \+ ( qa_mark_unbound(Snap),
            qa_link_names(ENames, Snap),
            qa_got_pairs(Snap, GPairs0),
            msort(EPairs0, EPairs),
            msort(GPairs0, GPairs),
            qa_variant(EPairs, GPairs) ).

% "X = a, Y = b" -> ['X'=a, 'Y'=b]; "true" -> [].
qa_exp_pairs(true, _, []) :- !.
qa_exp_pairs((A, B), Names, Pairs) :- !,
    qa_exp_pairs(A, Names, PA), qa_exp_pairs(B, Names, PB), append(PA, PB, Pairs).
qa_exp_pairs(L = R, Names, [N = R]) :- var(L), qa_var_name(Names, L, N).

qa_var_name([N = V|_], L, N) :- V == L, !.
qa_var_name([_|Ns], L, N) :- qa_var_name(Ns, L, N).

% Unbound query vars become '$qv'(Name), matching only same-named expected vars.
qa_mark_unbound([]).
qa_mark_unbound([N = V|Ps]) :- ( var(V) -> V = '$qv'(N) ; true ), qa_mark_unbound(Ps).

qa_link_names([], _).
qa_link_names([N = V|Ns], Snap) :-
    ( member(N = GV, Snap) -> V = GV ; true ),
    qa_link_names(Ns, Snap).

% Mirrors format_bindings/2.
qa_got_pairs([], []).
qa_got_pairs([N = V|Ps], Out) :-
    ( sub_atom(N, 0, 1, _, '_') -> Out = Out1
    ; V == '$qv'(N) -> Out = Out1
    ; Out = [N = V|Out1]
    ),
    qa_got_pairs(Ps, Out1).

qa_variant(A, B) :-
    \+ \+ ( copy_term(A, A1), copy_term(B, B1),
            qa_number_vars(A1, 0, _), qa_number_vars(B1, 0, _),
            A1 == B1 ).

qa_number_vars(T, N0, N) :- var(T), !, T = '$qa_var'(N0), N is N0 + 1.
qa_number_vars(T, N0, N0) :- atomic(T), !.
qa_number_vars(T, N0, N) :- T =.. [_|Args], qa_number_vars_list(Args, N0, N).

qa_number_vars_list([], N, N).
qa_number_vars_list([A|As], N0, N) :- qa_number_vars(A, N0, N1), qa_number_vars_list(As, N1, N).

is_error_expectation(Atom, Type) :- atom_concat('error(', Rest, Atom), atom_concat(Type, ')', Rest).

% Falls back to comparing as terms: "foo/0" vs /(foo, 0), "a,b" vs "a, b".
matches_error(Error, ExpType) :-
    term_to_atom(Error, ErrAtom),
    ( ErrAtom == ExpType -> true
    ; atom_concat(ExpType, _, ErrAtom) -> true
    ; strip_at_marks(ExpType, Clean),
      catch(atom_to_term(Clean, ExpTerm, _), _, fail),
      \+ \+ Error = ExpTerm
    ).

% Some expected errors carry an @ prefix from the
% suite they were transcribed from, so drop them.
strip_at_marks(Atom, Clean) :-
    atom_codes(Atom, Cs),
    sam(Cs, out, Out),
    atom_codes(Clean, Out).

sam([], _, []).
sam([0'@|Cs], out, Out) :- !, sam(Cs, out, Out).
sam([0'\', 0'\'|Cs], sq, [0'\', 0'\'|Out]) :- !, sam(Cs, sq, Out).
sam([0'\'|Cs], out, [0'\'|Out]) :- !, sam(Cs, sq, Out).
sam([0'\'|Cs], sq, [0'\'|Out]) :- !, sam(Cs, out, Out).
sam([C|Cs], St, [C|Out]) :- sam(Cs, St, Out).

format_atom(Fmt, Args, Atom) :- with_output_to(atom(Atom), format_write(Fmt, Args)).

format_write(Fmt, Args) :- atom_chars(Fmt, Cs), fw_codes(Cs, Args).

fw_codes([], []).
fw_codes(['~', w|Cs], [A|As]) :- !, write(A), fw_codes(Cs, As).
fw_codes(['~', n|Cs], As) :- !, nl, fw_codes(Cs, As).
fw_codes([C|Cs], As) :- write(C), fw_codes(Cs, As).

quad_report(TestNum, Display, true, _, ElapsedMs) :-
    !,
    ms_to_secs_atom(ElapsedMs, TimeAtom),
    write('ok '), write(TestNum), write(' - ?- '), write(Display),
    write(' # time='), write(TimeAtom), write('s'), nl, flush_output.
quad_report(TestNum, Display, false, Reason, ElapsedMs) :-
    ms_to_secs_atom(ElapsedMs, TimeAtom),
    write('not ok '), write(TestNum), write(' - ?- '), write(Display),
    write(' # time='), write(TimeAtom), write('s'), nl,
    write_reason_lines(Reason),
    flush_output.

write_reason_lines(Reason) :-
    split_nl(Reason, Lines),
    forall(member(L, Lines), (write('#   '), write(L), nl)).

% --- elapsed-time formatting: "S.mmm" ---

pad3(N, Atom) :-
    atom_number(NAtom, N),
    ( N < 10 -> atom_concat('00', NAtom, Atom)
    ; N < 100 -> atom_concat('0', NAtom, Atom)
    ; Atom = NAtom
    ).

ms_to_secs_atom(Ms, Atom) :-
    Secs is Ms // 1000,
    Frac is Ms mod 1000,
    pad3(Frac, FracAtom),
    atom_number(SecsAtom, Secs),
    atom_concat(SecsAtom, '.', A1),
    atom_concat(A1, FracAtom, Atom).

% --- quad file parsing and running ---

:- dynamic(quad_stat/4).
:- dynamic(quad_record/5).

run_quad_file(File) :- run_quad_file(File, 0).

% Skip: how many query/answer blocks to re-parse but not re-execute
% (directives/facts still run either way).
run_quad_file(File, Skip) :-
    retractall(quad_stat(_, _, _, _)),
    assertz(quad_stat(0, 0, 0, 0)),
    retractall(quad_record(_, _, _, _, _)),
    open(File, read, S),
    qf_loop(S, '', '', query, Skip, 0),
    close(S),
    quad_stat(Total, Passed, Failed, TotalMs),
    ms_to_secs_atom(TotalMs, TotalTimeAtom),
    write('# '), write(File), write(': '), write(Total), write(' tests, '),
    write(Passed), write(' passed, '), write(Failed), write(' failed, '),
    write(TotalTimeAtom), write('s total'), nl.

qf_loop(S, ClauseBuf, AnswerBuf, Mode, Skip, SeenCount) :-
    read_line_to_atom(S, Line0),
    ( Line0 == end_of_file
    -> true
    ;  strip_line_comment(Line0, Line),
       trim_leading(Line, Trimmed),
       ( Mode == answer
       -> qf_answer_step(S, ClauseBuf, AnswerBuf, Line, Trimmed, Skip, SeenCount)
       ;  qf_clause_step(S, ClauseBuf, Line, Trimmed, Skip, SeenCount)
       )
    ).

qf_answer_step(S, QueryBuf, AnswerBuf0, Line, Trimmed, Skip, SeenCount) :-
    ( AnswerBuf0 == '', Trimmed == ''
    -> qf_loop(S, QueryBuf, AnswerBuf0, answer, Skip, SeenCount)
    ;  ( AnswerBuf0 == '' -> AnswerBuf1 = Line
       ;  atom_concat(AnswerBuf0, '\n', AB1), atom_concat(AB1, Line, AnswerBuf1)
       ),
       ( has_complete_clause(AnswerBuf1)
       -> SeenCount1 is SeenCount + 1,
          ( SeenCount1 =< Skip
          -> true
          ;  once(run_one_test(QueryBuf, AnswerBuf1, _Pass))
          ),
          qf_loop(S, '', '', query, Skip, SeenCount1)
       ;  qf_loop(S, QueryBuf, AnswerBuf1, answer, Skip, SeenCount)
       )
    ).

qf_clause_step(S, ClauseBuf0, Line, Trimmed, Skip, SeenCount) :-
    dcg_accumulate(ClauseBuf0, Trimmed, ClauseBuf1),
    ( has_complete_clause(ClauseBuf1)
    -> ( sub_atom(ClauseBuf1, 0, 2, _, '?-')
       -> qf_loop(S, ClauseBuf1, '', answer, Skip, SeenCount)
       ;  sub_atom(ClauseBuf1, 0, 2, _, ':-')
       -> sub_atom(ClauseBuf1, 2, _, 0, DirText0),
          strip_terminating_dot(DirText0, DirText),
          ( catch((atom_to_term(DirText, Goal, _),
                   with_output_to(atom(_), catch(call(Goal), _, true))), _, fail)
          -> true
          ;  true
          ),
          qf_loop(S, '', '', query, Skip, SeenCount)
       ;  strip_terminating_dot(ClauseBuf1, ClauseText),
          ( catch((atom_to_term(ClauseText, Term, _), assertz(Term)), _, fail)
          -> true
          ;  true
          ),
          qf_loop(S, '', '', query, Skip, SeenCount)
       )
    ;  qf_loop(S, ClauseBuf1, '', query, Skip, SeenCount)
    ).

% --- CLI entry point: exit code 0 if all pass, 1 if any failed ---

quad_cli(File) :-
    once(run_quad_file(File)),
    quad_stat(_, _, Failed, _),
    ( Failed > 0 -> halt(1) ; halt(0) ).

% --- JUnit XML output, with crash-resume support ---

last_path_segment(Path, Seg) :-
    atom_codes(Path, Cs),
    ( append(_, [0'/|SegCs], Cs), \+ member(0'/, SegCs) -> true ; SegCs = Cs ),
    atom_codes(Seg, SegCs).

strip_ext(Atom, Base) :-
    atom_codes(Atom, Cs),
    ( append(BaseCs, [0'.|Rest], Cs), \+ member(0'., Rest) -> true ; BaseCs = Cs ),
    atom_codes(Base, BaseCs).

quad_suite_name(File, Suite) :- last_path_segment(File, Seg), strip_ext(Seg, Suite).

xml_escape(Atom, Escaped) :- atom_codes(Atom, Cs), xesc_codes(Cs, Out), atom_codes(Escaped, Out).

xesc_codes([], []).
xesc_codes([0'&|Cs], [0'&, 0'a, 0'm, 0'p, 0';|Out]) :- !, xesc_codes(Cs, Out).
xesc_codes([0'<|Cs], [0'&, 0'l, 0't, 0';|Out]) :- !, xesc_codes(Cs, Out).
xesc_codes([0'>|Cs], [0'&, 0'g, 0't, 0';|Out]) :- !, xesc_codes(Cs, Out).
xesc_codes([0'"|Cs], [0'&, 0'q, 0'u, 0'o, 0't, 0';|Out]) :- !, xesc_codes(Cs, Out).
xesc_codes([0'\n|Cs], [0'&, 0'#, 0'1, 0'0, 0';|Out]) :- !, xesc_codes(Cs, Out).
xesc_codes([0'\r|Cs], [0'&, 0'#, 0'1, 0'3, 0';|Out]) :- !, xesc_codes(Cs, Out).
xesc_codes([C|Cs], [C|Out]) :- xesc_codes(Cs, Out).

write_testcase(Strm, Suite, Name, true, _, ElapsedMs) :-
    !,
    xml_escape(Name, EscName),
    ms_to_secs_atom(ElapsedMs, TimeAtom),
    format_atom('  <testcase name="~w" classname="~w" time="~w"/>', [EscName, Suite, TimeAtom], Line),
    write(Strm, Line), nl(Strm).
write_testcase(Strm, Suite, Name, false, Reason, ElapsedMs) :-
    xml_escape(Name, EscName),
    xml_escape(Reason, EscReason),
    ms_to_secs_atom(ElapsedMs, TimeAtom),
    format_atom('  <testcase name="~w" classname="~w" time="~w">', [EscName, Suite, TimeAtom], Open),
    write(Strm, Open), nl(Strm),
    format_atom('    <failure message="~w"/>', [EscReason], FailLine),
    write(Strm, FailLine), nl(Strm),
    write(Strm, '  </testcase>'), nl(Strm).

run_quad_file_junit(File, Dir) :- run_quad_file_junit(File, Dir, 0).

% Skip > 0: resuming after a crash, so keep the existing scratch files
% instead of truncating them.
run_quad_file_junit(File, Dir, Skip) :-
    quad_suite_name(File, Suite),
    atom_concat(Dir, '/', D1),
    atom_concat(D1, Suite, D2),
    atom_concat(D2, '.progress', ProgressPath),
    atom_concat(D2, '.xml.partial', PartialPath),
    ( Skip =:= 0
    -> catch((open(ProgressPath, write, S1), close(S1)), _, true),
       catch((open(PartialPath, write, S2), close(S2)), _, true)
    ;  true
    ),
    retractall(quad_ckpt_ctx(_, _, _)),
    assertz(quad_ckpt_ctx(ProgressPath, PartialPath, Suite)),
    run_quad_file(File, Skip),
    retractall(quad_ckpt_ctx(_, _, _)),
    quad_finalize_junit(File, Suite, Dir).

read_whole_file(Path, Whole) :- open(Path, read, S), rwf_loop(S, '', Whole), close(S).

rwf_loop(S, Acc, Whole) :-
    read_line_to_atom(S, Line),
    ( Line == end_of_file
    -> Whole = Acc
    ;  atom_concat(Line, '\n', L1), atom_concat(Acc, L1, Acc1), rwf_loop(S, Acc1, Whole)
    ).

% one line at a time, no atom_concat accumulation over the whole file.
count_partial(Path, TestcaseCount, FailureCount, TotalMs) :-
    catch(
        ( open(Path, read, S),
          cp_loop(S, stat(0, 0, 0), stat(TestcaseCount, FailureCount, TotalMs)),
          close(S)
        ), _, ( TestcaseCount = 0, FailureCount = 0, TotalMs = 0 )).

cp_loop(S, stat(AccT, AccF, AccMs), Stat) :-
    read_line_to_atom(S, Line),
    ( Line == end_of_file
    -> Stat = stat(AccT, AccF, AccMs)
    ;  ( line_has_prefix(Line, '  <testcase ')
       -> AccT1 is AccT + 1,
          ( line_time_ms(Line, LineMs) -> AccMs1 is AccMs + LineMs ; AccMs1 = AccMs )
       ;  AccT1 = AccT, AccMs1 = AccMs
       ),
       ( line_has_prefix(Line, '    <failure ') -> AccF1 is AccF + 1 ; AccF1 = AccF ),
       cp_loop(S, stat(AccT1, AccF1, AccMs1), Stat)
    ).

% copies Path's lines verbatim to the already-open OutStrm, one line at a
% time
stream_copy_lines(Path, OutStrm) :-
    catch((open(Path, read, S), scl_loop(S, OutStrm), close(S)), _, true).

scl_loop(S, OutStrm) :-
    read_line_to_atom(S, Line),
    ( Line == end_of_file
    -> true
    ;  write(OutStrm, Line), nl(OutStrm), scl_loop(S, OutStrm)
    ).

line_has_prefix(Line, Prefix) :-
    atom_length(Prefix, Len),
    atom_length(Line, LineLen),
    LineLen >= Len,
    sub_atom(Line, 0, Len, _, Prefix).

% pulls the time="S.mmm" attribute out of a <testcase> line and converts
% it back to milliseconds (mirrors ms_to_secs_atom/2's "S.mmm" format).
line_time_ms(Line, Ms) :-
    sub_atom(Line, Before, 6, _, 'time="'),
    !,
    Start is Before + 6,
    sub_atom(Line, Start, _, 0, Rest),
    sub_atom(Rest, EndBefore, _, _, '"'),
    !,
    sub_atom(Rest, 0, EndBefore, _, TimeStr),
    secs_atom_to_ms(TimeStr, Ms).

secs_atom_to_ms(Atom, Ms) :-
    ( sub_atom(Atom, B, 1, A, '.')
    -> sub_atom(Atom, 0, B, _, SecsPart),
       sub_atom(Atom, _, A, 0, FracPart),
       atom_number(SecsPart, Secs),
       atom_number(FracPart, FracMs),
       Ms is Secs * 1000 + FracMs
    ;  atom_number(Atom, Secs), Ms is Secs * 1000
    ).

% appends a synthetic "crashed here" <testcase> naming the in-flight
% query, so the next resume attempt's Skip steps past it too.
quad_mark_crash(Suite, Dir) :-
    atom_concat(Dir, '/', D1),
    atom_concat(D1, Suite, D2),
    atom_concat(D2, '.progress', ProgressPath),
    atom_concat(D2, '.xml.partial', PartialPath),
    ( catch(read_whole_file(ProgressPath, CrashedRaw), _, fail)
    -> trim_trailing(CrashedRaw, CrashedDisplay)
    ;  CrashedDisplay = 'unknown query (no checkpoint recorded)'
    ),
    xml_escape(CrashedDisplay, EscCrashed),
    format_atom('  <testcase name="~w (trilog crashed here)" classname="~w" time="0.000">',
                [EscCrashed, Suite], CrashOpen),
    open(PartialPath, append, Strm),
    write(Strm, CrashOpen), nl(Strm),
    write(Strm, '    <failure message="trilog crashed while running this test (see harness log for details)"/>'), nl(Strm),
    write(Strm, '  </testcase>'), nl(Strm),
    close(Strm).

quad_resolved_count(Suite, Dir, Count) :-
    atom_concat(Dir, '/', D1),
    atom_concat(D1, Suite, D2),
    atom_concat(D2, '.xml.partial', PartialPath),
    count_partial(PartialPath, Count, _Failed, _TotalMs).

% two passes: counts need to be known before the opening tag is written,
% so pass 1 counts and pass 2 streams the body across.
quad_finalize_junit(File, Suite, Dir) :-
    atom_concat(Dir, '/', D1),
    atom_concat(D1, Suite, D2),
    atom_concat(D2, '.xml', XmlPath),
    atom_concat(D2, '.progress', ProgressPath),
    atom_concat(D2, '.xml.partial', PartialPath),
    count_partial(PartialPath, Total, Failed, TotalMs),
    xml_escape(File, EscFile),
    ms_to_secs_atom(TotalMs, TotalTimeAtom),
    open(XmlPath, write, Strm),
    write(Strm, '<?xml version="1.0" encoding="UTF-8"?>'), nl(Strm),
    format_atom('<testsuite name="~w" file="~w" tests="~w" failures="~w" errors="0" time="~w">',
                [Suite, EscFile, Total, Failed, TotalTimeAtom], Header),
    write(Strm, Header), nl(Strm),
    stream_copy_lines(PartialPath, Strm),
    write(Strm, '</testsuite>'), nl(Strm),
    close(Strm),
    catch((open(ProgressPath, write, S1), close(S1)), _, true),
    catch((open(PartialPath, write, S2), close(S2)), _, true).

quad_cli_junit(File, Dir) :- quad_cli_junit(File, Dir, 0).

quad_cli_junit(File, Dir, Skip) :-
    once(run_quad_file_junit(File, Dir, Skip)),
    quad_stat(_, _, Failed, _),
    ( Failed > 0 -> halt(1) ; halt(0) ).

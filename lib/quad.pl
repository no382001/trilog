:- '$builtin_file'.

:- ensure_loaded(library(apply)).
:- ensure_loaded(library(dcgs)).

% --- text as chars ---

blank(' ').
blank('\t').
blank('\n').
blank('\r').

trim_leading([C|Cs0], Cs) :- ( C == ' ' ; C == '\t' ), !, trim_leading(Cs0, Cs).
trim_leading(Cs, Cs).

trim_trailing(Cs0, Cs) :- reverse(Cs0, R0), drop_blanks(R0, R), reverse(R, Cs).

drop_blanks([C|Cs0], Cs) :- blank(C), !, drop_blanks(Cs0, Cs).
drop_blanks(Cs, Cs).

trim(Cs0, Cs) :- trim_leading(Cs0, Cs1), trim_trailing(Cs1, Cs).

lines([L|Ls]) --> line(L), ( "\n" -> lines(Ls) ; { Ls = [] } ).

line([C|Cs]) --> [C], { C \== '\n' }, !, line(Cs).
line([]) --> [].

join(_, [], []).
join(_, [L], L) :- !.
join(Sep, [L|Ls], Cs) :- join(Sep, Ls, Cs1), append(Sep, Cs1, Cs2), append(L, Cs2, Cs).

concat([], []).
concat([L|Ls], Cs) :- concat(Ls, Cs1), append(L, Cs1, Cs).

symbol_char(C) :- memberchk(C, ['+','-','*','/','\\','^','<','>','=','~',':','.','?','@','#','&','$']).

digit(D) --> [D], { char_code(D, C), C >= 0'0, C =< 0'9 }.

digits([D|Ds]) --> digit(D), digits(Ds).
digits([D]) --> digit(D).

% marks(Ms): each char as o(C) outside quotes, or q(C) inside a quoted item or
% a 0'c literal, so '%', '.' and brackets count only where they are syntax.
% Dispatching on the char, the first argument, lets indexing pick the clause.
marks([], []).
marks([C|Cs], Ms) :- mark(C, Cs, Ms).

mark('0', ['''', '''', ''''|Cs], [o('0'), q(''''), q(''''), q('''')|Ms]) :- !, marks(Cs, Ms).
mark('0', ['''', '\\', E|Cs], [o('0'), q(''''), q('\\'), q(E)|Ms]) :- !, marks(Cs, Ms).
mark('0', ['''', C|Cs], [o('0'), q(''''), q(C)|Ms]) :- !, marks(Cs, Ms).
mark('''', Cs, [q('''')|Ms]) :- !, quoted(Cs, '''', Ms).
mark('"', Cs, [q('"')|Ms]) :- !, quoted(Cs, '"', Ms).
mark(C, Cs, [o(C)|Ms]) :- marks(Cs, Ms).

quoted([], _, []).
quoted([C|Cs], Q, Ms) :- quoted_char(C, Q, Cs, Ms).

quoted_char('\\', Q, Cs0, [q('\\')|Ms]) :-
    phrase(numeric_escape(Es), Cs0, Cs),
    !,
    q_marks(Es, Ms, Ms1),
    quoted(Cs, Q, Ms1).
quoted_char('\\', Q, [E|Cs], [q('\\'), q(E)|Ms]) :- !, quoted(Cs, Q, Ms).
quoted_char(Q, Q, [Q|Cs], [q(Q), q(Q)|Ms]) :- !, quoted(Cs, Q, Ms).
quoted_char(Q, Q, Cs, [q(Q)|Ms]) :- !, marks(Cs, Ms).
quoted_char(C, Q, Cs, [q(C)|Ms]) :- quoted(Cs, Q, Ms).

q_marks([], Ms, Ms).
q_marks([C|Cs], [q(C)|Ms0], Ms) :- q_marks(Cs, Ms0, Ms).

% An octal \141\ or hex \x61\ escape runs to the next backslash.
numeric_escape([C|Cs]) --> [C], { C == x ; memberchk(C, ['0','1','2','3','4','5','6','7']) }, escape_digits(Cs).

escape_digits(['\\']) --> "\\", !.
escape_digits([C|Cs]) --> [C], { hex_digit(C) }, escape_digits(Cs).

hex_digit(C) :- char_code(C, X), ( X >= 0'0, X =< 0'9 ; X >= 0'a, X =< 0'f ; X >= 0'A, X =< 0'F ), !.

mark_char(M, C) :- arg(1, M, C).

uncommented(Cs0, Cs) :-
    (   memberchk('%', Cs0)
    ->  marks(Cs0, Ms),
        before_comment(Ms, Cs)
    ;   Cs = Cs0
    ).

before_comment([], []).
before_comment([o('%')|_], []) :- !.
before_comment([M|Ms], [C|Cs]) :- mark_char(M, C), before_comment(Ms, Cs).

% clause_body(Ms, Body): Body is the text before the clause's end, a '.' at
% bracket depth 0 that is not part of "=.." and is followed by layout or EOF.
clause_body(Ms, Body) :- cb(Ms, 0, ' ', Body).

cb([o('.')|Ms], 0, Prev, []) :-
    Prev \== '.',
    ( Ms == [] ; Ms = [M|_], mark_char(M, N), blank(N) ),
    !.
cb([M|Ms], D0, _, [C|Body]) :-
    mark_char(M, C),
    (   M = o(B), memberchk(B, ['(', '[']) -> D is D0 + 1
    ;   M = o(B), memberchk(B, [')', ']']) -> D is D0 - 1
    ;   D = D0
    ),
    ( M = o(P) -> true ; P = none ),
    cb(Ms, D, P, Body).

has_complete_clause(Cs) :- marks(Cs, Ms), clause_body(Ms, _).

strip_terminating_dot(Cs, Body) :-
    marks(Cs, Ms),
    ( clause_body(Ms, Body) -> true ; Body = Cs ).

% --- a quad file as items: tests, directives and clauses ---

quad_items([I|Is]) --> quad_item(I), !, quad_items(Is).
quad_items([]) --> [].

quad_item(I) --> blank_lines, clause_text(Cs), { item_kind(Cs, K) }, item_tail(K, I).

blank_lines --> [L], { trim_leading(L, []) }, !, blank_lines.
blank_lines --> [].

clause_text(Cs) --> [L], { trim_leading(L, T0), strip_id(T0, T) }, clause_more(T, Cs).

clause_more(Cs, Cs) --> { memberchk('.', Cs), has_complete_clause(Cs) }, !.
clause_more(Cs0, Cs) --> [L], { trim_leading(L, T), append(Cs0, [' '|T], Cs1) }, clause_tail(T, Cs1, Cs).

% Only a line with a '.' can end the clause.
clause_tail(T, Cs0, Cs) --> { \+ memberchk('.', T) }, !, clause_more_lines(Cs0, Cs).
clause_tail(_, Cs0, Cs) --> clause_more(Cs0, Cs).

clause_more_lines(Cs0, Cs) --> [L], { trim_leading(L, T), append(Cs0, [' '|T], Cs1) }, clause_tail(T, Cs1, Cs).

item_kind(Cs, test(Cs)) :- append("?-", _, Cs), !.
item_kind(Cs, directive(D)) :- append(":-", D, Cs), !.
item_kind(Cs, clause(Cs)).

item_tail(test(Q), test(Q, A)) --> !, answer(A).
item_tail(K, K) --> [].

% An answer runs to its terminating '.'; Ulrich continues one on indented lines.
answer(A) --> blank_lines, [L], answer_more([L], A).

answer_more([L|Ls], A) -->
    { memberchk('.', L), reverse([L|Ls], Lines), join("\n", Lines, Cs), has_complete_clause(Cs) },
    !,
    answer_done([L|Ls], A).
answer_more(Rev, A) --> [L], answer_more([L|Rev], A).

answer_done(Rev, A) --> [L], { continuation(L) }, !, answer_more([L|Rev], A).
answer_done(Rev, A) --> { reverse(Rev, Ls), join("\n", Ls, A) }.

continuation(L) :-
    trim_leading(L, T),
    T \== [],
    L \== T,
    \+ append("?-", _, T),
    strip_id(T, T),
    T \= [':'|_].

% Ulrich numbers his quads: "66 ?- number_chars(N,\"010\")."
strip_id(T0, T) :- phrase((digits(_), " ", spaces), T0, T), T = ['?', '-'|_], !.
strip_id(T, T).

spaces --> " ", !, spaces.
spaces --> [].

% --- the expected answer: alternatives, renderings, answer sequences ---

% A line starting with "|" begins another acceptable outcome.
quad_alternatives(Raw, Alts) :-
    phrase(lines(Lines0), Raw),
    exclude(unexpected_line, Lines0, Lines1),
    maplist(strip_sto, Lines1, Lines2),
    exclude(open_line, Lines2, Lines),
    Lines \== [],
    alt_groups(Lines, [], Groups),
    maplist(join("\n"), Groups, Alts0),
    exclude(untestable, Alts0, Alts1),
    maplist(renderings, Alts1, Altss),
    concat(Altss, Alts).

unexpected_line(L) :-
    trim_trailing(L, T),
    ( append(_, ", unexpected.", T) ; append(_, ", unexpected", T) ),
    !.

strip_sto(L, Out) :-
    trim_leading(L, T),
    (   T = ['|'|R0]
    ->  trim_leading(R0, R),
        ( append("sto, ", R1, R) -> append("| ", R1, Out) ; Out = L )
    ;   append("sto, ", R1, T)
    ->  Out = R1
    ;   Out = L
    ).

open_line(L) :- trim_leading(L, T), trim_trailing(T, "... ; ... .").

untestable(Alt) :- trim(Alt, T), ( T == "loops" ; T == "loops." ).

alt_groups([], Cur, [G]) :- reverse(Cur, G).
alt_groups([L|Ls], Cur, Gs) :-
    trim_leading(L, T),
    (   Cur \== [], T = ['|'|Rest]
    ->  reverse(Cur, G),
        Gs = [G|Gs1],
        alt_groups(Ls, [Rest], Gs1)
    ;   alt_groups(Ls, [L|Cur], Gs)
    ).

% One answer written several ways, as "N = 0'a. N = 97.", is split at each '.'.
renderings(Alt, Rs) :-
    \+ ( append(_, ['.', W|_], Alt), blank(W) ),
    !,
    Rs = [Alt].
renderings(Alt, Rs) :-
    marks(Alt, Ms),
    split_renderings(Ms, ' ', [], Parts),
    exclude(==([]), Parts, Rs0),
    ( Rs0 = [_, _|_] -> Rs = Rs0 ; Rs = [Alt] ).

split_renderings([], _, Cur, [P]) :- reverse(Cur, P0), trim_leading(P0, P).
split_renderings([o('.'), M|Ms], Prev, Cur, [P|Ps]) :-
    mark_char(M, W),
    blank(W),
    \+ symbol_char(Prev),
    !,
    reverse(Cur, P0),
    trim_leading(P0, P),
    split_renderings([M|Ms], W, [], Ps).
split_renderings([M|Ms], _, Cur, Ps) :-
    mark_char(M, C),
    split_renderings(Ms, C, [C|Cur], Ps).

% "x = a\n;  x = b" -> ['x = a', 'x = b'].
parse_expected(Alt, Expected, Mode) :-
    strip_terminating_dot(Alt, Answer),
    phrase(lines(Lines), Answer),
    answer_groups(Lines, Groups),
    maplist(join(" "), Groups, Joined),
    maplist(trim, Joined, Trimmed),
    exclude(==([]), Trimmed, Answers),
    maplist(chars_atom, Answers, Expected1),
    (   append(Prefix, ['..., ad_infinitum'], Expected1)
    ->  Mode = more(8), Expected = Prefix
    ;   append(Prefix, ['...'], Expected1)
    ->  Mode = more(1), Expected = Prefix
    ;   Mode = exact, Expected = Expected1
    ).

% A test written only as answers marked ", unexpected." passes unless it gives one.
unexpected_answers(Raw, Us) :-
    phrase(lines(Ls), Raw),
    include(unexpected_line, Ls, ULs),
    ULs \== [],
    maplist(drop_unexpected, ULs, Us).

drop_unexpected(L, U) :-
    trim(L, T),
    ( append(U0, ", unexpected.", T) -> true ; append(U0, ", unexpected", T) ),
    trim(U0, U).

answer_groups([], []).
answer_groups([L|Ls], Gs) :- answer_groups(Ls, [L], Gs).

answer_groups([], Cur, [G]) :- reverse(Cur, G).
answer_groups([L|Ls], Cur, Gs) :-
    trim_leading(L, T),
    (   T == []
    ->  answer_groups(Ls, Cur, Gs)
    ;   T = [';'|R0]
    ->  reverse(Cur, G),
        trim_leading(R0, R),
        Gs = [G|Gs1],
        answer_groups(Ls, [R], Gs1)
    ;   answer_groups(Ls, [L|Cur], Gs)
    ).

chars_atom(Cs, A) :- atom_chars(A, Cs).

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
    ( catch(copy_term(NameVars, _), error(representation_error(term), _), fail)
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
    ( atom_chars(Name, ['_'|_]) -> Pairs = Pairs1
    ; var(Val) -> Pairs = Pairs1
    ; Pairs = [Name=Val|Pairs1]
    ),
    '$format_bindings_pairs'(Rest, Pairs1).

'$write_bindings'([N=V]) :- !, write(N), write(' = '), writeq(V).
'$write_bindings'([N=V|Rest]) :- write(N), write(' = '), writeq(V), write(', '), '$write_bindings'(Rest).

% --- running one test ---

quad_display(Query, Display) :-
    atom_chars(Query, Cs),
    (   length(Cs, Len), Len > 60
    ->  length(Head, 57),
        append(Head, _, Cs),
        append(Head, "...", Ds),
        atom_chars(Display, Ds)
    ;   Display = Query
    ).

query_text(Raw, Query) :-
    ( append("?-", Rest, Raw) -> true ; Rest = Raw ),
    trim_leading(Rest, Q0),
    strip_terminating_dot(Q0, Q),
    atom_chars(Query, Q).

% Timings read 0 on a platform without get_time_ms/1.
quad_now(T) :-
    catch(get_time_ms(T), error(existence_error(procedure, _), _), T = 0).

run_one_test(QueryRaw, AnswerRaw, Pass) :-
    query_text(QueryRaw, Query),
    (   quad_alternatives(AnswerRaw, Alts) -> Expect = Alts
    ;   unexpected_answers(AnswerRaw, Us) -> Expect = not(Us)
    ;   Expect = ["no answer to test"]
    ),
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
    quad_judge_expect(Expect, Got, Snaps, Error, Pass, Reason),
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

quad_judge_alts([Alt|Alts], Got, Snaps, Error, Pass, Reason) :-
    parse_expected(Alt, Expected, Mode),
    quad_judge(Expected, Got, Snaps, Error, Mode, Pass0, Reason0),
    ( Pass0 == true -> Pass = true, Reason = ''
    ; Alts == [] -> Pass = false, Reason = Reason0
    ; quad_judge_alts(Alts, Got, Snaps, Error, Pass, Reason)
    ).

quad_judge(Expected, Got, Snaps, Error, Mode, Pass, Reason) :-
    ( Mode = more(Witness)
    -> quad_judge_more(Expected, Witness, Got, Snaps, Error, Pass, Reason)
    ;  quad_judge_exact(Expected, Got, Snaps, Error, Pass, Reason)
    ).

quad_judge_expect(not(Us), Got, Snaps, Error, Pass, Reason) :- !,
    (   quad_judge_alts(Us, Got, Snaps, Error, true, _)
    ->  Pass = false,
        format_atom('gave an answer marked unexpected: ~w', [quad_got(Got, Error)], Reason)
    ;   Pass = true, Reason = ''
    ).
quad_judge_expect(Alts, Got, Snaps, Error, Pass, Reason) :-
    quad_judge_alts(Alts, Got, Snaps, Error, Pass, Reason).

% Expected answers, then at least Witness more.
quad_judge_more(Expected, Witness, Got, Snaps, Error, Pass, Reason) :-
    ( Error \== none
    -> Pass = false, format_atom('error: ~w', [Error], Reason)
    ;  length(Expected, PrefixLen),
       MinLen is PrefixLen + Witness,
       length(GotPrefix, PrefixLen),
       append(GotPrefix, _, Got),
       length(SnapPrefix, PrefixLen),
       append(SnapPrefix, _, Snaps),
       quad_answers_match(Expected, GotPrefix, SnapPrefix),
       length(Got, GotLen),
       GotLen >= MinLen
    -> Pass = true, Reason = ''
    ;  format_atom('expected: ~w, then at least ~w more~ngot: ~w',
                   [Expected, Witness, quad_got(Got, Error)], Reason),
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
            qa_drop_any(EPairs0, GPairs0, EPairs1, GPairs1),
            msort(EPairs1, EPairs),
            msort(GPairs1, GPairs),
            qa_variant(EPairs, GPairs) ).

qa_drop_any(E0, G0, E, G) :-
    findall(N, member(N = '...', E0), Any),
    exclude(qa_named(Any), E0, E),
    exclude(qa_named(Any), G0, G).

qa_named(Names, N = _) :- memberchk(N, Names).

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
    ( atom_chars(N, ['_'|_]) -> Out = Out1
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

is_error_expectation(Atom, Type) :-
    atom_chars(Atom, Cs),
    append("error(", Rest, Cs),
    append(TypeCs0, [')'], Rest),
    !,
    ( without_context(TypeCs0, TypeCs) -> true ; TypeCs = TypeCs0 ),
    atom_chars(Type, TypeCs).

% "error(F, _)" expects the formal F with any context.
without_context(Cs0, Cs) :-
    trim_trailing(Cs0, Cs1),
    append(Cs2, ['_'], Cs1),
    trim_trailing(Cs2, Cs3),
    append(Cs4, [','], Cs3),
    trim_trailing(Cs4, Cs).
is_error_expectation(Atom, Atom) :-
    catch(atom_to_term(Atom, T, _), _, fail),
    callable(T),
    functor(T, N, _),
    ( N == instantiation_error ; N == system_error ; atom_chars(N, Cs), append(_, "_error", Cs) ),
    !.

% Falls back to comparing as terms: "foo/0" vs /(foo, 0), "a,b" vs "a, b".
matches_error(Error, ExpType) :-
    term_to_atom(Error, ErrAtom),
    atom_chars(ErrAtom, ErrCs),
    atom_chars(ExpType, ExpCs),
    (   append(ExpCs, _, ErrCs)
    ->  true
    ;   phrase(without_at_marks(CleanCs), ExpCs),
        atom_chars(Clean, CleanCs),
        catch(atom_to_term(Clean, ExpTerm0, _), _, fail),
        err_dots(ExpTerm0, ExpTerm),
        \+ \+ Error = ExpTerm
    ).

% "..." in an expected error matches anything.
err_dots(T, _) :- T == '...', !.
err_dots(T, T) :- \+ compound(T), !.
err_dots(T0, T) :- T0 =.. [F|As0], maplist(err_dots, As0, As), T =.. [F|As].

% Some expected errors carry an @ prefix from the suite they were transcribed
% from; quoted text keeps its @.
without_at_marks(Cs) --> "@", !, without_at_marks(Cs).
without_at_marks([''''|Cs]) --> "'", !, at_quoted(Cs).
without_at_marks([C|Cs]) --> [C], !, without_at_marks(Cs).
without_at_marks([]) --> [].

at_quoted(['''', ''''|Cs]) --> "''", !, at_quoted(Cs).
at_quoted([''''|Cs]) --> "'", !, without_at_marks(Cs).
at_quoted([C|Cs]) --> [C], !, at_quoted(Cs).
at_quoted([]) --> [].

format_atom(Fmt, Args, Atom) :- with_output_to(atom(Atom), format_write(Fmt, Args)).

format_write(Fmt, Args) :- atom_chars(Fmt, Cs), format_chars(Cs, Args).

format_chars([], []).
format_chars(['~', w|Cs], [A|As]) :- !, write(A), format_chars(Cs, As).
format_chars(['~', n|Cs], As) :- !, nl, format_chars(Cs, As).
format_chars([C|Cs], As) :- write(C), format_chars(Cs, As).

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
    atom_chars(Reason, Cs),
    phrase(lines(Lines), Cs),
    forall(member(L, Lines), (write('#   '), atom_chars(A, L), write(A), nl)).

% --- elapsed time as "S.mmm" ---

ms_to_secs_atom(Ms, Atom) :-
    Secs is Ms // 1000,
    Frac is Ms mod 1000,
    number_chars(Secs, SecsCs),
    number_chars(Frac, FracCs0),
    length(FracCs0, N),
    Pad is 3 - N,
    length(Zeros, Pad),
    maplist(=('0'), Zeros),
    append(Zeros, FracCs0, FracCs),
    append(SecsCs, ['.'|FracCs], Cs),
    atom_chars(Atom, Cs).

secs_ms(Ms) --> digits(S), ".", digits(F), !, { number_chars(Secs, S), number_chars(FMs, F), Ms is Secs * 1000 + FMs }.
secs_ms(Ms) --> digits(S), { number_chars(Secs, S), Ms is Secs * 1000 }.

% --- quad file parsing and running ---

:- dynamic(quad_stat/4).
:- dynamic(quad_record/5).

run_quad_file(File) :- run_quad_file(File, 0).

% Skip: how many tests to read but not run (directives and clauses still run).
run_quad_file(File, Skip) :-
    retractall(quad_stat(_, _, _, _)),
    assertz(quad_stat(0, 0, 0, 0)),
    retractall(quad_record(_, _, _, _, _)),
    open(File, read, S),
    read_lines(S, Lines0),
    close(S),
    maplist(uncommented, Lines0, Lines),
    phrase(quad_items(Items), Lines, _),
    run_items(Items, Skip),
    quad_stat(Total, Passed, Failed, TotalMs),
    ms_to_secs_atom(TotalMs, TotalTimeAtom),
    write('# '), write(File), write(': '), write(Total), write(' tests, '),
    write(Passed), write(' passed, '), write(Failed), write(' failed, '),
    write(TotalTimeAtom), write('s total'), nl.

read_lines(S, Lines) :-
    read_line_to_atom(S, Line),
    (   Line == end_of_file
    ->  Lines = []
    ;   atom_chars(Line, Cs),
        Lines = [Cs|Lines1],
        read_lines(S, Lines1)
    ).

% Each run of clauses between tests is a small consult: the first clause a
% block gives a predicate replaces what earlier blocks defined for it.
run_items(Items, Skip) :- run_items(Items, Skip, 0, []).

run_items([], _, _, _).
run_items([I|Is], Skip, Seen0, Block0) :-
    run_item(I, Skip, Seen0, Seen, Block0, Block),
    run_items(Is, Skip, Seen, Block).

run_item(test(Query, Answer), Skip, Seen0, Seen, _, []) :-
    Seen is Seen0 + 1,
    ( Seen =< Skip -> true ; once(run_one_test(Query, Answer, _)) ).
run_item(directive(Cs), _, Seen, Seen, _, []) :-
    strip_terminating_dot(Cs, Text),
    atom_chars(A, Text),
    (   catch((atom_to_term(A, Goal, _),
               with_output_to(atom(_), catch(call(Goal), _, true))), _, fail)
    ->  true
    ;   true
    ).
run_item(clause(Cs), _, Seen, Seen, Block0, Block) :-
    strip_terminating_dot(Cs, Text),
    atom_chars(A, Text),
    (   catch(atom_to_term(A, Term, _), _, fail),
        clause_predicate(Term, PI)
    ->  block_predicate(PI, Block0, Block),
        catch(add_clause(Term), _, true)
    ;   Block = Block0
    ).

clause_predicate((H --> _), N/A) :- !, dcg_head(H, H0), functor(H0, N, A0), A is A0 + 2.
clause_predicate((H :- _), N/A) :- !, callable(H), functor(H, N, A).
clause_predicate(H, N/A) :- callable(H), functor(H, N, A).

dcg_head((H, _), H) :- !.
dcg_head(H, H).

block_predicate(PI, Block, Block) :- memberchk(PI, Block), !.
block_predicate(N/A, Block, [N/A|Block]) :-
    functor(Skel, N, A),
    catch(retractall(Skel), _, true).

add_clause((H --> B)) :- !, '$dcg_compile'(H, B).
add_clause(Clause) :- assertz(Clause).

% --- CLI entry point: exit code 0 if all pass, 1 if any failed ---

quad_cli(File) :-
    once(run_quad_file(File)),
    quad_stat(_, _, Failed, _),
    ( Failed > 0 -> halt(1) ; halt(0) ).

% --- JUnit XML output, with crash-resume support ---

quad_suite_name(File, Suite) :-
    atom_chars(File, Cs),
    ( append(_, ['/'|Seg], Cs), \+ memberchk('/', Seg) -> true ; Seg = Cs ),
    ( append(Base, ['.'|Ext], Seg), \+ memberchk('.', Ext) -> true ; Base = Seg ),
    atom_chars(Suite, Base).

suite_path(Dir, Suite, Ext, Path) :-
    atom_chars(Dir, D),
    atom_chars(Suite, S),
    concat([D, "/", S, Ext], Cs),
    atom_chars(Path, Cs).

xml_escape(Atom, Escaped) :-
    atom_chars(Atom, Cs),
    phrase(xml_escaped(Cs), Es),
    atom_chars(Escaped, Es).

xml_escaped([]) --> [].
xml_escaped([C|Cs]) --> xml_char(C), xml_escaped(Cs).

xml_char('&') --> !, "&amp;".
xml_char('<') --> !, "&lt;".
xml_char('>') --> !, "&gt;".
xml_char('"') --> !, "&quot;".
xml_char('\n') --> !, "&#10;".
xml_char('\r') --> !, "&#13;".
xml_char(C) --> [C].

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
    suite_path(Dir, Suite, ".progress", ProgressPath),
    suite_path(Dir, Suite, ".xml.partial", PartialPath),
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

% One line at a time, so a long file never becomes one atom.
count_partial(Path, TestcaseCount, FailureCount, TotalMs) :-
    catch(
        ( open(Path, read, S),
          count_lines(S, stat(0, 0, 0), stat(TestcaseCount, FailureCount, TotalMs)),
          close(S)
        ), _, ( TestcaseCount = 0, FailureCount = 0, TotalMs = 0 )).

count_lines(S, stat(T0, F0, Ms0), Stat) :-
    read_line_to_atom(S, Line),
    (   Line == end_of_file
    ->  Stat = stat(T0, F0, Ms0)
    ;   atom_chars(Line, Cs),
        (   append("  <testcase ", _, Cs)
        ->  T1 is T0 + 1,
            ( phrase(testcase_ms(LineMs), Cs) -> Ms1 is Ms0 + LineMs ; Ms1 = Ms0 )
        ;   T1 = T0, Ms1 = Ms0
        ),
        ( append("    <failure ", _, Cs) -> F1 is F0 + 1 ; F1 = F0 ),
        count_lines(S, stat(T1, F1, Ms1), Stat)
    ).

% The time="S.mmm" attribute of a <testcase> line, in milliseconds.
testcase_ms(Ms) --> skip_to("time=\""), secs_ms(Ms), "\"", !, rest_of_line.

skip_to(Prefix, Cs0, Cs) :- append(Prefix, Cs, Cs0), !.
skip_to(Prefix, [_|Cs0], Cs) :- skip_to(Prefix, Cs0, Cs).

rest_of_line(_, []).

% Copies Path's lines verbatim to the open OutStrm, one line at a time.
stream_copy_lines(Path, OutStrm) :-
    catch((open(Path, read, S), copy_lines(S, OutStrm), close(S)), _, true).

copy_lines(S, OutStrm) :-
    read_line_to_atom(S, Line),
    (   Line == end_of_file
    ->  true
    ;   write(OutStrm, Line), nl(OutStrm), copy_lines(S, OutStrm)
    ).

% Appends a synthetic "crashed here" <testcase> naming the in-flight query,
% so the next resume attempt's Skip steps past it too.
quad_mark_crash(Suite, Dir) :-
    suite_path(Dir, Suite, ".progress", ProgressPath),
    suite_path(Dir, Suite, ".xml.partial", PartialPath),
    (   catch((open(ProgressPath, read, S), read_lines(S, Ls), close(S)), _, fail),
        join("\n", Ls, Cs0),
        trim_trailing(Cs0, Cs),
        Cs \== []
    ->  atom_chars(CrashedDisplay, Cs)
    ;   CrashedDisplay = 'unknown query (no checkpoint recorded)'
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
    suite_path(Dir, Suite, ".xml.partial", PartialPath),
    count_partial(PartialPath, Count, _Failed, _TotalMs).

% Two passes: counts need to be known before the opening tag is written,
% so pass 1 counts and pass 2 streams the body across.
quad_finalize_junit(File, Suite, Dir) :-
    suite_path(Dir, Suite, ".xml", XmlPath),
    suite_path(Dir, Suite, ".progress", ProgressPath),
    suite_path(Dir, Suite, ".xml.partial", PartialPath),
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

:- forall(member(N/A, [lines/1, line/1, digit/1, digits/1, numeric_escape/1, escape_digits/1, quad_items/1, quad_item/1, blank_lines/0, clause_text/1, clause_more/2, clause_tail/3, clause_more_lines/2, item_tail/2, answer/1, answer_more/2, answer_done/2, spaces/0, without_at_marks/1, at_quoted/1, secs_ms/1, xml_escaped/1, xml_char/1, testcase_ms/1]), '$dcg_ensure'(N, A)).

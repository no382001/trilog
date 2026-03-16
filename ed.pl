% ed.pl -- Unix line editor (ported from V7/PWB Unix ed, ~1979)
%
%   ed.         -- empty buffer
%   ed(File).   -- load File into buffer
%
% Commands: a i c d p l n = q Q f e r w k s g v m t
%
% State is stored via assert/retract:
%   ed_buf(Lines)   -- list of line atoms
%   ed_dot(N)       -- current line number
%   ed_dol(N)       -- last line number
%   ed_file(F)      -- default filename
%   ed_pat(P)       -- last compiled regex
%   ed_mark(C, N)   -- mark 'a..'z -> line number

ed :- ed('').

ed(File) :-
    ed_reset,
    assert(ed_file(File)),
    ( File \== '' ->
        ( ed_do_r(0, File) -> true ; write('?'), nl )
    ; true ),
    catch(ed_loop, ed_quit, true).

ed_reset :-
    retractall(ed_buf(_)),  retractall(ed_dot(_)),
    retractall(ed_dol(_)),  retractall(ed_file(_)),
    retractall(ed_pat(_)),  retractall(ed_mark(_,_)),
    retractall(ed_dirty),
    assert(ed_buf([])), assert(ed_dot(0)),
    assert(ed_dol(0)),  assert(ed_pat([])).

ed_reset_buf :-
    retractall(ed_buf(_)), retractall(ed_dot(_)),
    retractall(ed_dol(_)), retractall(ed_mark(_,_)),
    retractall(ed_dirty),
    assert(ed_buf([])), assert(ed_dot(0)), assert(ed_dol(0)).

ed_loop :-
    read_line_to_atom(user_input, LA),
    ( LA == end_of_file -> true
    ; atom_chars(LA, Cs),
      catch(ed_exec(Cs), ed_error, (write('?'), nl)),
      ed_loop ).

ed_exec(Cs) :-
    ed_dot(D), ed_dol(Dl),
    ed_parse_range(Cs, D, Dl, A1r, A2r, Cs1),
    skip_ws(Cs1, Cs2),
    ( Cs2 = [Cmd|Cs3] -> true ; Cmd = p, Cs3 = [] ),
    ed_do(Cmd, A1r, A2r, Cs3).

% returns A1/A2 = integer or 'none' (not given)
ed_parse_range(Cs, D, Dl, A1, A2, Rest) :-
    ( ed_parse_addr(Cs, D, Dl, First, Cs1) ->
        skip_ws(Cs1, Cs2),
        ( (Cs2 = [','|Cs3] ; Cs2 = [';'|Cs3]) ->
            ( Cs2 = [';'|_] -> ed_set_dot(First) ; true ),
            ed_dot(D2),
            ( ed_parse_addr(Cs3, D2, Dl, Second, Rest) ->
                A1 = First, A2 = Second
            ; throw(ed_error) )
        ;
            A1 = First, A2 = First, Rest = Cs2
        )
    ;
        A1 = none, A2 = none, Rest = Cs
    ).

ed_parse_addr(Cs0, D, Dl, A, Rest) :-
    skip_ws(Cs0, Cs1),
    ed_parse_base(Cs1, D, Dl, Base, Cs2),
    !,
    ed_parse_off(Cs2, D, Dl, Base, A, Rest).

ed_parse_base([C|Cs], _, _, N, Rest) :-
    is_digit(C), !,
    collect_digits([C|Cs], Ds, Rest),
    number_chars(N, Ds).
ed_parse_base(['.'|Rest], D, _, D, Rest) :- !.
ed_parse_base(['$'|Rest], _, Dl, Dl, Rest) :- !.
ed_parse_base(['/'|Cs], D, Dl, A, Rest) :- !,
    collect_to(Cs, '/', PatAtom, Rest),
    ( PatAtom \== '' -> ed_set_pat(PatAtom) ; true ),
    ed_search_fwd(D, Dl, A).
ed_parse_base(['?'|Cs], D, Dl, A, Rest) :- !,
    collect_to(Cs, '?', PatAtom, Rest),
    ( PatAtom \== '' -> ed_set_pat(PatAtom) ; true ),
    ed_search_bwd(D, Dl, A).
ed_parse_base(['\''|[C|Cs]], _, _, A, Cs) :- !,
    ( ed_mark(C, A) -> true ; throw(ed_error) ).

ed_parse_off(Cs0, D, Dl, Base, A, Rest) :-
    skip_ws(Cs0, Cs1),
    ( Cs1 = ['+'|Cs2] ->
        ( collect_digits(Cs2, Ds, Cs3), Ds \= [] ->
            number_chars(N, Ds), A1 is Base + N, R1 = Cs3
        ; A1 is Base + 1, R1 = Cs2 ),
        ed_parse_off(R1, D, Dl, A1, A, Rest)
    ; (Cs1 = ['-'|Cs2] ; Cs1 = ['^'|Cs2]) ->
        ( collect_digits(Cs2, Ds, Cs3), Ds \= [] ->
            number_chars(N, Ds), A1 is Base - N, R1 = Cs3
        ; A1 is Base - 1, R1 = Cs2 ),
        ed_parse_off(R1, D, Dl, A1, A, Rest)
    ;
        A = Base, Rest = Cs1
    ).

ed_set_dot(N) :- retractall(ed_dot(_)), assert(ed_dot(N)).
ed_set_dol(N) :- retractall(ed_dol(_)), assert(ed_dol(N)).

ed_set_pat(Atom) :-
    re_compile(Atom, Pat),
    retractall(ed_pat(_)),
    assert(ed_pat(Pat)).

% setdot: default = dot,dot
res_dot(none, none, A1, A2) :- !, ed_dot(D), A1 = D, A2 = D.
res_dot(A1, A2, A1, A2).

% setall: default = 1,$
res_all(none, none, A1, A2) :- !,
    ed_dol(Dl),
    ( Dl =:= 0 -> A1 = 0, A2 = 0 ; A1 = 1, A2 = Dl ).
res_all(A1, A2, A1, A2).

ed_check(A1, A2)    :- ( A1 > A2 -> throw(ed_error) ; true ).
ed_nonzero(A1, A2)  :-
    ed_dol(Dl),
    ( A1 < 1   -> throw(ed_error) ; true ),
    ( A2 > Dl  -> throw(ed_error) ; true ).

ed_do('a', A1r, A2r, Cs) :- !,
    newline_or_end(Cs),
    ( A2r = none -> ed_dot(A2) ; A2 = A2r ),
    ed_dol(Dl), ( A2 > Dl -> throw(ed_error) ; true ),
    ed_input_lines(Lines),
    ed_insert(A2, Lines).

ed_do('i', A1r, A2r, Cs) :- !,
    newline_or_end(Cs),
    ( A2r = none -> ed_dot(A2) ; A2 = A2r ),
    Before is max(0, A2 - 1),
    ed_input_lines(Lines),
    ed_insert(Before, Lines).

ed_do('c', A1r, A2r, Cs) :- !,
    newline_or_end(Cs),
    res_dot(A1r, A2r, A1, A2),
    ed_check(A1, A2), ed_nonzero(A1, A2),
    ed_delete(A1, A2),
    NewBefore is A1 - 1,
    ed_input_lines(Lines),
    ed_insert(NewBefore, Lines).

ed_do('d', A1r, A2r, Cs) :- !,
    newline_or_end(Cs),
    res_dot(A1r, A2r, A1, A2),
    ed_check(A1, A2), ed_nonzero(A1, A2),
    ed_delete(A1, A2),
    ed_dol(Dl),
    ( Dl >= A1 -> ed_set_dot(A1)
    ; Dl > 0   -> ed_set_dot(Dl)
    ;              ed_set_dot(0) ).

ed_do('p', A1r, A2r, Cs) :- !,
    newline_or_end(Cs),
    res_dot(A1r, A2r, A1, A2),
    ed_check(A1, A2), ed_nonzero(A1, A2),
    ed_buf(Buf),
    ed_print_range(Buf, A1, A2, false),
    ed_set_dot(A2).

ed_do('l', A1r, A2r, Cs) :- !,
    newline_or_end(Cs),
    res_dot(A1r, A2r, A1, A2),
    ed_check(A1, A2), ed_nonzero(A1, A2),
    ed_buf(Buf),
    ed_print_range(Buf, A1, A2, true),
    ed_set_dot(A2).

ed_do('n', A1r, A2r, Cs) :- !,
    newline_or_end(Cs),
    res_dot(A1r, A2r, A1, A2),
    ed_check(A1, A2), ed_nonzero(A1, A2),
    ed_buf(Buf),
    ed_print_numbered(Buf, A1, A2),
    ed_set_dot(A2).

% bare Enter: advance to next line and print it
ed_do('\n', none, none, _) :- !,
    ed_dot(D), ed_dol(Dl),
    Next is D + 1,
    ( Next > Dl -> throw(ed_error) ; true ),
    ed_buf(Buf),
    nth1(Next, Buf, Line),
    write(Line), nl,
    ed_set_dot(Next).

ed_do('=', _, A2r, Cs) :- !,
    newline_or_end(Cs),
    ( A2r = none -> ed_dol(N) ; N = A2r ),
    write(N), nl.

ed_do('q', A1r, A2r, Cs) :- !,
    ( A1r \= none -> throw(ed_error) ; true ),
    ( A2r \= none -> throw(ed_error) ; true ),
    newline_or_end(Cs),
    throw(ed_quit).

ed_do('Q', A1r, A2r, Cs) :- !,
    ( A1r \= none -> throw(ed_error) ; true ),
    ( A2r \= none -> throw(ed_error) ; true ),
    newline_or_end(Cs),
    throw(ed_quit).

ed_do('f', A1r, A2r, Cs) :- !,
    ( A1r \= none -> throw(ed_error) ; true ),
    ( A2r \= none -> throw(ed_error) ; true ),
    skip_ws(Cs, Cs1),
    ( Cs1 \= [] ->
        atom_chars(NewFile, Cs1),
        retractall(ed_file(_)), assert(ed_file(NewFile))
    ; true ),
    ed_file(F), write(F), nl.

ed_do('e', A1r, A2r, Cs) :- !,
    ( A1r \= none -> throw(ed_error) ; true ),
    ( A2r \= none -> throw(ed_error) ; true ),
    ed_parse_fname(Cs, File),
    ed_reset_buf,
    ( File \== '' ->
        ( ed_do_r(0, File) -> true ; throw(ed_error) )
    ; true ).

ed_do('E', A1r, A2r, Cs) :- !, ed_do('e', A1r, A2r, Cs).

ed_do('r', A1r, A2r, Cs) :- !,
    ed_dol(Dl),
    ( A2r = none -> A2 = Dl ; A2 = A2r ),
    ed_parse_fname(Cs, File),
    ( File = '' -> throw(ed_error) ; true ),
    ( ed_do_r(A2, File) -> true ; throw(ed_error) ).

ed_do('w', A1r, A2r, Cs) :- !,
    ed_dol(Dl),
    ( A1r = none -> A1 = 1 ; A1 = A1r ),
    ( A2r = none -> A2 = Dl ; A2 = A2r ),
    ( Dl =:= 0 -> A1e = 0 ; A1e = A1 ),
    ed_check(A1e, A2),
    ed_parse_fname(Cs, File),
    ed_buf(Buf),
    ed_write_file(Buf, A1e, A2, File),
    retractall(ed_dirty).

ed_do('k', _, A2r, Cs) :- !,
    skip_ws(Cs, [C|Cs1]),
    newline_or_end(Cs1),
    ( is_lower(C) -> true ; throw(ed_error) ),
    ( A2r = none -> ed_dot(A2) ; A2 = A2r ),
    ed_nonzero(A2, A2),
    retractall(ed_mark(C, _)),
    assert(ed_mark(C, A2)).

ed_do('s', A1r, A2r, Cs) :- !,
    res_dot(A1r, A2r, A1, A2),
    ed_check(A1, A2), ed_nonzero(A1, A2),
    ed_parse_subst(Cs, ReplAtom, GFlag, PFlag),
    ed_subst_loop(A1, A2, ReplAtom, GFlag, PFlag).

ed_do('g', A1r, A2r, Cs) :- !,
    res_all(A1r, A2r, A1, A2),
    ed_parse_gcmd(Cs, GCs),
    ed_do_global(A1, A2, GCs, true).

ed_do('v', A1r, A2r, Cs) :- !,
    res_all(A1r, A2r, A1, A2),
    ed_parse_gcmd(Cs, GCs),
    ed_do_global(A1, A2, GCs, false).

ed_do('m', A1r, A2r, Cs) :- !,
    res_dot(A1r, A2r, A1, A2),
    ed_check(A1, A2), ed_nonzero(A1, A2),
    ed_dot(D), ed_dol(Dl),
    ( ed_parse_addr(Cs, D, Dl, Dest, Rest) -> true ; throw(ed_error) ),
    newline_or_end(Rest),
    ( Dest >= A1, Dest < A2 -> throw(ed_error) ; true ),
    ed_move(A1, A2, Dest).

ed_do('t', A1r, A2r, Cs) :- !,
    res_dot(A1r, A2r, A1, A2),
    ed_check(A1, A2), ed_nonzero(A1, A2),
    ed_dot(D), ed_dol(Dl),
    ( ed_parse_addr(Cs, D, Dl, Dest, Rest) -> true ; throw(ed_error) ),
    newline_or_end(Rest),
    ed_copy(A1, A2, Dest).

ed_do('h', A1r, A2r, Cs) :- !,
    ( A1r \= none -> throw(ed_error) ; true ),
    ( A2r \= none -> throw(ed_error) ; true ),
    newline_or_end(Cs),
    ed_help.

ed_do('H', A1r, A2r, Cs) :- !, ed_do('h', A1r, A2r, Cs).

ed_do(_, _, _, _) :- throw(ed_error).

ed_help :-
    write('ed commands:'), nl,
    write('  (addr) a       -- append lines after addr'), nl,
    write('  (addr) i       -- insert lines before addr'), nl,
    write('  (addr1,addr2) c  -- change lines'), nl,
    write('  (addr1,addr2) d  -- delete lines'), nl,
    write('  (addr1,addr2) p  -- print lines'), nl,
    write('  (addr1,addr2) l  -- print lines (unambiguously)'), nl,
    write('  (addr1,addr2) n  -- print lines with line numbers'), nl,
    write('  (addr) =       -- print line number'), nl,
    write('  (addr1,addr2) s/re/repl/[g]  -- substitute'), nl,
    write('  (addr1,addr2) g/re/cmd  -- global'), nl,
    write('  (addr1,addr2) v/re/cmd  -- global (non-matching)'), nl,
    write('  (addr1,addr2) m addr  -- move lines'), nl,
    write('  (addr1,addr2) t addr  -- copy lines'), nl,
    write('  (addr) k c    -- mark line with letter c'), nl,
    write('  f [file]      -- print/set filename'), nl,
    write('  e [file]      -- edit file'), nl,
    write('  r [file]      -- read file after addr'), nl,
    write('  w [file]      -- write file'), nl,
    write('  q             -- quit (warns if unsaved)'), nl,
    write('  Q             -- quit unconditionally'), nl,
    write('  h / H         -- this help'), nl,
    write('addresses: N  .  $  /re/  ?re?  ''c  +N  -N'), nl.

ed_insert(N, Lines) :-
    ( Lines = [] ->
        ( N =:= 0 -> ed_set_dot(0) ; ed_set_dot(N) )
    ;
        ed_buf(Buf),
        list_take(Buf, N, Before, After),
        append(Lines, After, Tail),
        append(Before, Tail, NewBuf),
        retractall(ed_buf(_)), assert(ed_buf(NewBuf)),
        length(NewBuf, Dl), ed_set_dol(Dl),
        length(Lines, K),
        NewDot is N + K,
        ed_set_dot(NewDot),
        ed_shift_marks(N, K),
        assert(ed_dirty)
    ).

ed_delete(A1, A2) :-
    ed_buf(Buf),
    N0 is A1 - 1,
    list_take(Buf, N0, Before, Tail),
    Cnt is A2 - A1 + 1,
    list_take(Tail, Cnt, _, After),
    append(Before, After, NewBuf),
    retractall(ed_buf(_)), assert(ed_buf(NewBuf)),
    length(NewBuf, Dl), ed_set_dol(Dl),
    ed_unmark(A1, A2),
    NegCnt is 0 - Cnt,
    ed_shift_marks(A2, NegCnt),
    assert(ed_dirty).

% list_take(+List, +N, -FirstN, -Rest)
list_take(L, 0, [], L) :- !.
list_take([H|T], N, [H|B], R) :- N > 0, N1 is N - 1, list_take(T, N1, B, R).

ed_shift_marks(Pivot, K) :-
    findall(m(C,L), ed_mark(C,L), Ms),
    ed_shift_marks_(Ms, Pivot, K).
ed_shift_marks_([], _, _).
ed_shift_marks_([m(C,L)|Rest], Pivot, K) :-
    ( L > Pivot ->
        retractall(ed_mark(C, _)),
        L2 is L + K,
        ( L2 > 0 -> assert(ed_mark(C, L2)) ; true )
    ; true ),
    ed_shift_marks_(Rest, Pivot, K).

ed_unmark(A1, A2) :-
    findall(m(C,L), (ed_mark(C,L), L >= A1, L =< A2), Ms),
    ed_unmark_(Ms).
ed_unmark_([]).
ed_unmark_([m(C,L)|Rest]) :- retractall(ed_mark(C,L)), ed_unmark_(Rest).

ed_move(A1, A2, Dest) :-
    ed_buf(Buf),
    Cnt is A2 - A1 + 1,
    N0 is A1 - 1,
    list_take(Buf, N0, Before, Tail),
    list_take(Tail, Cnt, Moved, After),
    append(Before, After, TmpBuf),
    ( Dest > A2 -> Dest2 is Dest - Cnt ; Dest2 = Dest ),
    list_take(TmpBuf, Dest2, B2, A2b),
    append(Moved, A2b, Tail2),
    append(B2, Tail2, NewBuf),
    retractall(ed_buf(_)), assert(ed_buf(NewBuf)),
    length(NewBuf, Dl), ed_set_dol(Dl),
    NewDot is Dest2 + Cnt,
    ed_set_dot(NewDot),
    assert(ed_dirty).

ed_copy(A1, A2, Dest) :-
    ed_buf(Buf),
    findall(L, (between(A1, A2, N), nth1(N, Buf, L)), Lines),
    ed_insert(Dest, Lines).

ed_print_range(_, A1, A2, _) :- A1 > A2, !.
ed_print_range(Buf, A, A2, List) :-
    nth1(A, Buf, Line),
    ( List -> write(Line), write('$') ; write(Line) ), nl,
    A1 is A + 1,
    ed_print_range(Buf, A1, A2, List).

ed_print_numbered(_, A1, A2) :- A1 > A2, !.
ed_print_numbered(Buf, A, A2) :-
    nth1(A, Buf, Line),
    write(A), write('\t'), write(Line), nl,
    A1 is A + 1,
    ed_print_numbered(Buf, A1, A2).

ed_input_lines(Lines) :-
    read_line_to_atom(user_input, LA),
    ( LA == end_of_file -> Lines = []
    ; LA == '.'         -> Lines = []
    ; Lines = [LA|Rest], ed_input_lines(Rest) ).

ed_do_r(N, File) :-
    open(File, read, S),
    ed_read_stream(S, Lines),
    close(S),
    ed_count_chars(Lines, CC),
    ed_insert(N, Lines),
    write(CC), nl.

ed_read_stream(S, Lines) :-
    read_line_to_atom(S, LA),
    ( LA == end_of_file -> Lines = []
    ; Lines = [LA|Rest], ed_read_stream(S, Rest) ).

ed_count_chars([], 0).
ed_count_chars([L|Ls], N) :-
    atom_length(L, K), ed_count_chars(Ls, N1), N is N1 + K + 1.

ed_write_file(Buf, A1, A2, File0) :-
    ( File0 = '' -> ed_file(File) ; File = File0 ),
    ( File = '' -> throw(ed_error) ; true ),
    open(File, write, S),
    ed_write_stream(Buf, A1, A2, S),
    close(S),
    ed_count_chars_range(Buf, A1, A2, CC),
    write(CC), nl.

ed_write_stream(_, A1, A2, _) :- A1 > A2, !.
ed_write_stream(Buf, A, A2, S) :-
    nth1(A, Buf, Line),
    writeln(S, Line),
    A1 is A + 1,
    ed_write_stream(Buf, A1, A2, S).

ed_count_chars_range(_, A1, A2, 0) :- A1 > A2, !.
ed_count_chars_range(Buf, A, A2, N) :-
    nth1(A, Buf, Line), atom_length(Line, K),
    A1 is A + 1, ed_count_chars_range(Buf, A1, A2, N1),
    N is N1 + K + 1.

ed_parse_fname(Cs, File) :-
    skip_ws(Cs, Cs1),
    ( Cs1 = [] ->
        ed_file(File)
    ;
        atom_chars(File, Cs1),
        retractall(ed_file(_)), assert(ed_file(File))
    ).

ed_search_fwd(D, Dl, A) :-
    ed_pat(Pat), ( Pat = [] -> throw(ed_error) ; true ),
    Start is D + 1,
    ( ed_search_range(Start, Dl, Pat, A)   -> true
    ; ed_search_range(1, D, Pat, A)        -> true
    ; throw(ed_error) ).

ed_search_bwd(D, Dl, A) :-
    ed_pat(Pat), ( Pat = [] -> throw(ed_error) ; true ),
    Prev is D - 1,
    Next is D + 1,
    ( Prev >= 1, ed_search_bwd_range(1, Prev, Pat, A) -> true
    ; Dl > D,   ed_search_bwd_range(Next, Dl, Pat, A) -> true
    ; throw(ed_error) ).

ed_search_range(Lo, Hi, Pat, A) :-
    between(Lo, Hi, A),
    ed_buf(Buf), nth1(A, Buf, Line),
    re_exec(Pat, Line, _, _),
    !.

ed_search_bwd_range(Lo, Hi, Pat, A) :-
    between(Lo, Hi, I),
    A is Hi - I + Lo,
    ed_buf(Buf), nth1(A, Buf, Line),
    re_exec(Pat, Line, _, _),
    !.

% Parse s/pat/repl/[g][p]
ed_parse_subst([D|Cs], ReplAtom, GFlag, PFlag) :-
    collect_to(Cs, D, PatAtom, Cs1),
    ( PatAtom \== '' -> ed_set_pat(PatAtom) ; true ),
    collect_to(Cs1, D, ReplAtom, Cs2),
    ed_subst_flags(Cs2, GFlag, PFlag).

ed_subst_flags([], false, false) :- !.
ed_subst_flags([g|R], true,  P) :- !, ed_subst_flags(R, _, P).
ed_subst_flags([p|R], G,  true) :- !, ed_subst_flags(R, G, _).
ed_subst_flags(_, false, false).

ed_subst_loop(A, A2, _, _, _) :- A > A2, !.
ed_subst_loop(A, A2, ReplAtom, GFlag, PFlag) :-
    ed_pat(Pat),
    ed_buf(Buf),
    nth1(A, Buf, Line),
    ( re_exec(Pat, Line, Loc1, Loc2) ->
        atom_chars(ReplAtom, ReplCs),
        atom_chars(Line, LineCs),
        ed_apply_subst(LineCs, Loc1, Loc2, ReplCs, GFlag, Pat, NewCs),
        atom_chars(NewLine, NewCs),
        ed_replace_line(A, NewLine),
        ed_set_dot(A),
        ( PFlag -> write(NewLine), nl ; true )
    ; true ),
    A1 is A + 1,
    ed_subst_loop(A1, A2, ReplAtom, GFlag, PFlag).

% apply replacement to LineCs given match at Loc1..Loc2
% Loc1 and Loc2 are char-list suffixes of LineCs
ed_apply_subst(LineCs, Loc1, Loc2, ReplCs, GFlag, Pat, Result) :-
    append(Prefix, Loc1, LineCs),        % chars before match
    append(MatchCs, Loc2, Loc1),         % matched chars
    ed_expand_repl(ReplCs, MatchCs, Expanded),
    ( GFlag, Loc2 \= [] ->
        % try further substitutions in Loc2
        atom_chars(Loc2A, Loc2),
        ( re_exec(Pat, Loc2A, Loc1b, Loc2b) ->
            ed_apply_subst(Loc2, Loc1b, Loc2b, ReplCs, GFlag, Pat, RestCs)
        ;
            RestCs = Loc2
        )
    ;
        RestCs = Loc2
    ),
    append(Prefix, Expanded, T),
    append(T, RestCs, Result).

% expand replacement string: & = match, \n = group n (ignored for now)
ed_expand_repl([], _, []) :- !.
ed_expand_repl(['&'|Rest], Match, Out) :- !,
    ed_expand_repl(Rest, Match, Out2),
    append(Match, Out2, Out).
ed_expand_repl(['\\'|['n'|Rest]], Match, ['\n'|Out]) :- !,
    ed_expand_repl(Rest, Match, Out).
ed_expand_repl(['\\'|[C|Rest]], Match, [C|Out]) :- !,
    ed_expand_repl(Rest, Match, Out).
ed_expand_repl([C|Rest], Match, [C|Out]) :-
    ed_expand_repl(Rest, Match, Out).

ed_replace_line(N, NewLine) :-
    ed_buf(Buf),
    N0 is N - 1,
    list_take(Buf, N0, Before, [_|After]),
    append(Before, [NewLine|After], NewBuf),
    retractall(ed_buf(_)), assert(ed_buf(NewBuf)),
    assert(ed_dirty).

% parse  g/pat/cmd
ed_parse_gcmd([D|Cs], GCs) :-
    collect_to(Cs, D, PatAtom, GCs),
    ( PatAtom \== '' -> ed_set_pat(PatAtom) ; true ).

ed_do_global(A1, A2, GCs, MatchFlag) :-
    ed_pat(Pat), ( Pat = [] -> throw(ed_error) ; true ),
    ed_dol(Dl),
    ( A2 > Dl -> A2b = Dl ; A2b = A2 ),
    % Collect matching line numbers at this snapshot
    findall(N,
        ( between(A1, A2b, N),
          ed_buf(Buf), nth1(N, Buf, Line),
          ( re_exec(Pat, Line, _, _) -> MatchFlag = true ; MatchFlag = false )
        ),
        Ns),
    ed_run_global(Ns, GCs).

ed_run_global([], _) :- !.
ed_run_global([N|Rest], GCs) :-
    ed_dol(Dl),
    ( N =< Dl ->
        ed_set_dot(N),
        ( GCs = [] ->
            ed_buf(Buf), nth1(N, Buf, Line), write(Line), nl
        ;
            catch(ed_exec(GCs), ed_error, (write('?'), nl))
        )
    ; true ),
    ed_run_global(Rest, GCs).

% re_compile(+PatternAtom, -CompiledList)
re_compile(Atom, Pat) :-
    atom_chars(Atom, Cs),
    re_compile_cs(Cs, Pat).

re_compile_cs(['^'|Rest], [bol|P]) :- !, re_items(Rest, P).
re_compile_cs(Cs, P) :- re_items(Cs, P).

re_items([], []) :- !.
re_items(['$'], [dol]) :- !.
re_items(['$'|R], [dol|P]) :- !, re_items(R, P).
re_items(['\\'|['('|R]], [gbeg|P]) :- !, re_items(R, P).
re_items(['\\'|[')'|R]], [gend|P]) :- !, re_items(R, P).
re_items(['\\'|[C|R]], Item) :- !,
    ( R = ['*'|R2] -> Base = star(ch(C)), Rem = R2
    ;                  Base = ch(C),       Rem = R ),
    re_items(Rem, Tail), Item = [Base|Tail].
re_items(['['|R], Item) :- !,
    re_class(R, Set, Neg, R2),
    ( Neg = neg -> Raw = ncls(Set) ; Raw = cls(Set) ),
    ( R2 = ['*'|R3] -> Base = star(Raw), Rem = R3
    ;                    Base = Raw,       Rem = R2 ),
    re_items(Rem, Tail), Item = [Base|Tail].
re_items(['.'|R], Item) :- !,
    ( R = ['*'|R2] -> Base = star(any), Rem = R2
    ;                  Base = any,       Rem = R ),
    re_items(Rem, Tail), Item = [Base|Tail].
re_items([C|R], Item) :-
    ( R = ['*'|R2] -> Base = star(ch(C)), Rem = R2
    ;                  Base = ch(C),       Rem = R ),
    re_items(Rem, Tail), Item = [Base|Tail].

re_class(['^'|R], Set, neg, After) :- !, re_class_items(R, Set, After).
re_class(R, Set, pos, After)       :- re_class_items(R, Set, After).

re_class_items([']'|R], [], R) :- !.
re_class_items([C,'-',D|R], Set, After) :- D \= ']', !,
    char_code(C, CC), char_code(D, DC),
    findall(X, (between(CC, DC, N), char_code(X, N)), Range),
    re_class_items(R, Rest, After),
    append(Range, Rest, Set).
re_class_items([C|R], [C|Set], After) :- re_class_items(R, Set, After).

% find first match of compiled pattern in line atom
% returns Loc1, Loc2 as char-list positions
re_exec(Pat, LineAtom, Loc1, Loc2) :-
    atom_chars(LineAtom, Cs),
    ( Pat = [bol|Pat2] ->
        re_adv(Pat2, Cs, Loc2), Loc1 = Cs
    ;
        re_find(Pat, Cs, Loc1, Loc2)
    ).

re_find(Pat, [H|T], Loc1, Loc2) :-
    ( re_adv(Pat, [H|T], Loc2) -> Loc1 = [H|T]
    ; re_find(Pat, T, Loc1, Loc2) ).
re_find(Pat, [], Loc1, Loc2) :-
    re_adv(Pat, [], Loc2), Loc1 = [].

re_adv([], I, I) :- !.
re_adv([dol|P],  [], R) :- !, re_adv(P, [], R).
re_adv([gbeg|P], I, R)  :- !, re_adv(P, I, R).
re_adv([gend|P], I, R)  :- !, re_adv(P, I, R).
re_adv([ch(C)|P],   [C|R], O) :- !, re_adv(P, R, O).
re_adv([any|P],     [_|R], O) :- !, re_adv(P, R, O).
re_adv([cls(S)|P],  [C|R], O) :- !, member(C, S), re_adv(P, R, O).
re_adv([ncls(S)|P], [C|R], O) :- !, \+ member(C, S), re_adv(P, R, O).
re_adv([star(M)|P], I, O)     :- re_star(M, P, I, O).

re_star(M, P, I, O) :-
    re_collect(M, I, Matched, Rest),
    re_try_star(Matched, Rest, P, O).

re_collect(M, [C|T], [C|More], Rest) :-
    re_item_match(M, C), !, re_collect(M, T, More, Rest).
re_collect(_, Rest, [], Rest).

re_item_match(any,     _).
re_item_match(ch(C),   C).
re_item_match(cls(S),  C) :- member(C, S).
re_item_match(ncls(S), C) :- \+ member(C, S).

% try from longest prefix down (greedy)
re_try_star(Matched, Rest, P, O) :-
    length(Matched, N),
    re_star_n(N, Matched, Rest, P, O).

re_star_n(N, Matched, Rest, P, O) :-
    ( N >= 0 ->
        length(Keep, N),
        append(Keep, Give, Matched),
        append(Give, Rest, Rem),
        ( re_adv(P, Rem, O) -> true
        ; N1 is N-1, re_star_n(N1, Matched, Rest, P, O) )
    ; fail ).

skip_ws([], []) :- !.
skip_ws([' '|T],  R) :- !, skip_ws(T, R).
skip_ws(['\t'|T], R) :- !, skip_ws(T, R).
skip_ws(L, L).

newline_or_end([]) :- !.
newline_or_end(['\n'|_]) :- !.
newline_or_end([' '|T])  :- !, newline_or_end(T).
newline_or_end(['\t'|T]) :- !, newline_or_end(T).

is_digit(C) :-
    char_code(C, CC), char_code('0', Z0), char_code('9', Z9),
    CC >= Z0, CC =< Z9.
is_lower(C) :-
    char_code(C, CC), char_code('a', A), char_code('z', Z),
    CC >= A, CC =< Z.

collect_digits([], [], []) :- !.
collect_digits([C|T], [C|Ds], Rest) :- is_digit(C), !, collect_digits(T, Ds, Rest).
collect_digits(Rest, [], Rest).

% collect_to(+Cs, +Delim, -ContentAtom, -Rest)
collect_to(Cs, D, Atom, Rest) :-
    collect_to_cs(Cs, D, Content, Rest),
    atom_chars(Atom, Content).

collect_to_cs([], _, [], []) :- !.
collect_to_cs([D|Rest], D, [], Rest) :- !.
collect_to_cs(['\\'|[C|T]], D, ['\\'|[C|More]], Rest) :- !,
    collect_to_cs(T, D, More, Rest).
collect_to_cs([C|T], D, [C|More], Rest) :-
    collect_to_cs(T, D, More, Rest).

nth1(1, [H|_], H) :- !.
nth1(N, [_|T], E) :- N > 1, N1 is N-1, nth1(N1, T, E).

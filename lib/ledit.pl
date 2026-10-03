% ledit.pl -- Line editor adapted from "Prolog and Its Applications" Ch.3
%
% Usage:
%   ledit.         -- start with empty buffer
%   ledit(File).   -- load File into buffer
%
% Commands (first letter suffices):
%   add            -- read lines from keyboard (EOF to stop)
%   backward [N]   -- move N lines backward [default 1]
%   change /S1/S2/ [N] -- replace S1 with S2 (N=0: once, N>0: N lines all)
%   delete [N]     -- delete N lines from current [default 1]
%   forward [N]    -- advance N lines [default 1]
%   look /S/       -- search for string S from current line
%   print [N]      -- display N lines forward [default 1]
%   quit           -- terminate editing
%   rewind         -- go to top of file (line 0)
%   wind           -- go to bottom of file
%   yank           -- insert delete buffer after current line
%   Delete         -- delete all lines
%   get F          -- read file F, insert after current line
%   save F         -- write all lines to file F
%   help [C]       -- show help
%   (empty line)   -- re-execute previous command
%
% State stored via assert/retract:
%   l_value(line, (Above, Below))  -- gap buffer; Above/Below hold char lists
%   l_value(command, Cs)           -- last command char list
%   l_value(look, S)               -- last search char list
%   l_value(change, S1/S2)         -- last change char lists
%   l_value(delete, Texts)         -- delete buffer (char lists)

:- dynamic(l_value/2).

% --- Entry points ---

ledit :- ledit('').

ledit(File) :-
    l_initialize,
    ( File \== '' -> l_do_get_file(File), l_do([r]) ; true ),
    catch(l_loop, l_quit, true).

% --- Database helpers ---

l_set(P, V) :-
    ( retract(l_value(P, _)) -> true ; true ),
    assert(l_value(P, V)).

l_set(P, V, W) :-
    retract(l_value(P, V)), !,
    assert(l_value(P, W)).

% --- Initialization ---

l_initialize :-
    ( l_value(line, _) -> true
    ;
        l_set(line, ([top_of_file], [])),
        l_set(delete, [])
    ).

% --- Main loop (tail-recursive to avoid term/binding overflow) ---

l_loop :-
    repeat,
        l_display,
        write('LED> '), flush_output,
        read_line_to_chars(user_input, Input),
        ( Input == end_of_file -> !
        ; ( catch(l_exec(Input), l_error, (write('?'), nl)) -> true ; true ),
          fail
        ).

l_exec(Cs) :-
    l_continuation(Cs, X),
    l_do(X).

% --- Display current line ---

l_display :-
    l_value(line, ([Text|_], _)),
    ( Text == top_of_file -> write('*** top_of_file ***')
    ; put_chars(Text)
    ),
    nl.

% --- Continuation ---

l_continuation([], X) :- !,
    ( l_value(command, X) -> true
    ; write('?'), nl, fail
    ).
l_continuation(X, X) :- l_set(command, X).

% --- Utilities ---

l_for(0, _) :- !.
l_for(N, P) :-
    call(P), !,
    N1 is N - 1,
    l_for(N1, P).
l_for(_, _).

% --- Char list helpers ---

l_reverse([], Acc, Acc).
l_reverse([H|T], Acc, R) :- l_reverse(T, [H|Acc], R).

l_concat([], B, B) :- !.
l_concat([H|A], B, [H|C]) :- l_concat(A, B, C).

l_starts_with(Rest, [], Rest).
l_starts_with([H|T1], [H|T2], Rest) :-
    l_starts_with(T1, T2, Rest).

l_contains(_, []) :- !.
l_contains(Text, Sub) :- l_split_at(Text, Sub, _, _), !.

l_split_at(Text, Sub, [], After) :-
    l_starts_with(Text, Sub, After), !.
l_split_at([H|T], Sub, [H|Before], After) :-
    l_split_at(T, Sub, Before, After).

% --- Argument parsing ---

l_skip_spaces([' '|T], Rest) :- !, l_skip_spaces(T, Rest).
l_skip_spaces(L, L).

l_number([], 1) :- !.
l_number(Cs, N) :- l_number_acc(Cs, 0, N).

l_number_acc([], N, N) :- !.
l_number_acc([C|L], Acc, N) :-
    char_code(C, Code),
    Code >= 48, Code =< 57, !,
    Acc1 is Acc * 10 + Code - 48,
    l_number_acc(L, Acc1, N).
l_number_acc(_, _, _) :-
    write('?'), nl, fail.

l_collect_to([], _, [], []).
l_collect_to([C|Rest], C, [], Rest) :- !.
l_collect_to([C|Rest], Delim, [C|Acc], Tail) :-
    l_collect_to(Rest, Delim, Acc, Tail).

% --- Movement ---

l_backward :-
    l_set(line, ([X, Y|L1], L2), ([Y|L1], [X|L2])).

l_forward :-
    l_set(line, (L1, [X|L2]), ([X|L1], L2)).

% --- Commands ---

% quit
l_do([q|_]) :- !, retractall(l_value(_, _)), throw(l_quit).

% add
l_do([a|_]) :- !,
    l_add_lines.

l_add_lines :-
    write(': '), flush_output,
    read_line_to_chars(user_input, Cs),
    ( Cs == end_of_file -> true
    ; Cs == "." -> true
    ; l_set(line, (L1, L2), ([Cs|L1], L2)),
      l_add_lines
    ).

% backward
l_do([b|L]) :- !,
    l_skip_spaces(L, Rest),
    l_number(Rest, N),
    l_for(N, l_backward).

% forward
l_do([f|L]) :- !,
    l_skip_spaces(L, Rest),
    l_number(Rest, N),
    l_for(N, l_forward).

% print
l_do([p|L]) :- !,
    l_skip_spaces(L, Rest),
    l_number(Rest, N),
    l_for(N, (l_forward, l_display)).

% rewind
l_do([r|_]) :- !,
    l_value(line, ([X, Y|L1], L2)),
    l_reverse(L1, [Y, X|L2], [_|L3]),
    l_set(line, ([top_of_file], L3)).

% wind
l_do([w|_]) :- !,
    l_value(line, (L1, [X|L2])),
    l_reverse(L2, [X|L1], L3),
    l_set(line, (L3, [])).

% delete (top-of-file check)
l_do([d|_]) :-
    l_value(line, ([top_of_file], _)), !,
    write('?'), nl.
l_do([d|L]) :- !,
    l_skip_spaces(L, Rest),
    l_number(Rest, N),
    l_deletebuf,
    l_for(N, l_delete).

l_delete :-
    l_set(line, ([X|L], []), (L, [])), !,
    l_set(delete, D, [X|D]), fail.
l_delete :-
    l_set(line, ([X|L1], [Y|L2]), ([Y|L1], L2)),
    l_set(delete, D, [X|D]).

l_deletebuf :-
    l_set(delete, []).

% Delete all
l_do(['D'|_]) :- !,
    l_deletebuf,
    l_deleteall.

l_deleteall :-
    l_value(line, (L1, L2)),
    l_reverse(L1, L2, [_|L3]),
    l_reverse(L3, [], L4),
    l_set(delete, L4),
    l_set(line, ([top_of_file], [])), !.

% yank
l_do([y|_]) :-
    l_value(delete, []), !,
    write('? empty delete buffer'), nl.
l_do([y|_]) :- !,
    l_value(delete, D),
    l_yank(D).

l_yank([]) :- !.
l_yank([Text|D]) :-
    l_yank(D), !,
    l_set(line, (L1, L2), ([Text|L1], L2)).

% look
l_do([l|L]) :- !,
    l_skip_spaces(L, L1),
    l_lookstr(L1, S),
    l_look(S).

l_lookstr([], S) :- !,
    ( l_value(look, S) -> true
    ; write('?'), nl, fail
    ).
l_lookstr([Delim|L], S) :-
    l_collect_to(L, Delim, S, _), !,
    l_set(look, S).
l_lookstr(_, _) :- write('?'), nl, fail.

l_look(S) :-
    repeat,
        ( \+ l_forward ->
            !, write('? not found'), nl, fail
        ; l_value(line, ([Text|_], _)),
          ( l_contains(Text, S) -> ! ; fail )
        ).

% change
l_do([c|L]) :- !,
    l_skip_spaces(L, L1),
    l_changestr(L1, S1, S2, N),
    l_change(S1, S2, N).

l_changestr([], S1, S2, 0) :- !,
    ( l_value(change, S1/S2) -> true
    ; write('?'), nl, fail
    ).
l_changestr([C|Rest], S1, S2, N) :-
    char_code(C, Code), Code >= 49, Code =< 57, !,
    ( l_value(change, S1/S2) -> true
    ; write('?'), nl, fail
    ),
    l_number([C|Rest], N).
l_changestr([Delim|L], S1, S2, N) :-
    l_collect_to(L, Delim, S1, Rest1),
    l_collect_to(Rest1, Delim, S2, Rest2), !,
    l_skip_spaces(Rest2, Rest3),
    ( Rest3 = [] -> N = 0 ; l_number(Rest3, N) ),
    l_set(change, S1/S2).
l_changestr(_, _, _, _) :-
    write('?'), nl, fail.

l_change(S1, S2, 0) :- !, l_change_once(S1, S2).
l_change(S1, S2, N) :-
    l_for(N, (l_changes(S1, S2), l_forward)),
    l_backward.

l_change_once(S1, S2) :-
    l_value(line, ([Text|Rest], Below)),
    Text \== top_of_file, !,
    ( l_split_at(Text, S1, Prefix, Suffix) ->
        l_concat(Prefix, S2, Tmp),
        l_concat(Tmp, Suffix, NewText),
        l_set(line, ([Text|Rest], Below), ([NewText|Rest], Below))
    ; true
    ).
l_change_once(_, _) :-
    write('?'), nl.

l_changes(S1, S2) :-
    l_value(line, ([Text|Rest], Below)),
    Text \== top_of_file, !,
    l_replace_all(Text, S1, S2, NewText),
    ( Text \== NewText ->
        l_set(line, ([Text|Rest], Below), ([NewText|Rest], Below))
    ; true
    ).
l_changes(_, _).

l_replace_all(Text, S1, S2, Result) :-
    ( l_split_at(Text, S1, Prefix, Suffix) ->
        l_replace_all(Suffix, S1, S2, RestResult),
        l_concat(Prefix, S2, Tmp),
        l_concat(Tmp, RestResult, Result)
    ; Result = Text
    ), !.

% get (read file)
l_do([g|L]) :- !,
    l_skip_spaces(L, L1),
    ( L1 \== [] ->
        atom_chars(Fname, L1),
        l_do_get_file(Fname)
    ; write('?'), nl
    ).

l_do_get_file(Fname) :-
    catch(
        ( open(Fname, read, S),
          l_read_file(S)
        ),
        _,
        ( write('? cannot read '), write(Fname), nl )
    ).

l_read_file(S) :-
    l_set(read_stream, S),
    l_read_loop.

l_read_loop :-
    l_value(read_stream, S),
    read_line_to_chars(S, Cs),
    ( Cs == end_of_file ->
        close(S),
        ( retract(l_value(read_stream, _)) -> true ; true )
    ; l_set(line, (L1, L2), ([Cs|L1], L2)),
      l_read_loop
    ).

% save
l_do([s|L]) :- !,
    l_skip_spaces(L, L1),
    ( L1 \== [] ->
        atom_chars(Fname, L1),
        l_do_save_file(Fname)
    ; write('?'), nl
    ).

l_do_save_file(Fname) :-
    catch(
        ( open(Fname, write, S),
          l_listing(S),
          close(S),
          write(Fname), write(' saved.'), nl
        ),
        _,
        ( write('? cannot write '), write(Fname), nl )
    ).

l_listing(S) :-
    l_value(line, (L1, L2)),
    l_reverse(L1, L2, [_|L3]),
    l_list_lines(L3, S).

l_list_lines([], _).
l_list_lines([Text|Rest], S) :-
    put_chars(S, Text),
    nl(S),
    l_list_lines(Rest, S).

% help
l_do([h|_]) :- !,
    write('Commands (first letter suffices):'), nl,
    write('  a         add lines (. to stop)'), nl,
    write('  b [N]     backward N lines'), nl,
    write('  c /S1/S2/ [N]  change S1->S2'), nl,
    write('  d [N]     delete N lines'), nl,
    write('  f [N]     forward N lines'), nl,
    write('  l /S/     look for string S'), nl,
    write('  p [N]     print N lines'), nl,
    write('  q         quit'), nl,
    write('  r         rewind to top'), nl,
    write('  w         wind to bottom'), nl,
    write('  y         yank from delete buffer'), nl,
    write('  D         Delete all lines'), nl,
    write('  g FILE    get (read) file'), nl,
    write('  s FILE    save to file'), nl,
    write('  h         this help'), nl.

% otherwise
l_do(_) :- write('?'), nl.

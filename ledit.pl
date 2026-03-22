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
%   l_value(line, (Above, Below))  -- Above = [cur,prev,...,0], Below = [next,...]
%   l_value(newnum, N)             -- next line tag
%   l_value(command, Cs)           -- last command char list
%   l_value(look, S)               -- last search atom
%   l_value(change, S1/S2)         -- last change atoms
%   l_value(delete, Tags)          -- delete buffer
%   l_line(Tag, Text)              -- line text (atom)

% --- Entry points ---

ledit :- ledit('').

ledit(File) :-
    l_initialize,
    ( File \== '' -> l_do_get_file(File), l_do([r]) ; true ),
    l_loop.

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
        l_set(line, ([0], [])),
        assert(l_line(0, '*** top_of_file ***')),
        l_set(newnum, 1),
        l_set(delete, [])
    ).

% --- Main loop (tail-recursive to avoid term/binding overflow) ---

l_loop :-
    l_display,
    write('LED> '), flush_output,
    read_line_to_atom(user_input, LA),
    ( LA == end_of_file -> true
    ; atom_chars(LA, Cs),
      ( catch(l_exec(Cs), l_error, (write('?'), nl)) -> true ; true ),
      l_loop
    ).

l_exec(Cs) :-
    l_continuation(Cs, X),
    l_do(X).

% --- Display current line ---

l_display :-
    l_value(line, ([N|_], _)),
    l_line(N, Text),
    write(Text), nl.

% --- Continuation ---

l_continuation([], X) :- !,
    ( l_value(command, X) -> true
    ; write('?'), nl, fail
    ).
l_continuation(X, X) :- l_set(command, X).

% --- Utilities ---

l_member(E, [E|_]).
l_member(E, [_|L]) :- l_member(E, L).

l_reverse([], L, L) :- !.
l_reverse([X|L1], L2, L3) :- l_reverse(L1, [X|L2], L3).

l_for(0, _) :- !.
l_for(N, P) :-
    call(P), !,
    N1 is N - 1,
    l_for(N1, P).
l_for(_, _).

l_newnum(N) :-
    l_value(newnum, N),
    N1 is N + 1,
    l_set(newnum, N1), !.

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
l_do([q|_]) :- !.

% add
l_do([a|_]) :- !,
    l_add_lines.

l_add_lines :-
    write(': '), flush_output,
    read_line_to_atom(user_input, LA),
    ( LA == end_of_file -> true
    ; LA == '.' -> true
    ; l_newnum(N),
      l_set(line, (L1, L2), ([N|L1], L2)),
      assert(l_line(N, LA)),
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
    l_set(line, ([0], L3)).

% wind
l_do([w|_]) :- !,
    l_value(line, (L1, [X|L2])),
    l_reverse(L2, [X|L1], L3),
    l_set(line, (L3, [])).

% delete (line 0 check)
l_do([d|_]) :-
    l_value(line, ([0], _)), !,
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
    l_set(delete, D, []),
    l_retract_lines(D).

l_retract_lines([]).
l_retract_lines([X|Rest]) :-
    ( retract(l_line(X, _)) -> true ; true ),
    l_retract_lines(Rest).

% Delete all
l_do(['D'|_]) :- !,
    l_deletebuf,
    l_deleteall.

l_deleteall :-
    l_value(line, (L1, L2)),
    l_reverse(L1, L2, [_|L3]),
    l_reverse(L3, [], L4),
    l_set(delete, L4),
    l_set(line, ([0], [])), !.

% yank
l_do([y|_]) :-
    l_value(delete, []), !,
    write('? empty delete buffer'), nl.
l_do([y|_]) :- !,
    l_value(delete, D),
    l_yank(D).

l_yank([]) :- !.
l_yank([X|D]) :-
    l_yank(D), !,
    l_line(X, Text),
    l_newnum(N),
    l_set(line, (L1, L2), ([N|L1], L2)),
    assert(l_line(N, Text)).

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
    l_collect_to(L, Delim, Schars, _), !,
    atom_chars(S, Schars),
    l_set(look, S).
l_lookstr(_, _) :- write('?'), nl, fail.

l_look(S) :-
    ( \+ l_forward ->
        write('? not found'), nl, fail
    ; l_value(line, ([N|_], _)),
      l_line(N, Text),
      ( sub_atom(Text, _, _, _, S) -> true
      ; l_look(S)
      )
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
    l_collect_to(L, Delim, S1chars, Rest1),
    l_collect_to(Rest1, Delim, S2chars, Rest2), !,
    atom_chars(S1, S1chars),
    atom_chars(S2, S2chars),
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
    l_value(line, ([N|_], _)), N \== 0, !,
    l_line(N, Text),
    ( sub_atom(Text, Before, _, After, S1) ->
        sub_atom(Text, 0, Before, _, Prefix),
        atom_length(Text, TLen),
        Start is TLen - After,
        sub_atom(Text, Start, After, _, Suffix),
        atom_concat(Prefix, S2, Tmp),
        atom_concat(Tmp, Suffix, NewText),
        retract(l_line(N, _)), !,
        assert(l_line(N, NewText))
    ; true
    ).
l_change_once(_, _) :-
    write('?'), nl.

l_changes(S1, S2) :-
    l_value(line, ([N|_], _)), N \== 0, !,
    l_line(N, Text),
    l_replace_all(Text, S1, S2, NewText),
    ( Text \== NewText ->
        retract(l_line(N, _)), !,
        assert(l_line(N, NewText))
    ; true
    ).
l_changes(_, _).

l_replace_all(Text, S1, S2, Result) :-
    ( sub_atom(Text, Before, _, After, S1) ->
        sub_atom(Text, 0, Before, _, Prefix),
        atom_length(Text, TLen),
        Start is TLen - After,
        sub_atom(Text, Start, After, _, Rest),
        l_replace_all(Rest, S1, S2, RestResult),
        atom_concat(Prefix, S2, Tmp),
        atom_concat(Tmp, RestResult, Result)
    ; Result = Text
    ).

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
          l_read_file(S),
          close(S)
        ),
        _,
        ( write('? cannot read '), write(Fname), nl )
    ).

l_read_file(S) :-
    read_line_to_atom(S, LA),
    ( LA == end_of_file -> true
    ; l_newnum(N),
      l_set(line, (L1, L2), ([N|L1], L2)),
      assert(l_line(N, LA)),
      l_read_file(S)
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
    l_list_tags(L3, S).

l_list_tags([], _).
l_list_tags([N|Rest], S) :-
    l_line(N, Text),
    writeln(S, Text),
    l_list_tags(Rest, S).

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

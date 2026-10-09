% ledit.pl -- Line editor adapted from "Prolog and Its Applications" Ch.3
%
% Usage:
%   ledit.                  -- start with empty buffer
%   ledit(File).            -- load File into buffer
%   ledit(File, Commands).  -- run Commands on File without prompting, e.g.
%       ledit('notes.txt', ['l /TODO/', 'c /TODO/DONE/', 's notes.txt'])
%     After `add`, the following commands are the lines to add, up to '.'.
%
% Commands (any prefix of the name works, so `f 3` and `forward 3` are the same):
%   add            -- read lines from keyboard (. or EOF to stop)
%   backward [N]   -- move N lines backward [default 1]
%   change /S1/S2/ [N] -- replace S1 with S2 (no N: first match in this line,
%                     N: every match in N lines); `change [N]` repeats the last
%   delete [N]     -- delete N lines from current [default 1]
%   forward [N]    -- advance N lines [default 1]
%   look /S/       -- search forward for S; `look` repeats the last search
%   print [N]      -- display N lines forward [default 1]
%   quit           -- terminate editing
%   rewind         -- go to top of file (line 0)
%   wind           -- go to bottom of file
%   yank           -- insert delete buffer after current line
%   Delete         -- delete all lines
%   get F          -- read file F, insert after current line
%   save F         -- write all lines to file F
%   help           -- show help
%   (empty line)   -- re-execute previous command
%

%!  ledit is det.
ledit :-
    ed_new(S),
    ed_session(interactive, S, _).

%!  ledit(+File) is det.
ledit(File) :-
    ledit(File, interactive).

%!  ledit(+File, +Commands) is det.
%   Commands is a list of command lines (atoms or char lists), or
%   `interactive` to read them from the terminal.
ledit(File, Commands) :-
    ed_new(S0),
    ed_get(File, S0, S1),
    ed_rewind(S1, S),
    ed_session(Commands, S, _).

%!  ed_new(-State) is det.
ed_new(ed([], [], [], memo(none, none, none))).


% --- The session ---

%!  ed_session(+Input, +State0, -State) is det.
%   Runs commands until `quit` or the end of Input, which is `interactive`
%   or a list of command lines.
ed_session(Input0, S0, S) :-
    ed_next_line(Input0, command, S0, Line, Input),
    (   Line == end_of_file
    ->  S = S0
    ;   ed_parse_line(Line, S0, Command, S1),
        (   Command == quit
        ->  S = S1
        ;   Command == add
        ->  ed_add(Input, S1, S2, Input1),
            ed_session(Input1, S2, S)
        ;   ed_run(Command, S1, S2),
            ed_session(Input, S2, S)
        )
    ).

%!  ed_add(+Input0, +State0, -State, -Input) is det.
%   Inserts lines from Input up to `.` or its end.
ed_add(Input0, S0, S, Input) :-
    ed_next_line(Input0, add, S0, Line, Input1),
    (   ( Line == end_of_file ; Line == ['.'] )
    ->  S = S0,
        Input = Input1
    ;   ed_insert([Line], S0, S1),
        ed_add(Input1, S1, S, Input)
    ).

%!  ed_next_line(+Input0, +Mode, +State, -Line, -Input) is det.
%   On the terminal, a command prompt shows the current line first.
ed_next_line(interactive, Mode, S, Line, interactive) :-
    (   Mode == command
    ->  ed_display(S),
        write('LED> ')
    ;   write(': ')
    ),
    flush_output,
    read_line_to_chars(user_input, Line).
ed_next_line([], _, _, end_of_file, []).
ed_next_line([Text|Texts], _, _, Line, Texts) :-
    (   ( Text == [] ; Text = [_|_] )
    ->  Line = Text
    ;   atom_chars(Text, Line)
    ).

%!  ed_parse_line(+Line, +State0, -Command, -State) is det.
%   An empty line repeats the previous command; anything that doesn't parse
%   becomes `bad`.
ed_parse_line(Line, S0, Command, S) :-
    S0 = ed(A, B, D, memo(Last, Look, Change)),
    (   phrase(ed_blanks, Line)
    ->  ( Last == none -> Command = bad ; Command = Last ),
        S = S0
    ;   once(phrase(ed_command(Command), Line))
    ->  S = ed(A, B, D, memo(Command, Look, Change))
    ;   Command = bad,
        S = S0
    ).


% --- Commands ---

%!  ed_run(+Command, +State0, -State) is det.
ed_run(bad, S, S) :-
    ed_complain.
ed_run(forward(N), S0, S) :-
    ed_repeat(N, ed_forward, S0, S).
ed_run(backward(N), S0, S) :-
    ed_repeat(N, ed_backward, S0, S).
ed_run(print(N), S0, S) :-
    ed_repeat(N, ed_print_next, S0, S).
ed_run(rewind, S0, S) :-
    ed_rewind(S0, S).
ed_run(wind, S0, S) :-
    ed_wind(S0, S).
ed_run(delete(N), S0, S) :-
    (   ed_delete(N, S0, S1)
    ->  S = S1
    ;   ed_complain,
        S = S0
    ).
ed_run(delete_all, S0, S) :-
    ed_delete_all(S0, S).
ed_run(yank, S0, S) :-
    (   ed_yank(S0, S1)
    ->  S = S1
    ;   write('? empty delete buffer'), nl,
        S = S0
    ).
ed_run(look(Sub), S0, S) :-
    S0 = ed(A, B, D, memo(C, _, Ch)),
    ed_run_look(Sub, ed(A, B, D, memo(C, Sub, Ch)), S).
ed_run(look_again, S0, S) :-
    S0 = ed(_, _, _, memo(_, Sub, _)),
    (   Sub == none
    ->  ed_complain,
        S = S0
    ;   ed_run_look(Sub, S0, S)
    ).
ed_run(change(From, To, N), S0, S) :-
    S0 = ed(A, B, D, memo(C, L, _)),
    ed_run_change(From, To, N, ed(A, B, D, memo(C, L, From/To)), S).
ed_run(change_again(N), S0, S) :-
    S0 = ed(_, _, _, memo(_, _, Change)),
    (   Change = From/To
    ->  ed_run_change(From, To, N, S0, S)
    ;   ed_complain,
        S = S0
    ).
ed_run(get(File), S0, S) :-
    ed_get(File, S0, S).
ed_run(save(File), S, S) :-
    ed_save(File, S).
ed_run(help, S, S) :-
    ed_help.

ed_run_look(Sub, S0, S) :-
    (   ed_look(Sub, S0, S1)
    ->  S = S1
    ;   write('? not found'), nl,
        S = S0
    ).

ed_run_change(From, To, N, S0, S) :-
    (   ed_change(From, To, N, S0, S1)
    ->  S = S1
    ;   ed_complain,
        S = S0
    ).

ed_complain :-
    write('?'), nl.


% --- Editing, as relations between states ---

%!  ed_forward(+State0, -State) is semidet.
ed_forward(ed(A, [L|B], D, M), ed([L|A], B, D, M)).

%!  ed_backward(+State0, -State) is semidet.
ed_backward(ed([L|A], B, D, M), ed(A, [L|B], D, M)).

%!  ed_repeat(+N, :Step, +State0, -State) is det.
%   Steps N times, or until Step fails.
ed_repeat(N, Step, S0, S) :-
    (   N > 0,
        call(Step, S0, S1)
    ->  N1 is N - 1,
        ed_repeat(N1, Step, S1, S)
    ;   S = S0
    ).

ed_print_next(S0, S) :-
    ed_forward(S0, S),
    ed_display(S).

%!  ed_lines(+State, -Lines) is det.
%   All lines of the buffer, top to bottom.
ed_lines(ed(A, B, _, _), Lines) :-
    reverse(A, Top),
    append(Top, B, Lines).

%!  ed_rewind(+State0, -State) is det.
ed_rewind(S0, ed([], Lines, D, M)) :-
    S0 = ed(_, _, D, M),
    ed_lines(S0, Lines).

%!  ed_wind(+State0, -State) is det.
ed_wind(S0, ed(Above, [], D, M)) :-
    S0 = ed(_, _, D, M),
    ed_lines(S0, Lines),
    reverse(Lines, Above).

%!  ed_insert(+Lines, +State0, -State) is det.
%   Lines go after the current line; the last of them becomes current.
ed_insert(Lines, ed(A, B, D, M), ed(A1, B, D, M)) :-
    reverse(Lines, New),
    append(New, A, A1).

%!  ed_delete(+N, +State0, -State) is semidet.
%   Deletes the current line and up to N-1 after it into the delete buffer.
%   Fails at the top of the file.
ed_delete(N, ed([L|A], B, _, M), S) :-
    N1 is N - 1,
    ed_take(N1, B, Taken, Rest),
    (   Rest = [Next|Rest1]
    ->  S = ed([Next|A], Rest1, [L|Taken], M)
    ;   S = ed(A, [], [L|Taken], M)
    ).

%!  ed_take(+N, +List, -Prefix, -Rest) is det.
%   Prefix is the first N elements of List, or all of them if it is shorter.
ed_take(N, [X|Xs], [X|Prefix], Rest) :-
    N > 0,
    !,
    N1 is N - 1,
    ed_take(N1, Xs, Prefix, Rest).
ed_take(_, Rest, [], Rest).

%!  ed_delete_all(+State0, -State) is det.
ed_delete_all(S0, ed([], [], Lines, M)) :-
    S0 = ed(_, _, _, M),
    ed_lines(S0, Lines).

%!  ed_yank(+State0, -State) is semidet.
%   Fails when the delete buffer is empty.
ed_yank(S0, S) :-
    S0 = ed(_, _, [D|Ds], _),
    ed_insert([D|Ds], S0, S).

%!  ed_look(+Sub, +State0, -State) is semidet.
%   Moves to the first line after the current one that contains Sub.
ed_look(Sub, ed(A, B, D, M), ed([L|A1], B1, D, M)) :-
    append(Skipped, [L|B1], B),
    ed_contains(L, Sub),
    !,
    reverse(Skipped, RSkipped),
    append(RSkipped, A, A1).

%!  ed_change(+From, +To, +N, +State0, -State) is semidet.
%   N = 0 replaces the first From in the current line; N > 0 replaces every
%   From in N lines and leaves the last of them current. Fails at the top.
ed_change(From, To, 0, ed([L|A], B, D, M), ed([L1|A], B, D, M)) :-
    !,
    ed_replace_first(L, From, To, L1).
ed_change(From, To, N, ed([L|A], B, D, M), S) :-
    ed_replace_all(L, From, To, L1),
    (   N > 1,
        B = [Next|B1]
    ->  N1 is N - 1,
        ed_change(From, To, N1, ed([Next, L1|A], B1, D, M), S)
    ;   S = ed([L1|A], B, D, M)
    ).


% --- Text ---

%!  ed_contains(+Text, +Sub) is semidet.
ed_contains(Text, Sub) :-
    once(phrase((ed_seq(_), ed_seq(Sub), ed_seq(_)), Text)).

%!  ed_replace_first(+Text, +From, +To, -New) is det.
ed_replace_first(Text, From, To, New) :-
    (   From \== [],
        once(phrase((ed_seq(Before), ed_seq(From), ed_seq(After)), Text))
    ->  phrase((ed_seq(Before), ed_seq(To), ed_seq(After)), New)
    ;   New = Text
    ).

%!  ed_replace_all(+Text, +From, +To, -New) is det.
ed_replace_all(Text, From, To, New) :-
    (   From \== [],
        once(phrase((ed_seq(Before), ed_seq(From), ed_seq(After)), Text))
    ->  ed_replace_all(After, From, To, After1),
        phrase((ed_seq(Before), ed_seq(To), ed_seq(After1)), New)
    ;   New = Text
    ).


% --- Command syntax ---

%!  ed_command(-Command)// is semidet.
ed_command(Command) -->
    ed_blanks,
    ed_letters(Word),
    { ed_command_name(Word, Name) },
    ed_args(Name, Command),
    ed_blanks.

ed_command_name(Word, Name) :-
    Word = [_|_],
    member(Name, [add, backward, change, delete, forward, get, help, look,
                  print, quit, rewind, save, wind, yank, 'Delete']),
    atom_chars(Name, Chars),
    append(Word, _, Chars),
    !.

ed_args(add, add) --> [].
ed_args(quit, quit) --> [].
ed_args(rewind, rewind) --> [].
ed_args(wind, wind) --> [].
ed_args(yank, yank) --> [].
ed_args(help, help) --> ed_seq(_).
ed_args('Delete', delete_all) --> [].
ed_args(forward, forward(N)) --> ed_count(1, N).
ed_args(backward, backward(N)) --> ed_count(1, N).
ed_args(print, print(N)) --> ed_count(1, N).
ed_args(delete, delete(N)) --> ed_count(1, N).
ed_args(look, look(Sub)) --> ed_blanks, ed_delimited(Sub).
ed_args(look, look_again) --> [].
ed_args(change, change(From, To, N)) -->
    ed_blanks,
    [Delim],
    { \+ ed_digit(Delim), Delim \== ' ' },
    ed_seq(From),
    [Delim],
    ed_seq(To),
    ( [Delim] ; [] ),
    ed_count(0, N).
ed_args(change, change_again(N)) --> ed_count(0, N).
ed_args(get, get(File)) --> ed_blanks, ed_file_name(File).
ed_args(save, save(File)) --> ed_blanks, ed_file_name(File).

ed_count(_, N) --> ed_blanks, ed_digits(Ds), { number_chars(N, Ds) }.
ed_count(Default, Default) --> [].

ed_delimited(S) --> [Delim], { Delim \== ' ' }, ed_seq(S), ( [Delim] ; [] ).

ed_file_name(File) --> ed_seq([C|Cs]), { atom_chars(File, [C|Cs]) }.

ed_letters([C|Cs]) --> [C], { ed_letter(C) }, ed_letters(Cs).
ed_letters([]) --> [].

ed_digits([D|Ds]) --> [D], { ed_digit(D) }, ed_digits_rest(Ds).

ed_digits_rest([D|Ds]) --> [D], { ed_digit(D) }, ed_digits_rest(Ds).
ed_digits_rest([]) --> [].

ed_blanks --> [' '], ed_blanks.
ed_blanks --> [].

ed_seq([]) --> [].
ed_seq([X|Xs]) --> [X], ed_seq(Xs).

ed_letter(C) :-
    char_code(C, Code),
    (   Code >= 0'a, Code =< 0'z
    ;   Code >= 0'A, Code =< 0'Z
    ),
    !.

ed_digit(C) :-
    char_code(C, Code),
    Code >= 0'0,
    Code =< 0'9.


% --- I/O ---

ed_display(ed([], _, _, _)) :-
    write('*** top_of_file ***'),
    nl.
ed_display(ed([L|_], _, _, _)) :-
    put_chars(L),
    nl.

%!  ed_get(+File, +State0, -State) is det.
ed_get(File, S0, S) :-
    catch(ed_read_file_lines(File, Lines), _, Lines = none),
    (   Lines == none
    ->  write('? cannot read '), write(File), nl,
        S = S0
    ;   ed_insert(Lines, S0, S)
    ).

ed_read_file_lines(File, Lines) :-
    open(File, read, Stream),
    ed_read_stream_lines(Stream, Lines),
    close(Stream).

ed_read_stream_lines(Stream, Lines) :-
    read_line_to_chars(Stream, Line),
    (   Line == end_of_file
    ->  Lines = []
    ;   Lines = [Line|Rest],
        ed_read_stream_lines(Stream, Rest)
    ).

%!  ed_save(+File, +State) is det.
ed_save(File, S) :-
    ed_lines(S, Lines),
    catch(ed_write_file_lines(File, Lines), _, fail),
    !,
    write(File), write(' saved.'), nl.
ed_save(File, _) :-
    write('? cannot write '), write(File), nl.

ed_write_file_lines(File, Lines) :-
    open(File, write, Stream),
    forall(member(L, Lines), (put_chars(Stream, L), nl(Stream))),
    close(Stream).

ed_help :-
    forall(
        member(Text, [
            'Commands (any prefix of the name works):',
            '  add             add lines (. to stop)',
            '  backward [N]    backward N lines',
            '  change /S1/S2/ [N]  change S1 to S2',
            '  delete [N]      delete N lines',
            '  forward [N]     forward N lines',
            '  look /S/        look for string S',
            '  print [N]       print N lines',
            '  quit            quit',
            '  rewind          rewind to top',
            '  wind            wind to bottom',
            '  yank            yank from delete buffer',
            '  Delete          delete all lines',
            '  get FILE        get (read) file',
            '  save FILE       save to file',
            '  help            this help'
        ]),
        (write(Text), nl)).

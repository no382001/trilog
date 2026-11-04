:- '$builtin_file'.

:- module(editline, [edit_line/3,
                     add_history/1,
                     edit_keys/4]).

:- use_module(library(dcgs)).

:- dynamic(history/1).

%!  edit_line(+Prompt, +Initial, -Line) is semidet.
%   Reads a line from the terminal with editing and history; Initial is the
%   codes the line starts with. Fails at end of input. The host must have
%   switched the terminal to raw mode; this switches it back.
edit_line(Prompt, Initial, Line) :-
    findall(H, history(H), Hs0),
    reverse(Hs0, Hs),
    reverse(Initial, Before),
    catch(edit(Prompt, line(Before, [], Hs, []), Result), E,
          ( '$tl_raw'(0), throw(E) )),
    '$tl_raw'(0),
    nl,
    Result = line(Cs),
    atom_codes(Line, Cs).

%!  add_history(+Text) is det.
%   Text becomes the newest history entry, its line breaks made spaces, so a
%   query that spanned lines comes back as one; the same text twice running
%   is kept once.
add_history(Text) :-
    atom_codes(Text, Cs0),
    one_line(Cs0, Cs),
    findall(H, history(H), Hs),
    (   last(Hs, Cs) -> true ; assertz(history(Cs)) ).

one_line([], []).
one_line([C0|Cs0], [C|Cs]) :-
    (   C0 =:= 0'\n -> C = 0'  ; C = C0 ),
    one_line(Cs0, Cs).

edit(Prompt, S0, Result) :-
    redraw(Prompt, S0),
    '$tl_key'(K),
    key_action(K, Action),
    (   step(Action, S0, S)
    ->  (   S = done(Result) -> true ; edit(Prompt, S, Result) )
    ;   edit(Prompt, S0, Result)
    ).

%!  edit_keys(+Keys, +Initial, -Line, -Rest) is det.
%   The line the key codes Keys type, starting from the codes Initial, as
%   codes; Rest is the keys after the one that ends the line. For testing.
edit_keys(Keys, Initial, Line, Rest) :-
    reverse(Initial, Before),
    keys_line(Keys, line(Before, [], [], []), Line, Rest).

keys_line([], line(B, A, _, _), Line, []) :- reverse(B, Bs), append(Bs, A, Line).
keys_line([K|Ks0], S0, Line, Rest) :-
    phrase(key(K, Action), Ks0, Ks),
    (   step(Action, S0, S)
    ->  (   S = done(R)
        ->  ( R = line(Line) -> true ; Line = end_of_file ), Rest = Ks
        ;   keys_line(Ks, S, Line, Rest)
        )
    ;   keys_line(Ks, S0, Line, Rest)
    ).

% A key at the terminal; an escape sequence is read whole, then parsed as in
% a test.
key_action(K, Action) :-
    (   K =:= 0'\x1b\ -> read_escape(Seq) ; Seq = [] ),
    phrase(key(K, Action), Seq, _).

read_escape([C|Cs]) :-
    '$tl_key'(C),
    (   C =:= 0'[ -> read_csi(Cs)
    ;   C =:= 0'O -> '$tl_key'(F), Cs = [F]
    ;   Cs = []
    ).

read_csi([C|Cs]) :-
    '$tl_key'(C),
    (   C >= 0'@, C =< 0'~ -> Cs = [] ; read_csi(Cs) ).

key(0'\x1b\, Action) --> !, escape(Action).
key(K, Action) --> { control(K, Action) }, !.
key(K, insert(K)) --> { K >= 0'  }, !.
key(_, none) --> [].

control(0'\r, accept).
control(0'\n, accept).
control(0'\x7f\, backspace).
control(0'\b, backspace).
control(-1, eof).
control(K, Action) :-
    K >= 1, K =< 26,
    C is K + 0'a - 1,
    char_code(L, C),
    ctrl(L, Action).

% Ctrl and a letter is that letter's code less 96: ctrl(e, end) is Ctrl+E.
ctrl(a, home).
ctrl(e, end).
ctrl(b, left).
ctrl(f, right).
ctrl(d, eof_or_delete).
ctrl(k, kill_end).
ctrl(u, kill_start).
ctrl(w, kill_word).
ctrl(p, up).
ctrl(n, down).

escape(Action) --> next(0'[), !, csi(Action).
escape(Action) --> next(0'O), [F], { csi_action(F, [], Action) }, !.
escape(word_left) --> next(0'b), !.
escape(word_right) --> next(0'f), !.
escape(none) --> [].

csi(Action) --> params(Ps), next(F), { csi_action(F, Ps, Action) }, !.
csi(none) --> [].

params([P|Ps]) --> digits(Ds), { Ds \== [], number_codes(P, Ds) }, !,
    ( next(0';) -> params(Ps) ; { Ps = [] } ).
params([]) --> [].

digits([D|Ds]) --> peek_digit(D), !, digits(Ds).
digits([]) --> [].

csi_action(0'A, [], up).
csi_action(0'B, [], down).
csi_action(0'C, [], right).
csi_action(0'D, [], left).
csi_action(0'H, [], home).
csi_action(0'F, [], end).
csi_action(0'C, [1, 5], word_right).
csi_action(0'D, [1, 5], word_left).
csi_action(0'~, [1], home).
csi_action(0'~, [4], end).
csi_action(0'~, [3], delete).

next(K) --> [K].

peek_digit(D) --> [D], { D >= 0'0, D =< 0'9 }.

% line(Before, After, Older, Newer): Before is reversed, so its head is the
% code left of the cursor; Older and Newer are the history around the line.
step(insert(K), line(B, A, O, N), line([K|B], A, O, N)).
step(accept, line(B, A, _, _), done(line(Cs))) :- reverse(B, Bs), append(Bs, A, Cs).
step(eof, _, done(end_of_file)).
step(eof_or_delete, line([], [], _, _), done(end_of_file)) :- !.
step(eof_or_delete, S0, S) :- step(delete, S0, S).
step(backspace, line([_|B], A, O, N), line(B, A, O, N)).
step(delete, line(B, [_|A], O, N), line(B, A, O, N)).
step(left, line([C|B], A, O, N), line(B, [C|A], O, N)).
step(right, line(B, [C|A], O, N), line([C|B], A, O, N)).
step(home, line(B, A, O, N), line([], Cs, O, N)) :- reverse(B, Bs), append(Bs, A, Cs).
step(end, line(B, A, O, N), line(Rs, [], O, N)) :- reverse(A, As), append(As, B, Rs).
step(kill_end, line(B, _, O, N), line(B, [], O, N)).
step(kill_start, line(_, A, O, N), line([], A, O, N)).
step(kill_word, line(B0, A, O, N), line(B, A, O, N)) :- skip(space, B0, B1), skip(word, B1, B).
step(word_left, line(B0, A0, O, N), line(B, A, O, N)) :-
    move(space, B0, A0, B1, A1), move(word, B1, A1, B, A).
step(word_right, line(B0, A0, O, N), line(B, A, O, N)) :-
    move(space, A0, B0, A1, B1), move(word, A1, B1, A, B).
step(up, line(B, A, [H|O], N), line(Hr, [], O, [Cur|N])) :-
    reverse(B, Bs), append(Bs, A, Cur), reverse(H, Hr).
step(down, line(B, A, O, [H|N]), line(Hr, [], [Cur|O], N)) :-
    reverse(B, Bs), append(Bs, A, Cur), reverse(H, Hr).

% Moves codes of one kind from the head of From to the head of To.
move(Kind, [C|F0], T0, F, T) :- kind(Kind, C), !, move(Kind, F0, [C|T0], F, T).
move(_, F, T, F, T).

skip(Kind, [C|Cs], Rest) :- kind(Kind, C), !, skip(Kind, Cs, Rest).
skip(_, Cs, Cs).

kind(space, C) :- C =:= 0'  .
kind(word, C) :- C =\= 0'  .

% \r, the prompt and the line, clear to the end, then the cursor back over
% what is right of it.
redraw(Prompt, line(B, A, _, _)) :-
    put_char('\r'),
    write(Prompt),
    reverse(B, Bs),
    atom_codes(Left, Bs),
    atom_codes(Right, A),
    write(Left),
    write(Right),
    csi('K'),
    length(A, N),
    (   N > 0 -> csi(N, 'D') ; true ),
    flush_output.

csi(F) :- put_code(0'\x1b\), put_char('['), write(F).
csi(N, F) :- put_code(0'\x1b\), put_char('['), write(N), write(F).

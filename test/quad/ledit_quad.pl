% ledit_quad.pl -- Tests for ledit.pl line editor
%

:- consult('lib/ledit.pl').

% A buffer of three lines with "two" current.
s0(ed(["two", "one"], ["three"], [], memo(none, none, none))).

% The buffer's lines after running Commands on an empty buffer.
session_lines(Commands, Lines) :-
    ed_new(S0),
    ed_session(Commands, S0, S),
    ed_lines(S, Lines).

% ===== Command syntax =====

?- once(phrase(ed_command(C), "f 3")).
   C = forward(3).

?- once(phrase(ed_command(C), "forward 3")).
   C = forward(3).

?- once(phrase(ed_command(C), "f")).
   C = forward(1).

?- once(phrase(ed_command(C), "  b 2  ")).
   C = backward(2).

?- once(phrase(ed_command(C), "p")).
   C = print(1).

?- once(phrase(ed_command(C), "d 4")).
   C = delete(4).

?- once(phrase(ed_command(C), "D")).
   C = delete_all.

?- once(phrase(ed_command(C), "Delete")).
   C = delete_all.

?- once(phrase(ed_command(C), "c /ab/cd/")).
   C = change("ab", "cd", 0).

?- once(phrase(ed_command(C), "c/ab/cd/ 3")).
   C = change("ab", "cd", 3).

?- once(phrase(ed_command(C), "c 2")).
   C = change_again(2).

?- once(phrase(ed_command(C), "c")).
   C = change_again(0).

?- once(phrase(ed_command(C), "l /x y/")).
   C = look("x y").

?- once(phrase(ed_command(C), "l /xy")).
   C = look("xy").

?- once(phrase(ed_command(C), "l")).
   C = look_again.

?- once(phrase(ed_command(C), "s out.txt")).
   C = save('out.txt').

?- once(phrase(ed_command(C), "g in.txt")).
   C = get('in.txt').

?- once(phrase(ed_command(C), "q")).
   C = quit.

?- phrase(ed_command(_), "zzz").
   false.

?- phrase(ed_command(_), "f x").
   false.

?- phrase(ed_command(_), "s").
   false.

% ===== Repeating the previous command =====

?- s0(S0), ed_parse_line("f 2", S0, C, S), ed_parse_line("", S, C2, _).
   C = forward(2), C2 = forward(2), S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed(["two", "one"], ["three"], [], memo(forward(2), none, none)).

?- s0(S0), ed_parse_line("   ", S0, C, _).
   C = bad, S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)).

?- s0(S0), ed_parse_line("zzz", S0, C, _).
   C = bad, S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)).

% ===== Movement =====

?- s0(S0), ed_forward(S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed(["three", "two", "one"], [], [], memo(none, none, none)).

?- s0(S0), ed_backward(S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed(["one"], ["two", "three"], [], memo(none, none, none)).

?- ed_forward(ed(["x"], [], [], m), _).
   false.

?- ed_backward(ed([], ["x"], [], m), _).
   false.

?- s0(S0), ed_repeat(9, ed_backward, S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed([], ["one", "two", "three"], [], memo(none, none, none)).

?- s0(S0), ed_repeat(0, ed_forward, S0, S), S == S0.
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed(["two", "one"], ["three"], [], memo(none, none, none)).

?- s0(S0), ed_lines(S0, L).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), L = ["one", "two", "three"].

?- s0(S0), ed_rewind(S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed([], ["one", "two", "three"], [], memo(none, none, none)).

?- s0(S0), ed_wind(S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed(["three", "two", "one"], [], [], memo(none, none, none)).

% ===== Inserting and deleting =====

?- s0(S0), ed_insert(["a", "b"], S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed(["b", "a", "two", "one"], ["three"], [], memo(none, none, none)).

?- ed_insert(["a"], ed([], [], [], m), S).
   S = ed(["a"], [], [], m).

?- s0(S0), ed_delete(1, S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed(["three", "one"], [], ["two"], memo(none, none, none)).

?- s0(S0), ed_delete(5, S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed(["one"], [], ["two", "three"], memo(none, none, none)).

?- ed_delete(1, ed([], ["x"], [], m), _).
   false.

?- ed_take(2, [a, b, c], P, R).
   P = [a, b], R = [c].

?- ed_take(5, [a], P, R).
   P = [a], R = [].

?- s0(S0), ed_delete_all(S0, S).
   S0 = ed(["two", "one"], ["three"], [], memo(none, none, none)), S = ed([], [], ["one", "two", "three"], memo(none, none, none)).

?- ed_yank(ed(["one"], [], ["a", "b"], m), S).
   S = ed(["b", "a", "one"], [], ["a", "b"], m).

?- ed_yank(ed(["one"], [], [], m), _).
   false.

% ===== Searching and changing =====

?- ed_look("re", ed(["one"], ["two", "three", "four"], [], m), S).
   S = ed(["three", "two", "one"], ["four"], [], m).

?- ed_look("zz", ed(["one"], ["two"], [], m), _).
   false.

?- ed_change("o", "0", 0, ed(["foo", "x"], [], [], m), S).
   S = ed(["f0o", "x"], [], [], m).

?- ed_change("o", "0", 2, ed(["foo"], ["boo", "zoo"], [], m), S).
   S = ed(["b00", "f00"], ["zoo"], [], m).

?- ed_change("o", "0", 9, ed(["foo"], ["boo"], [], m), S).
   S = ed(["b00", "f00"], [], [], m).

?- ed_change("o", "0", 0, ed([], ["foo"], [], m), _).
   false.

?- ed_contains("hello world", "lo w").
   true.

?- ed_contains("hello", "").
   true.

?- ed_contains("hello", "xyz").
   false.

?- ed_replace_first("aaa", "a", "b", T).
   T = "baa".

?- ed_replace_all("aaa", "a", "bb", T).
   T = "bbbbbb".

?- ed_replace_all("hello", "xyz", "q", T).
   T = "hello".

?- ed_replace_all("hello", "", "q", T).
   T = "hello".

% ===== Command chains =====

?- session_lines(["a", "one", "two", "."], L).
   L = ["one", "two"].

?- session_lines([a, x, '.'], L).
   L = ["x"].

?- session_lines(["a", "x"], L).
   L = ["x"].

?- session_lines(["a", "x", ".", "q", "D"], L).
   L = ["x"].

?- session_lines(["a", "1", "2", "3", ".", "r", "f", "d", ""], L).
   L = ["3"].

?- session_lines(["a", "foo", "boo", ".", "r", "f", "c /o/0/ 2"], L).
   L = ["f00", "b00"].

?- session_lines(["a", "1", "2", ".", "b", "d", "y"], L).
   L = ["2", "1"].

?- session_lines(["a", "x", ".", "D", "y"], L).
   L = ["x"].


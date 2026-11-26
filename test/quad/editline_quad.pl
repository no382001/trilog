% library(editline): the line a list of key codes types, without a terminal.

:- use_module(library(editline)).

line(Keys, Initial, Line, Rest) :-
    edit_keys(Keys, Initial, Cs, Rest),
    ( Cs == end_of_file -> Line = Cs ; atom_codes(Line, Cs) ).

?- line([0'a, 0'b, 0'c, 0'\r], [], L, R).
   L = abc, R = [].

?- line([0'a, 0'b, 0'\x1b\, 0'[, 0'D, 0'X, 0'\r], [], L, _).
   L = aXb.

?- line([0'a, 0'b, 0'c, 0'\x7f\, 0'\r], [], L, _).
   L = ab.

?- line([0'f, 0'o, 0'o, 0' , 0'b, 0'a, 0'r, 0'\x1b\, 0'[, 0'1, 0';, 0'5, 0'D, 0'X, 0'\r], [], L, _).
   L = 'foo Xbar'.

?- line([0'f, 0'o, 0'o, 0' , 0'b, 0'a, 0'r, 1, 0'\x1b\, 0'[, 0'1, 0';, 0'5, 0'C, 0'X, 0'\r], [], L, _).
   L = 'fooX bar'.

?- line([0'a, 0'b, 0'c, 1, 0'X, 5, 0'Y, 0'\r], [], L, _).
   L = 'XabcY'.

?- line([0'f, 0'o, 0'o, 0' , 0'b, 0'a, 0'r, 23, 0'\r], [], L, _).
   L = 'foo '.

?- line([0'a, 0'b, 0'c, 2, 2, 11, 0'\r], [], L, _).
   L = a.

?- line([0'a, 0'b, 0'c, 2, 21, 0'\r], [], L, _).
   L = c.

?- line([2, 2, 0'\x1b\, 0'[, 0'3, 0'~, 0'\r], [0'a, 0'b], L, _).
   L = b.

?- line([0'x, 0'\r, 0'y], [0'w], L, R).
   L = wx, R = [0'y].

?- line([4], [], L, _).
   L = end_of_file.

?- line([0'a, 2, 4, 0'\r], [], L, _).
   L = ''.

?- line([-1], [], L, _).
   L = end_of_file.

% A terminal in application mode sends the arrows and Home/End as ESC O x.

?- line([0'a, 0'b, 0'\x1b\, 0'O, 0'D, 0'X, 0'\r], [], L, _).
   L = aXb.

?- line([0'a, 0'b, 0'\x1b\, 0'O, 0'H, 0'X, 0'\x1b\, 0'O, 0'F, 0'Y, 0'\r], [], L, _).
   L = 'XabY'.

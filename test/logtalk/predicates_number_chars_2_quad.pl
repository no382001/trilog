% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

quick_check(iso_number_chars_2_14, round_trip(+integer)).
quick_check(iso_number_chars_2_15, round_trip(+float)).
round_trip(X) :- (number_chars(X, L), number_chars(Y, L), X == Y).

% iso_number_chars_2_01
?- once(number_chars(33, L)), L == ['3','3'].
   true.

% iso_number_chars_2_02
?- number_chars(33, ['3','3']).
   true.

% iso_number_chars_2_03
?- once((number_chars(33.0, L), number_chars(N, L))), N == 33.0.
   true.

% iso_number_chars_2_04
?- once(number_chars(X, ['3','.','3','E','+','0'])), X == 3.3.
   true.

% iso_number_chars_2_05
?- number_chars(3.3, ['3'| _L]).
   true.

% iso_number_chars_2_06
?- once(number_chars(A, ['-','2','5'])), A == -25.
   true.

% iso_number_chars_2_07
?- once(number_chars(A, ['\n',' ','3'])), A == 3.
   true.

% iso_number_chars_2_08
?- number_chars(_A, ['3',' ']).
   error(syntax_error(_)).

% iso_number_chars_2_09
?- once(number_chars(A, ['0',x,f])), A == 15.
   true.

% iso_number_chars_2_10
?- once(number_chars(A, ['0','''',a])), A == 0'a.
   true.

% iso_number_chars_2_11
?- once(number_chars(A, ['4','.','2'])), A == 4.2.
   true.

% iso_number_chars_2_12
?- once(number_chars(A, ['4','2','.','0','e','-','1'])), A == 4.2.
   true.

% iso_number_chars_2_13
?- C = ['0', '.', '1'], (number_chars(X, C), number_chars(X, C)).
   true.

% eddbali_number_chars_2_16
?- number_chars(_A, _L).
   error(instantiation_error).

% eddbali_number_chars_2_17
?- number_chars(a, _L).
   error(type_error(number,a)).

% eddbali_number_chars_2_18
?- number_chars(_A, 4).
   error(type_error(list,4)).

% eddbali_number_chars_2_19
?- number_chars(_A, ['4',2]).
   error(type_error(character,2)).

% sics_number_chars_2_20
?- number_chars(_A, [a|_L]).
   error(instantiation_error).

% sics_number_chars_2_21
?- number_chars(_A, [a,_L]).
   error(instantiation_error).

% sics_number_chars_2_22
?- once(number_chars(X, [' ','0','o','1','1'])), X == 9.
   true.

% sics_number_chars_2_23
?- once(number_chars(X, [' ','0','x','1','1'])), X == 17.
   true.

% sics_number_chars_2_24
?- once(number_chars(X, [' ','0','b','1','1'])), X == 3.
   true.

% sics_number_chars_2_25
?- number_chars(_X, ['0','o','8']).
   error(syntax_error(_)).

% sics_number_chars_2_26
?- number_chars(_X, ['0','b','2']).
   error(syntax_error(_)).

% sics_number_chars_2_27
?- number_chars(_X, ['0','x','g']).
   error(syntax_error(_)).

% sics_number_chars_2_29
?- number_chars(_X, ['a']).
   error(syntax_error(_)).

% sics_number_chars_2_30
?- number_chars(_X, ['0','x','0','.','0']).
   error(syntax_error(_)).

% not converted:
% sics_number_chars_2_28: marked skipped by Logtalk

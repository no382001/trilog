% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

quick_check(iso_number_codes_2_12, round_trip(+integer)).
quick_check(iso_number_codes_2_13, round_trip(+float)).
round_trip(X) :- (number_codes(X, L), number_codes(Y, L), X == Y).

% iso_number_codes_2_01
?- once(number_codes(33, L)), L == [0'3,0'3].
   true.

% iso_number_codes_2_02
?- number_codes(33, [0'3,0'3]).
   true.

% iso_number_codes_2_03
?- once((number_codes(33.0, L), number_codes(N, L))), N == 33.0.
   true.

% iso_number_codes_2_04
?- number_codes(33.0, [0'3| _L]).
   true.

% iso_number_codes_2_05
?- once(number_codes(A, [0'-,0'2,0'5])), A == -25.
   true.

% iso_number_codes_2_06
?- once(number_codes(A, [0' , 0'3])), A == 3.
   true.

% iso_number_codes_2_07
?- once(number_codes(A, [0'0,0'x,0'f])), A == 15.
   true.

% iso_number_codes_2_08
?- once(number_codes(A, [0'0,39,0'a])), A == 0'a.
   true.

% iso_number_codes_2_09
?- once(number_codes(A, [0'4,0'.,0'2])), A == 4.2.
   true.

% iso_number_codes_2_10
?- once(number_codes(A, [0'4,0'2,0'.,0'0,0'e,0'-,0'1])), A == 4.2.
   true.

% iso_number_codes_2_11
?- C = [0'0, 0'., 0'1], (number_codes(X, C), number_codes(X, C)).
   true.

% eddbali_number_codes_2_14
?- number_codes(_A, _L).
   error(instantiation_error).

% eddbali_number_codes_2_15
?- number_codes(a, _L).
   error(type_error(number,a)).

% eddbali_number_codes_2_16
?- number_codes(_A, 4).
   error(type_error(list,4)).

% eddbali_number_codes_2_17
?- number_codes(_A, [0'4,-1]).
   error(representation_error(character_code)).

% sics_number_codes_2_18
?- number_codes(_A, [0'a|_L]).
   error(instantiation_error).

% sics_number_codes_2_19
?- number_codes(_A, [0'a,_L]).
   error(instantiation_error).

% sics_number_codes_2_20
?- once((number_chars(X, [' ','0','x','1','1','1']), number_codes(X, Y))), X-Y == 273-[50,55,51].
   true.

% sics_number_codes_2_21
?- once((number_chars(X, [' ','0','o','1','1','1']), number_codes(X, Y))), X-Y == 73-[55,51].
   true.

% sics_number_codes_2_22
?- once((number_chars(X, [' ','0','b','1','1','1']), number_codes(X, Y))), X-Y == 7-[55].
   true.

% sics_number_codes_2_23
?- once(number_codes(N, [48,39,92,110])), N == 10.
   true.

% sics_number_codes_2_24
?- number_codes(_N, [97]).
   error(syntax_error(_)).

% sics_number_codes_2_25
?- number_codes(_X, [0'0,0'x,0'0,0'.,0'0]).
   error(syntax_error(_)).

% sics_number_codes_2_33
?- once(number_codes(X, [0'0,0'x,0'1,0'1,0'1])), X == 273.
   true.

% sics_number_codes_2_34
?- once(number_codes(X, [0'0,0'o,0'1,0'1,0'1])), X == 73.
   true.

% sics_number_codes_2_35
?- once(number_codes(X, [0'0,0'b,0'1,0'1,0'1])), X == 7.
   true.

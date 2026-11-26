% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_number_01
?- once((set_text_input('123. '), read(T))), T == 123.
   true.

% iso_number_02
?- once((set_text_input('-123. '), read(T))), T == -123.
   true.

% iso_number_03
?- once((set_text_input('123.45. '), read(T))), T == 123.45.
   true.

% iso_number_04
?- once((set_text_input('-123.45. '), read(T))), T == -123.45.
   true.

% iso_number_05
?- once((set_text_input('83. '), read(T))), T == 83.
   true.

% iso_number_06
?- once((set_text_input('0\'S. '), read(T))), char_code('S', T).
   true.

% iso_number_07
?- once((set_text_input('0b1010011. '), read(T))), T == 83.
   true.

% iso_number_08
?- once((set_text_input('0o123. '), read(T))), T == 83.
   true.

% iso_number_09
?- once((set_text_input('0x53. '), read(T))), T == 83.
   true.

% iso_number_10
?- once((set_text_input('123.45. '), read(T))), T == 123.45.
   true.

% iso_number_11
?- once((set_text_input('123.45e+1. '), read(T))), T == 1234.5.
   true.

% iso_number_12
?- once((set_text_input('123.45E+1. '), read(T))), T == 1234.5.
   true.

% iso_number_13
?- once((set_text_input('123.45e-1. '), read(T))), T == 12.345.
   true.

% iso_number_14
?- once((set_text_input('123.45E-1. '), read(T))), T == 12.345.
   true.

:- clean_text_input.

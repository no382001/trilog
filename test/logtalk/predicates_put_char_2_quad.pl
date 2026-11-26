% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_put_char_2_01
?- once((set_text_output('qwer'), put_char(t), text_output_assertion('qwert', Assertion))), Assertion.
   true.

% iso_put_char_2_02
?- once((set_text_output(st_o, 'qwer'), put_char(st_o, 'A'), text_output_assertion(st_o, 'qwerA', Assertion))), Assertion.
   true.

% iso_put_char_2_03
?- once((set_text_output('qwer'), (nl, put_char(a)), text_output_assertion('qwer\na', Assertion))), Assertion.
   true.

% iso_put_char_2_04
?- once((set_text_output(st_o, 'qwer'), (nl(st_o), put_char(st_o, a)), text_output_assertion(st_o, 'qwer\na', Assertion))), Assertion.
   true.

% iso_put_char_2_05
?- set_text_output(my_file, ''), put_char(my_file, _C).
   error(instantiation_error).

% iso_put_char_2_06
?- set_text_output(st_o, ''), put_char(st_o, 'ty').
   error(type_error(character, ty)).

% sics_put_char_2_07
?- put_char(_, t).
   error(instantiation_error).

% sics_put_char_2_08
?- put_char(_).
   error(instantiation_error).

% sics_put_char_2_09
?- closed_input_stream(S, []), put_char(S, a).
   error(existence_error(stream,S)).

% sics_put_char_2_10
?- closed_output_stream(S, []), put_char(S, a).
   error(existence_error(stream,S)).

% sics_put_char_2_11
?- current_input(S), put_char(S, a).
   error(permission_error(output,stream,S)).

% sics_put_char_2_12
?- set_binary_output([]), current_output(S), put_char(a).
   error(permission_error(output,binary_stream,S)).

:- clean_text_output, clean_binary_output, clean_text_input.

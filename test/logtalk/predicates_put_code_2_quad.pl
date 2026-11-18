% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_put_code_2_01
?- once((set_text_output('qwer'), put_code(0't), text_output_assertion('qwert', Assertion))), Assertion.
   true.

% iso_put_code_2_02
?- once((set_text_output(st_o, 'qwer'), put_code(st_o, 0't), text_output_assertion(st_o, 'qwert', Assertion))), Assertion.
   true.

% iso_put_code_2_03
?- set_text_output(my_file, ''), put_code(my_file, _C), check_text_output(my_file, '').
   error(instantiation_error).

% iso_put_code_2_04
?- set_text_output(st_o, ''), put_code(st_o, 'ty'), check_text_output(st_o, '').
   error(type_error(integer,ty)).

% sics_put_code_2_05
?- put_code(_, 0't).
   error(instantiation_error).

% sics_put_code_2_06
?- put_code(_).
   error(instantiation_error).

% iso_put_code_2_07
?- closed_input_stream(S, []), put_code(S, 0'a).
   error(existence_error(stream,S)).

% iso_put_code_2_08
?- closed_output_stream(S, []), put_code(S, 0'a).
   error(existence_error(stream,S)).

% iso_put_code_2_09
?- current_input(S), put_code(S, 0'a).
   error(permission_error(output,stream,S)).

% iso_put_code_2_10
?- file_path(t, Path), open(Path, write, S, [type(binary)]), put_code(S, 0'a).
   error(permission_error(output,binary_stream,S)).

% sics_put_code_2_11
?- put_code(-1).
   error(representation_error(character_code)).

% sics_put_code_2_12
?- put_code(foo, 1).
   error(domain_error(stream_or_alias,foo))
|  error(existence_error(stream,foo)).

:- clean_file(t), clean_text_output, clean_text_input, clean_binary_output.

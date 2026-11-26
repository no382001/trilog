% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_put_byte_2_01
?- once((set_binary_output([113,119,101,114]), put_byte(116), binary_output_assertion([113,119,101,114,116], Assertion))), Assertion.
   true.

% iso_put_byte_2_02
?- once((set_binary_output(st_o, [113,119,101,114]), put_byte(st_o, 116), binary_output_assertion(st_o, [113,119,101,114,116], Assertion))), Assertion.
   true.

% iso_put_byte_2_03
?- set_binary_output(my_file_1, []), put_byte(my_file_1, _C).
   error(instantiation_error).

% iso_put_byte_2_04
?- set_binary_output(my_file_2, []), put_byte(my_file_2, 'ty').
   error(type_error(byte, ty)).

% sics_put_byte_2_05
?- put_byte(_S, 118).
   error(instantiation_error).

% sics_put_byte_2_06
?- set_binary_output([]), put_byte(_C).
   error(instantiation_error).

% sics_put_byte_2_07
?- closed_input_stream(S, [type(binary)]), put_byte(S, 77).
   error(existence_error(stream,S)).

% sics_put_byte_2_08
?- closed_output_stream(S, [type(binary)]), put_byte(S, 77).
   error(existence_error(stream,S)).

% sics_put_byte_2_09
?- set_binary_input([]), current_input(S), put_byte(S, 99).
   error(permission_error(output,stream,S)).

% sics_put_byte_2_10
?- current_output(S), put_byte(99).
   error(permission_error(output,text_stream,S)).

% sics_put_byte_2_11
?- set_binary_output([]), put_byte(-1).
   error(type_error(byte,-1)).

% sics_put_byte_2_12
?- put_byte(_S, 1).
   error(instantiation_error).

% sics_put_byte_2_13
?- put_byte(foo, 1).
   error(domain_error(stream_or_alias,foo))
|  error(existence_error(stream,foo)).

:- clean_binary_input, clean_binary_output, clean_text_output.

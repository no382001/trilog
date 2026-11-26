% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- lgt_files('predicates_set_stream_position_2').

% sics_set_stream_position_2_01
?- stream_position(Position), set_stream_position(_Stream, Position).
   error(instantiation_error).

% sics_set_stream_position_2_02
?- set_text_input(st_i, '', [reposition(true)]), set_stream_position(st_i, _Position).
   error(instantiation_error).

% sics_set_stream_position_2_03
?- stream_position(Position), set_stream_position(foo, Position).
   error(domain_error(stream_or_alias,foo))
|  error(existence_error(stream,foo)).

% sics_set_stream_position_2_04
?- stream_position(Position), closed_output_stream(Stream, []), set_stream_position(Stream, Position).
   error(existence_error(stream,Stream)).

% sics_set_stream_position_2_05
?- set_text_input(st_i, '', [reposition(true)]), set_stream_position(st_i, foo).
   error(domain_error(stream_position,foo)).

% sics_set_stream_position_2_06
?- file_path('terms.pl', Path), open(Path, read, Stream, [reposition(false)]), stream_property(Stream, position(Position)), set_stream_position(Stream, Position).
   error(permission_error(reposition,stream,Stream)).

:- clean_text_input, clean_binary_input, clean_text_output, clean_binary_output, clean_file(foo).

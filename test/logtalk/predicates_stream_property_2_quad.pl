% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

memberchk(Element, [Head| _]) :- Element == Head, !.
memberchk(Element, [_| Tail]) :- memberchk(Element, Tail).

% iso_stream_property_2_01
?- lgt_run((once((file_path(foo, FooPath), file_path(bar, BarPath), create_text_file(FooPath, ''), open(FooPath, read, S1), open(BarPath, write, S2), findall(S-F,stream_property(S, file_name(F)),L))), (memberchk(S1-FooPath, L), memberchk(S2-BarPath, L)))).
   true.
:- (close(S1), close(S2)).

% iso_stream_property_2_02
?- lgt_run((once((file_path(bar, BarPath), open(BarPath, write, FOut), current_output(COut), findall(S,stream_property(S, output),L))), (memberchk(FOut, L), memberchk(COut, L)))).
   true.
:- close(FOut).

% sics_stream_property_2_03
?- lgt_run(stream_property(foo, _S)).
   error(domain_error(stream,foo)).

% sics_stream_property_2_04
?- lgt_run(stream_property(_S, foo)).
   error(domain_error(stream_property,foo)).

% sics_stream_property_2_05a
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((current_input(S), findall(P,stream_property(S, P),L), memberchk(input, L))).
   true.

% sics_stream_property_2_05b
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((current_input(S), findall(A,stream_property(S, alias(A)),L), memberchk(user_input, L))).
   true.

% sics_stream_property_2_05c
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((once((current_input(S), stream_property(S, eof_action(Action)))), Action == reset)).
   true.

% sics_stream_property_2_05d
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((once((current_input(S), stream_property(S, mode(Mode)))), Mode == read)).
   true.

% sics_stream_property_2_05e
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((once((current_input(S), stream_property(S, reposition(Reposition)))), Reposition == false)).
   true.

% sics_stream_property_2_05f
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((once((current_input(S), stream_property(S, type(Type)))), Type == text)).
   true.

% sics_stream_property_2_06a
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((current_output(S), findall(P,stream_property(S, P),L), memberchk(output, L))).
   true.

% sics_stream_property_2_06b
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((current_output(S), findall(A,stream_property(S, alias(A)),L), memberchk(user_output, L))).
   true.

% sics_stream_property_2_06d
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((once((current_output(S), stream_property(S, mode(Mode)))), Mode == append)).
   true.

% sics_stream_property_2_06e
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((once((current_output(S), stream_property(S, reposition(Reposition)))), Reposition == false)).
   true.

% sics_stream_property_2_06f
% lgtunit also checks that the goal is deterministic; quad does not
?- lgt_run((once((current_output(S), stream_property(S, type(Type)))), Type == text)).
   true.

% sics_stream_property_2_07
?- lgt_run(stream_property(_S, type(binary))).
   false.

% not converted:
% sics_stream_property_2_06c: marked skipped by Logtalk

:- clean_file(foo), clean_file(bar), clean_file(output_text_file), clean_file(input_text_file), clean_file(output_binary_file), clean_file(input_binary_file).

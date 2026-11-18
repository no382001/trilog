% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% sics_current_output_1_01
?- lgt_run(current_output(_S)).
   true.

% sics_current_output_1_02
?- lgt_run(current_output(foo)).
   error(domain_error(stream,foo)).

% sics_current_output_1_03
?- lgt_run((current_input(S), current_output(S))).
   false.

% sics_current_output_1_04
?- lgt_run((closed_output_stream(S, []), current_output(S))).
   error(domain_error(stream,S)).

% sics_current_output_1_05
?- lgt_run((current_output(S), current_output(S))).
   true.

% sics_current_output_1_06
?- lgt_run((current_output(S), ground(S))).
   true.

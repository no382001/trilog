% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% sics_current_input_1_01
?- lgt_run(current_input(_S)).
   true.

% sics_current_input_1_02
?- lgt_run(current_input(foo)).
   error(domain_error(stream,foo)).

% sics_current_input_1_03
?- lgt_run((current_output(S), current_input(S))).
   false.

% sics_current_input_1_04
?- lgt_run((closed_input_stream(S, []), current_input(S))).
   error(domain_error(stream,S)).

% sics_current_input_1_05
?- lgt_run((current_input(S), current_input(S))).
   true.

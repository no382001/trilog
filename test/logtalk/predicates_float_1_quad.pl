% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_float_1_predicate_01
?- lgt_run(float(3.3)).
   true.

% iso_float_1_predicate_02
?- lgt_run(float(-3.3)).
   true.

% iso_float_1_predicate_03
?- lgt_run(float(3)).
   false.

% iso_float_1_predicate_04
?- lgt_run(float(atom)).
   false.

% iso_float_1_predicate_05
?- lgt_run(float(_X)).
   false.

% iso_float_1_predicate_06
?- lgt_run(float(1.0)).
   true.

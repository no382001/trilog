% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

three(3).

% iso_conjunction_2_01
?- lgt_run(','(X=1, var(X))).
   false.

% iso_conjunction_2_02
?- lgt_run((once(','(var(X), X=1)), X == 1)).
   true.

% iso_conjunction_2_03
?- lgt_run((once(','(X = true, call(X))), X == true)).
   true.

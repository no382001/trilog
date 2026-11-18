% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_min_2_01
?- lgt_run((once(X is min(2, 3)), X == 2)).
   true.

% iso_min_2_02
?- lgt_run(catch((X is min(2, 3.0), (X == 2; X == 2.0)),Error,Error = error(evaluation_error(undefined), _))).
   true.

% iso_min_2_03
?- lgt_run(catch((X is min(2.0, 3), X == 2.0),Error,Error = error(evaluation_error(undefined), _))).
   true.

% iso_min_2_04
?- lgt_run(catch((X is min(0, 0.0), (X == 0; X == 0.0)),Error,Error = error(evaluation_error(undefined), _))).
   true.

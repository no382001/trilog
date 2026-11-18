% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_max_2_01
?- once(X is max(2, 3)), X == 3.
   true.

% iso_max_2_02
?- catch((X is max(2.0, 3), (X == 3; X == 3.0)),Error,Error = error(evaluation_error(undefined), _)).
   true.

% iso_max_2_03
?- catch((X is max(2, 3.0), X == 3.0),Error,Error = error(evaluation_error(undefined), _)).
   true.

% iso_max_2_04
?- catch((X is max(0, 0.0), (X == 0; X == 0.0)),Error,Error = error(evaluation_error(undefined), _)).
   true.

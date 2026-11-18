% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_acos_1_01
?- once(X is acos(-1)), X =~= 3.1415927.
   true.

% iso_acos_1_02
?- once(X is acos(0.5)), X =~= 1.0471976.
   true.

% iso_acos_1_03
?- _X is acos(1.5).
   error(evaluation_error(undefined)).

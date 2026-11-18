% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_atan2_2_01
?- lgt_run((once(X is atan2(1, 0)), X =~= 1.5707963)).
   true.

% iso_atan2_2_02
?- lgt_run((once(X is atan2(0, -1)), X =~= 3.1415927)).
   true.

% iso_atan2_2_03
?- lgt_run(_X is atan2(0, 0)).
   error(evaluation_error(undefined)).

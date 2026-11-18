% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_asin_1_01
?- lgt_run((once(X is asin(0.5)), X =~= 0.5235988)).
   true.

% iso_asin_1_02
?- lgt_run((once(X is 2*asin(1)), X =~= 3.1415927)).
   true.

% iso_asin_1_03
?- lgt_run(_X is asin(2)).
   error(evaluation_error(undefined)).

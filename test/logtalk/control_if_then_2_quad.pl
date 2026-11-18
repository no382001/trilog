% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

three(3).

% iso_if_then_2_01
?- lgt_run('->'(true, true)).
   true.

% iso_if_then_2_02
?- lgt_run('->'(true, fail)).
   false.

% iso_if_then_2_03
?- lgt_run('->'(fail, true)).
   false.

% iso_if_then_2_04
?- lgt_run((once('->'(true, X=1)), X == 1)).
   true.

% iso_if_then_2_05
?- lgt_run((once('->'(';'(X=1, X=2), true)), X == 1)).
   true.

% iso_if_then_2_06
?- lgt_run((once(findall(X,'->'(true, ';'(X=1, X=2)),L)), L == [1, 2])).
   true.

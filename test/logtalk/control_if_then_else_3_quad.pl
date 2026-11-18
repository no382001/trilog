% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

three(3).

% iso_if_then_else_3_01
?- lgt_run(';'('->'(true, true), fail)).
   true.

% iso_if_then_else_3_02
?- lgt_run(';'('->'(fail, true), true)).
   true.

% iso_if_then_else_3_03
?- lgt_run(';'('->'(true, fail), fail)).
   false.

% iso_if_then_else_3_04
?- lgt_run(';'('->'(fail, true), fail)).
   false.

% iso_if_then_else_3_05
?- lgt_run((once(';'('->'(true, X=1), X=2)), X == 1)).
   true.

% iso_if_then_else_3_06
?- lgt_run((once(';'('->'(fail, X=1), X=2)), X == 2)).
   true.

% iso_if_then_else_3_07
?- lgt_run((once(findall(X,';'('->'(true, ';'(X=1, X=2)), true),L)), L == [1,2])).
   true.

% iso_if_then_else_3_08
?- lgt_run((once(';'('->'(';'(X=1, X=2), true), true)), X == 1)).
   true.

% iso_if_then_else_3_09
?- lgt_run(';'(('->'(!,fail), true), true)).
   true.

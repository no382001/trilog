% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

three(3).

% iso_if_then_else_3_01
?- ';'('->'(true, true), fail).
   true.

% iso_if_then_else_3_02
?- ';'('->'(fail, true), true).
   true.

% iso_if_then_else_3_03
?- ';'('->'(true, fail), fail).
   false.

% iso_if_then_else_3_04
?- ';'('->'(fail, true), fail).
   false.

% iso_if_then_else_3_05
?- once(';'('->'(true, X=1), X=2)), X == 1.
   true.

% iso_if_then_else_3_06
?- once(';'('->'(fail, X=1), X=2)), X == 2.
   true.

% iso_if_then_else_3_07
?- once(findall(X,';'('->'(true, ';'(X=1, X=2)), true),L)), L == [1,2].
   true.

% iso_if_then_else_3_08
?- once(';'('->'(';'(X=1, X=2), true), true)), X == 1.
   true.

% iso_if_then_else_3_09
?- ';'(('->'(!,fail), true), true).
   true.

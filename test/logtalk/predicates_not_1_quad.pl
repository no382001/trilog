% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_not_1_01
?- lgt_run('\\+'(true)).
   false.

% iso_not_1_02
?- lgt_run('\\+'(!)).
   false.

% iso_not_1_03
?- lgt_run('\\+'((!,fail))).
   true.

% iso_not_1_04
?- lgt_run((once(findall(X,((X=1;X=2), '\\+'((!,fail))),L)), L == [1, 2])).
   true.

% iso_not_1_05
?- lgt_run('\\+'(4 = 5)).
   true.

% iso_not_1_06
?- lgt_run((G = '\\+'(3), G)).
   error(type_error(callable,3))
|  error(type_error(callable,'\\+'(3))).

% iso_not_1_07
?- lgt_run((G = '\\+'(_X), G)).
   error(instantiation_error).

% iso_not_1_08
?- lgt_run('\\+'(X=f(X))).
   false.

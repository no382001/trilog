% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_unify_2_01
?- lgt_run('='(1, 1)).
   true.

% iso_unify_2_02
?- lgt_run((once('='(X, 1)), X == 1)).
   true.

% iso_unify_2_03
?- lgt_run((once('='(X, Y)), X == Y)).
   true.

% iso_unify_2_04
?- lgt_run('='(_, _)).
   true.

% iso_unify_2_05
?- lgt_run((once(('='(X,Y), '='(X,abc))), (X == abc, Y == abc))).
   true.

% iso_unify_2_06
?- lgt_run((once('='(f(X,def), f(def,Y))), (X == def, Y == def))).
   true.

% iso_unify_2_07
?- lgt_run('='(1, 2)).
   false.

% iso_unify_2_08
?- lgt_run('='(1, 1.0)).
   false.

% iso_unify_2_09
?- lgt_run('='(g(X), f(f(X)))).
   false.

% iso_unify_2_10
?- lgt_run('='(f(X,1), f(a(X)))).
   false.

% iso_unify_2_11
?- lgt_run('='(f(X,Y,X), f(a(X),a(Y),Y,2))).
   false.

% iso_unify_2_12
?- lgt_run('='(X,a(X))).
   true.

% iso_unify_2_13
?- lgt_run('='(f(X,1), f(a(X),2))).
   false.

% iso_unify_2_14
?- lgt_run('='(f(1,X,1), f(2,a(X),2))).
   false.

% iso_unify_2_15
?- lgt_run('='(f(1,X), f(2,a(X)))).
   false.

% iso_unify_2_16
?- lgt_run('='(f(X,Y,X,1), f(a(X),a(Y),Y,2))).
   false.

% iso_unify_2_17
?- lgt_run((L1 = [1,2,3| L1], L2 = [1,2,3,1,2,3| L2], L1 == L2)).
   true.

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_unify_2_01
?- '='(1, 1).
   true.

% iso_unify_2_02
?- once('='(X, 1)), X == 1.
   true.

% iso_unify_2_03
?- once('='(X, Y)), X == Y.
   true.

% iso_unify_2_04
?- '='(_, _).
   true.

% iso_unify_2_05
?- once(('='(X,Y), '='(X,abc))), (X == abc, Y == abc).
   true.

% iso_unify_2_06
?- once('='(f(X,def), f(def,Y))), (X == def, Y == def).
   true.

% iso_unify_2_07
?- '='(1, 2).
   false.

% iso_unify_2_08
?- '='(1, 1.0).
   false.

% iso_unify_2_09
?- '='(g(X), f(f(X))).
   false.

% iso_unify_2_10
?- '='(f(X,1), f(a(X))).
   false.

% iso_unify_2_11
?- '='(f(X,Y,X), f(a(X),a(Y),Y,2)).
   false.

% iso_unify_2_12
?- '='(X,a(X)).
   true.

% iso_unify_2_13
?- '='(f(X,1), f(a(X),2)).
   false.

% iso_unify_2_14
?- '='(f(1,X,1), f(2,a(X),2)).
   false.

% iso_unify_2_15
?- '='(f(1,X), f(2,a(X))).
   false.

% iso_unify_2_16
?- '='(f(X,Y,X,1), f(a(X),a(Y),Y,2)).
   false.

% iso_unify_2_17
?- L1 = [1,2,3| L1], L2 = [1,2,3,1,2,3| L2], L1 == L2.
   true.

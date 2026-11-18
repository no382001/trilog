% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_unify_with_occurs_check_2_01
?- unify_with_occurs_check(1, 1).
   true.

% iso_unify_with_occurs_check_2_02
?- once(unify_with_occurs_check(X, 1)), X == 1.
   true.

% iso_unify_with_occurs_check_2_03
?- once(unify_with_occurs_check(X, Y)), X == Y.
   true.

% iso_unify_with_occurs_check_2_04
?- unify_with_occurs_check(_, _).
   true.

% iso_unify_with_occurs_check_2_05
?- once((unify_with_occurs_check(X, Y), unify_with_occurs_check(X, abc))), X-Y == abc-abc.
   true.

% iso_unify_with_occurs_check_2_06
?- once(unify_with_occurs_check(f(X,def), f(def,Y))), X-Y == def-def.
   true.

% iso_unify_with_occurs_check_2_07
?- unify_with_occurs_check(1, 2).
   false.

% iso_unify_with_occurs_check_2_08
?- unify_with_occurs_check(1, 1.0).
   false.

% iso_unify_with_occurs_check_2_09
?- unify_with_occurs_check(g(X), f(f(X))).
   false.

% iso_unify_with_occurs_check_2_10
?- unify_with_occurs_check(f(X,1), f(a(X))).
   false.

% iso_unify_with_occurs_check_2_11
?- unify_with_occurs_check(f(X,Y,X), f(a(X),a(Y),Y,2)).
   false.

% iso_unify_with_occurs_check_2_12
?- unify_with_occurs_check(X, a(X)).
   false.

% iso_unify_with_occurs_check_2_13
?- unify_with_occurs_check(f(X,1), f(a(X),2)).
   false.

% iso_unify_with_occurs_check_2_14
?- unify_with_occurs_check(f(1,X,1), f(2,a(X),2)).
   false.

% iso_unify_with_occurs_check_2_15
?- unify_with_occurs_check(f(1,X), f(2,a(X))).
   false.

% iso_unify_with_occurs_check_2_16
?- unify_with_occurs_check(f(X,Y,X,1), f(a(X),a(Y),Y,2)).
   false.

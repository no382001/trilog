% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_not_unifiable_2_01
?- '\\='(1, 1).
   false.

% iso_not_unifiable_2_02
?- \=(_X, 1).
   false.

% iso_not_unifiable_2_03
?- '\\='(_X, _Y).
   false.

% iso_not_unifiable_2_04
?- \=(_, _).
   false.

% iso_not_unifiable_2_05
?- \=(f(_X,def), f(def,_Y)).
   false.

% iso_not_unifiable_2_06
?- '\\='(1, 2).
   true.

% iso_not_unifiable_2_07
?- \=(1, 1.0).
   true.

% iso_not_unifiable_2_08
?- '\\='(g(X), f(f(X))).
   true.

% iso_not_unifiable_2_09
?- \=(f(X,1), f(a(X))).
   true.

% iso_not_unifiable_2_10
?- '\\='(f(X,Y,X), f(a(X),a(Y),Y,2)).
   true.

% iso_not_unifiable_2_11
?- \=(X, a(X)).
   false.

% iso_not_unifiable_2_12
?- '\\='(f(X,1), f(a(X),2)).
   true.

% iso_not_unifiable_2_13
?- '\\='(f(1,X,1), f(2,a(X),2)).
   true.

% iso_not_unifiable_2_14
?- \=(f(1,X), f(2,a(X))).
   true.

% iso_not_unifiable_2_15
?- '\\='(f(X,Y,X,1), f(a(X),a(Y),Y,2)).
   true.

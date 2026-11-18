% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_not_unifiable_2_01
?- lgt_run('\\='(1, 1)).
   false.

% iso_not_unifiable_2_02
?- lgt_run(\=(_X, 1)).
   false.

% iso_not_unifiable_2_03
?- lgt_run('\\='(_X, _Y)).
   false.

% iso_not_unifiable_2_04
?- lgt_run(\=(_, _)).
   false.

% iso_not_unifiable_2_05
?- lgt_run(\=(f(_X,def), f(def,_Y))).
   false.

% iso_not_unifiable_2_06
?- lgt_run('\\='(1, 2)).
   true.

% iso_not_unifiable_2_07
?- lgt_run(\=(1, 1.0)).
   true.

% iso_not_unifiable_2_08
?- lgt_run('\\='(g(X), f(f(X)))).
   true.

% iso_not_unifiable_2_09
?- lgt_run(\=(f(X,1), f(a(X)))).
   true.

% iso_not_unifiable_2_10
?- lgt_run('\\='(f(X,Y,X), f(a(X),a(Y),Y,2))).
   true.

% iso_not_unifiable_2_11
?- lgt_run(\=(X, a(X))).
   false.

% iso_not_unifiable_2_12
?- lgt_run('\\='(f(X,1), f(a(X),2))).
   true.

% iso_not_unifiable_2_13
?- lgt_run('\\='(f(1,X,1), f(2,a(X),2))).
   true.

% iso_not_unifiable_2_14
?- lgt_run(\=(f(1,X), f(2,a(X)))).
   true.

% iso_not_unifiable_2_15
?- lgt_run('\\='(f(X,Y,X,1), f(a(X),a(Y),Y,2))).
   true.

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- discontiguous([ succeeds/1, fails/1 ]).

three(3).

% iso_disjunction_2_01
?- ';'(true, fail).
   true.

% iso_disjunction_2_02
?- ';'((!, fail), true).
   false.

% iso_disjunction_2_03
?- three(Three), ';'(!, call(Three)).
   true.

% iso_disjunction_2_04
?- once(';'((X=1, !), X=2)), X == 1.
   true.

% iso_disjunction_2_05
?- once(findall(X,';'(X=1, X=2),L)), L == [1,2].
   true.

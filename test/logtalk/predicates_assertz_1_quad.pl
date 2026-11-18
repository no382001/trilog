% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- dynamic(legs/2).
:- dynamic(foo/1).

four(4).

% iso_assertz_1_01
?- lgt_run(assertz(legs(spider, 8))).
   true.

% iso_assertz_1_02
?- lgt_run(assertz((legs(B, 2):-bird(B)))).
   true.

% iso_assertz_1_03
?- lgt_run(assertz((foo(X):- X -> call(X)))).
   true.

% iso_assertz_1_04
?- lgt_run(assertz(_)).
   error(instantiation_error).

% iso_assertz_1_05
?- lgt_run((four(Four), assertz(Four))).
   error(type_error(callable,4)).

% iso_assertz_1_06
?- lgt_run((four(Four), assertz((foo :- Four)))).
   error(type_error(callable,4)).

% iso_assertz_1_07
?- lgt_run(assertz((atom(_) :- true))).
   error(permission_error(modify,static_procedure,atom/1))
|  error(permission_error(modify,static_procedure,':'(user,atom/1))).

% eddbali_assertz_1_08
?- lgt_run((once(findall(X-Y,(assertz(insct(bee)),insct(X),assertz(insct(ant)),insct(Y)),L)), L == [bee-bee, bee-ant])).
   true.

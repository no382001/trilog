% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- dynamic(legs/2).
:- dynamic(foo/1).
:- discontiguous([ succeeds/1, throws/2 ]).

four(4).

% iso_asserta_1_01
?- lgt_run(asserta(legs(octopus, 8))).
   true.

% iso_asserta_1_02
?- lgt_run(asserta((legs(A,4):-animal(A)))).
   true.

% iso_asserta_1_03
?- lgt_run(asserta((foo(X) :- X,call(X)))).
   true.

% iso_asserta_1_04
?- lgt_run(asserta(_)).
   error(instantiation_error).

% iso_asserta_1_05
?- lgt_run((four(Four), asserta(Four))).
   error(type_error(callable,4)).

% iso_asserta_1_06
?- lgt_run((four(Four), asserta((foo :- Four)))).
   error(type_error(callable,4)).

% iso_asserta_1_07
?- lgt_run(asserta((atom(_) :- true))).
   error(permission_error(modify,static_procedure,atom/1))
|  error(permission_error(modify,static_procedure,':'(user,atom/1))).

% eddbali_asserta_1_08
?- lgt_run((once(findall(X-Y,(asserta(insct(bee)),insct(X),asserta(insct(ant)),insct(Y)),L)), L == [bee-ant, bee-bee])).
   true.

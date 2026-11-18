% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- dynamic(legs/2).
:- dynamic(insect/1).
:- dynamic(foo/1).

elk(X) :- moose(X).
legs(A, 4) :- animal(A).
legs(octopus, 8).
legs(A, 6) :- insect(A).
legs(spider, 8).
legs(B, 2) :- bird(B).
insect(ant).
insect(bee).
foo(X) :- call(X) -> call(X).
foo(X) :- call(X), call(X).

% iso_retract_1_01
?- retract(legs(octopus, 8)).
   true.

% iso_retract_1_02
?- retract(legs(spider, 6)).
   false.

% iso_retract_1_03
?- once(retract((legs(X, 2) :- T))), T == bird(X).
   true.

% iso_retract_1_04
?- once(findall(X-Y-Z,retract((legs(X,Y) :- Z)),L)), variant(L, [A-4-animal(A), B-6-insect(B), spider-8-true]).
   true.

% iso_retract_1_05
?- retract((legs(_X,_Y) :- _Z)).
   false.

% iso_retract_1_06
?- once((retract(insect(I)), retract(insect(bee)))), I == ant.
   true.

% iso_retract_1_07
?- retract((foo(A) :- A,call(A))).
   true.

% iso_retract_1_08
?- once(retract((foo(C) :- A -> B))), A-B == call(C)-call(C).
   true.

% iso_retract_1_09
?- retract((_X :- in_eec(_Y))).
   error(instantiation_error).

% iso_retract_1_10
?- retract((4 :- _X)).
   error(type_error(callable,4)).

% iso_retract_1_11
?- retract((atom(X) :- X =='[]')).
   error(permission_error(modify,static_procedure,atom/1))
|  error(permission_error(modify,static_procedure,':'(user,atom/1))).

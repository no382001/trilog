% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- dynamic(foo/1).
:- dynamic(insect/1).
:- dynamic(a/1).
:- dynamic(c/2).

foo(1).
foo(2).
foo(3).
elk(X) :- moose(X).
insect(ant).
insect(bee).
a(1).
a(2).
a(X) :- b(X).
b(3).
c(1, a).
c(1, 'A').
c(2, b).
c(2, 'B').
throws(lgt_retractall_1_07, error(instantiation_error,_)) :- retractall(_).
three(3).

% iso_retractall_1_01
?- once(retractall(foo(_))), current_predicate(foo/1).
   true.

% iso_retractall_1_02
?- retractall(insect(bee)).
   true.

% iso_retractall_1_03
?- retractall(insect(_)).
   true.

% iso_retractall_1_04
?- retractall(insect(spider)).
   true.

% iso_retractall_1_05
?- three(Three), retractall(Three).
   error(type_error(callable,3)).

% iso_retractall_1_06
?- retractall(retractall(_)).
   error(permission_error(modify,static_procedure,retractall/1))
|  error(permission_error(modify,static_procedure,':'(user,retractall/1))).

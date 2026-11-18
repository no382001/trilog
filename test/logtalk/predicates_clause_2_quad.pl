% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- dynamic(cat/0).
:- dynamic(dog/0).
:- dynamic(legs/2).
:- dynamic(insect/1).
:- dynamic(r/3).
:- dynamic(p/2).

cat.
dog :- true.
elk(X) :- moose(X).
legs(A, 6) :- insect(A).
legs(A, 7) :- A, call(A).
insect(ant).
insect(bee).
r(A, B, C) :- a(A), b(B), c(C).
a(_).
b(_).
c(_).
p(a(C), b(C)).

% iso_clause_2_01
?- lgt_run(clause(cat,true)).
   true.

% iso_clause_2_02
?- lgt_run(clause(dog,true)).
   true.

% iso_clause_2_03
?- lgt_run((once(clause(legs(I,6), Body)), Body == insect(I))).
   true.

% iso_clause_2_04
?- lgt_run((once(clause(legs(C,7), Body)), Body == (call(C),call(C)))).
   true.

% iso_clause_2_05
?- lgt_run((once(findall(I-T,clause(insect(I),T),L)), L == [ant-true, bee-true])).
   true.

% iso_clause_2_06
?- lgt_run(clause(x, _Body)).
   false.

% iso_clause_2_07
?- lgt_run(clause(_, _B)).
   error(instantiation_error).

% iso_clause_2_08
?- lgt_run(clause(4, _B)).
   error(type_error(callable,4)).

% iso_clause_2_09
?- lgt_run(catch(clause(elk(_N), _Body),Error,(Error = error(permission_error(access,private_procedure,elk/1),_) ; Error = error(permission_error(access,private_procedure,':'(user,elk/1)),_)))).
   true.

% iso_clause_2_10
?- lgt_run(clause(atom(_), _Body)).
   error(permission_error(access,private_procedure,atom/1))
|  error(permission_error(access,private_procedure,':'(user,atom/1))).

% iso_clause_2_11
?- lgt_run(clause(legs(A,6), insect(f(A)))).
   true.

% eddbali_clause_2_12
?- lgt_run(clause(f(_), 5)).
   error(type_error(callable,5)).

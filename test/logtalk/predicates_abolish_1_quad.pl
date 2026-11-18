% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- dynamic(insect/1).
:- dynamic(foo/1).

insect(ant).
insect(bee).
foo(X) :- call(X), call(X).
foo(X) :- call(X) -> call(X).
bar(_X) :- true.

% iso_abolish_1_01
?- abolish(foo/2).
   true.

% iso_abolish_1_02
?- abolish(foo/_).
   error(instantiation_error).

% iso_abolish_1_03
?- abolish(foo).
   error(type_error(predicate_indicator,foo))
|  error(type_error(predicate_indicator,':'(user,foo))).

% iso_abolish_1_04
?- abolish(foo(X)).
   error(type_error(predicate_indicator,foo(X)))
|  error(type_error(predicate_indicator,':'(user,foo(X)))).

% iso_abolish_1_05
?- abolish(abolish/1).
   error(permission_error(modify,static_procedure,abolish/1))
|  error(permission_error(modify,static_procedure,':'(user,abolish/1))).

% eddbali_abolish_1_06
?- abolish(foo/1).
   true.

% eddbali_abolish_1_07
?- once(findall(X,(insect(X), abolish(insect/1)),L)), L == [ant, bee].
   true.

% eddbali_abolish_1_08
?- abolish(bar/1).
   error(permission_error(modify,static_procedure,bar/1))
|  error(permission_error(modify,static_procedure,':'(user,bar/1))).

% eddbali_abolish_1_09
?- abolish(foo/a).
   error(type_error(integer,a)).

% eddbali_abolish_1_10
?- abolish(foo/(-1)).
   error(domain_error(not_less_than_zero,-1)).

% eddbali_abolish_1_12
?- abolish(5/2).
   error(type_error(atom,5)).

% eddbali_abolish_1_13
?- abolish(insect).
   error(type_error(predicate_indicator,insect))
|  error(type_error(predicate_indicator,':'(user,insect))).

% not converted:
% eddbali_abolish_1_11: condition \+ current_prolog_flag(max_arity,unbounded) is false for trilog

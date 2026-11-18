% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- dynamic(unicorn/0).
:- multifile(fenix/1).
:- discontiguous(scattered/2).

b(X) :- Y = (write(X), X), call(Y).
a(1).
a(2).
two(2).
goal(two(_)).
one(1).

% iso_call_1_01
?- call(!).
   true.

% iso_call_1_02
?- call(fail).
   false.

% iso_call_1_03
?- call((fail, _X)).
   false.

% iso_call_1_04
?- one(One), call((fail, call(One))).
   false.

% iso_call_1_05
?- suppress_text_output, b(_).
   error(instantiation_error).

% iso_call_1_06
?- suppress_text_output, b(3).
   error(type_error(callable,(write(3),3)))
|  error(type_error(callable,3)).

% iso_call_1_07
?- once((Z = !, call((Z=!, a(X), Z)))), Z-X == !-1.
   true.

% iso_call_1_08
?- once(findall(Z-X,call((Z=!, a(X), Z)),L)), L == [!-1, !-2].
   true.

% iso_call_1_09
?- suppress_text_output, call((write(3), _X)).
   error(instantiation_error).

% iso_call_1_10
?- suppress_text_output, one(One), call((write(3), call(One))).
   error(type_error(callable,1))
|  error(type_error(callable,':'(user,1))).

% iso_call_1_11
?- call(_X).
   error(instantiation_error).

% iso_call_1_12
?- one(One), call(One).
   error(type_error(callable,1))
|  error(type_error(callable,':'(user,1))).

% iso_call_1_13
?- one(One), call((fail, One)).
   error(type_error(callable,(fail,1)))
|  error(type_error(callable,1)).

% iso_call_1_14
?- suppress_text_output, one(One), call((write(3), One)).
   error(type_error(callable,(write(3),1)))
|  error(type_error(callable,1)).

% iso_call_1_15
?- one(One), call((One; true)).
   error(type_error(callable,(1;true)))
|  error(type_error(callable,1)).

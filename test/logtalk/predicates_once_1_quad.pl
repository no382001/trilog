% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
three(3).

% iso_once_1_01
?- once(!).
   true.

% iso_once_1_02
?- once(findall(X,(once(!), (X=1; X=2)),L)), L == [1, 2].
   true.

% iso_once_1_03
% lgtunit also checks that the goal is deterministic; quad does not
?- once(repeat).
   true.

% iso_once_1_04
?- once(fail).
   false.

% iso_once_1_05
?- once((X = f(X))).
   true.

% eddbali_once_1_06
?- three(G), once(G).
   error(type_error(callable,3))
|  error(type_error(callable,':'(user,3))).

% eddbali_once_1_07
?- variable(X), once(X).
   error(instantiation_error).

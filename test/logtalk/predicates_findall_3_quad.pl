% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

f(_, 1).
f(_, 2).
four(4).

% iso_findall_3_01
?- lgt_run((once(findall(X, (X=1;X=2), S)), S == [1,2])).
   true.

% iso_findall_3_02
?- lgt_run((once(findall(X+_Y, (X=1), S)), variant(S, [1+_]))).
   true.

% iso_findall_3_03
?- lgt_run((once(findall(_X, fail, L)), L == [])).
   true.

% iso_findall_3_04
?- lgt_run((once(findall(X, (X=1;X=1), S)), S == [1,1])).
   true.

% iso_findall_3_05
?- lgt_run(findall(X, (X=2;X=1), [1,2])).
   false.

% iso_findall_3_06
?- lgt_run((once(findall(X, (X=1;X=2), [X,Y])), X-Y == 1-2)).
   true.

% iso_findall_3_07
?- lgt_run(findall(_X, _Goal, _S)).
   error(instantiation_error).

% iso_findall_3_08
?- lgt_run((four(Four), findall(_X, Four, _S))).
   error(type_error(callable,4))
|  error(type_error(callable,':'(user,4))).

% sics_findall_3_09
?- lgt_run(findall(X, X=1, [A|1])).
   error(type_error(list,[A|1])).

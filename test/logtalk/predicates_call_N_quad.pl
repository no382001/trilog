% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

two(2).
call_n_maplist(_Cont, []).
call_n_maplist(Cont, [E|Es]) :- call(Cont, E), call_n_maplist(Cont, Es).
three(3).
variable(_).
goal(two, _).

% iso_call_N_01
?- call(integer, 3).
   true.

% iso_call_N_02
?- once(call(functor(F,c), 0)), F == c.
   true.

% iso_call_N_03
?- once(call(call(call(atom_concat, pro), log), Atom)), Atom == prolog.
   true.

% iso_call_N_04
?- once(findall(X-Y,call(;, X=1, Y=2),L)), variant(L, [1-_, _-2]).
   true.

% iso_call_N_05
?- call(;, (true->fail), _X=1).
   false.

% iso_call_N_06
?- call_n_maplist(>(3), [1, 2]).
   true.

% iso_call_N_07
?- call_n_maplist(>(3), [1, 2, 3]).
   false.

% iso_call_N_08
?- once(call_n_maplist(=(_X), Xs)), Xs == [].
   true.

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

quick_check(iso_term_variables_2_01, twice(+term)).
quick_check(iso_term_variables_2_02, chain(+term)).
twice(T) :- (term_variables(T, Vs1), term_variables(T, Vs2), Vs1 == Vs2).
chain(T) :- (term_variables(T, Vs1), term_variables(Vs1, Vs2), Vs1 == Vs2).

% iso_term_variables_2_03
?- once(term_variables(t, Vars)), Vars == [].
   true.

% iso_term_variables_2_04
?- once(term_variables(A+B*C/B-D, Vars)), Vars == [A, B, C, D].
   true.

% iso_term_variables_2_05
?- term_variables(t, [_, _|a]).
   error(type_error(list,[_,_|a])).

% iso_term_variables_2_06
?- (S=B+T, T=A*B, term_variables(S, Vars)), assertion(Vars == [B, A]), assertion(T == A*B), assertion(S == B+A*B).
   true.

% iso_term_variables_2_07
?- (T=A*B, S=B+T, term_variables(S, Vars)), assertion(Vars == [B, A]), assertion(T == A*B), assertion(S == B+A*B).
   true.

% iso_term_variables_2_08
?- term_variables(A+B+B, [B|Vars]), assertion(A == B), assertion(Vars == [B]).
   true.

% iso_term_variables_2_09
?- once(term_variables(_X+Vars, Vars)), subsumes_term([_, _], Vars).
   true.

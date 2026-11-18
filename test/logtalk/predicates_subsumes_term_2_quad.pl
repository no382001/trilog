% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_subsumes_term_2_01
?- lgt_run(subsumes_term(a, a)).
   true.

% iso_subsumes_term_2_02
?- lgt_run(subsumes_term(f(_X,_Y), f(Z,Z))).
   true.

% iso_subsumes_term_2_03
?- lgt_run(subsumes_term(f(Z,Z), f(_X,_Y))).
   false.

% iso_subsumes_term_2_04
?- lgt_run(subsumes_term(g(X), g(f(X)))).
   false.

% iso_subsumes_term_2_05
?- lgt_run(subsumes_term(X, f(X))).
   false.

% iso_subsumes_term_2_06
?- lgt_run((subsumes_term(X, Y), subsumes_term(Y, f(X)))).
   true.

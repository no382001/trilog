% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

succeeds(iso_acyclic_term_1_01) :- acyclic_term(a(1, _)).

% iso_acyclic_term_1_02
?- lgt_run((X = f(X), acyclic_term(X))).
   false.

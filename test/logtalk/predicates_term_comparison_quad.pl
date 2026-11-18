% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_term_comparison_01
?- '@=<'(1.0, 1).
   true.

% iso_term_comparison_02
?- '@<'(1.0, 1).
   true.

% iso_term_comparison_03
?- '\\=='(1, 1).
   false.

% iso_term_comparison_04
?- '@=<'(aardvark, zebra).
   true.

% iso_term_comparison_05
?- '@=<'(short, short).
   true.

% iso_term_comparison_06
?- '@=<'(short, shorter).
   true.

% iso_term_comparison_07
?- '@>='(short, shorter).
   false.

% iso_term_comparison_08
?- '@<'(foo(a,b), north(a)).
   false.

% iso_term_comparison_09
?- '@>'(foo(b), foo(a)).
   true.

% iso_term_comparison_10
?- '@<'(foo(a, _X), foo(b, _Y)).
   true.

% iso_term_comparison_11
?- '@<'(foo(_X, a), foo(_Y, b)) -> true ; true.
   true.

% iso_term_comparison_12
?- '@=<'(X, X).
   true.

% iso_term_comparison_13
?- '=='(X, X).
   true.

% iso_term_comparison_14
?- '@=<'(_X, _Y) -> true ; true.
   true.

% iso_term_comparison_15
?- '=='(_X, _Y).
   false.

% iso_term_comparison_16
?- \==(_, _).
   true.

% iso_term_comparison_17
?- '=='(_, _).
   false.

% iso_term_comparison_18
?- '@=<'(_, _) -> true ; true.
   true.

% iso_term_comparison_19
?- '@=<'(foo(_X, a), foo(_Y, b)) -> true ; true.
   true.

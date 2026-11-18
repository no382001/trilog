% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_term_comparison_01
?- lgt_run('@=<'(1.0, 1)).
   true.

% iso_term_comparison_02
?- lgt_run('@<'(1.0, 1)).
   true.

% iso_term_comparison_03
?- lgt_run('\\=='(1, 1)).
   false.

% iso_term_comparison_04
?- lgt_run('@=<'(aardvark, zebra)).
   true.

% iso_term_comparison_05
?- lgt_run('@=<'(short, short)).
   true.

% iso_term_comparison_06
?- lgt_run('@=<'(short, shorter)).
   true.

% iso_term_comparison_07
?- lgt_run('@>='(short, shorter)).
   false.

% iso_term_comparison_08
?- lgt_run('@<'(foo(a,b), north(a))).
   false.

% iso_term_comparison_09
?- lgt_run('@>'(foo(b), foo(a))).
   true.

% iso_term_comparison_10
?- lgt_run('@<'(foo(a, _X), foo(b, _Y))).
   true.

% iso_term_comparison_11
?- lgt_run(('@<'(foo(_X, a), foo(_Y, b)) -> true ; true)).
   true.

% iso_term_comparison_12
?- lgt_run('@=<'(X, X)).
   true.

% iso_term_comparison_13
?- lgt_run('=='(X, X)).
   true.

% iso_term_comparison_14
?- lgt_run(('@=<'(_X, _Y) -> true ; true)).
   true.

% iso_term_comparison_15
?- lgt_run('=='(_X, _Y)).
   false.

% iso_term_comparison_16
?- lgt_run(\==(_, _)).
   true.

% iso_term_comparison_17
?- lgt_run('=='(_, _)).
   false.

% iso_term_comparison_18
?- lgt_run(('@=<'(_, _) -> true ; true)).
   true.

% iso_term_comparison_19
?- lgt_run(('@=<'(foo(_X, a), foo(_Y, b)) -> true ; true)).
   true.

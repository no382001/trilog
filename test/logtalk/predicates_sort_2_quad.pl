% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_sort_2_01
?- lgt_run((once(sort([1, 1], Sorted)), Sorted == [1])).
   true.

% iso_sort_2_02
?- lgt_run((once(sort([1+Y, z, a, V, 1, 2, V, 1, 7.0, 8.0, 1+Y, 1+2, 8.0, -a, -X, a], Sorted)), Sorted == [V, 7.0, 8.0, 1, 2, a, z, -X, -a, 1+Y, 1+2])).
   true.

% iso_sort_2_03
?- lgt_run(sort([1, 1], [1, 1])).
   false.

% iso_sort_2_04
?- lgt_run(sort([V], V)).
   true.

% iso_sort_2_05
?- lgt_run((once(sort([f(U),U,U,f(V),f(U),V], L)), (L == [U,V,f(U),f(V)] ; L == [V,U,f(V),f(U)]))).
   true.

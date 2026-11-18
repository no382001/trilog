% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_keysort_2_01
?- once(keysort([1-1, 1-1], Sorted)), Sorted == [1-1, 1-1].
   true.

% iso_keysort_2_02
?- once(keysort([2-99, 1-a, 3-f(X), 1-z, 1-a, 2-44], Sorted)), Sorted == [1-a, 1-z, 1-a, 2-99, 2-44, 3-f(X)].
   true.

% iso_keysort_2_03
?- once(keysort([X-1,1-1],[2-1,1-1])), X == 2.
   true.

% iso_keysort_2_05
?- keysort([V-V], V).
   true.

% not converted:
% iso_keysort_2_04: marked skipped by Logtalk

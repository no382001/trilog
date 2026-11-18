% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_compare_3_01
?- once(compare(Order, 3, 5)), Order == (<).
   true.

% iso_compare_3_02
?- once(compare(Order, d, d)), Order == (=).
   true.

% iso_compare_3_03
?- once(compare(Order, Order, <)), Order == (<).
   true.

% iso_compare_3_04
?- compare(<, <, <).
   false.

% iso_compare_3_05
?- compare(1+2, 3, 3.0).
   error(type_error(atom,1+2)).

% iso_compare_3_06
?- compare(>=, 3, 3.0).
   error(domain_error(order,>=)).

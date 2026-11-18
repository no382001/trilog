% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_ground_1_01
?- lgt_run(ground(3)).
   true.

% iso_ground_1_02
?- lgt_run(ground(a(1, _))).
   false.

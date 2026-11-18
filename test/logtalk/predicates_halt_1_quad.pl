% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_halt_1_01
?- lgt_run(halt(a)).
   error(type_error(integer,a)).

% eddbali_halt_1_02
?- lgt_run(halt(_)).
   error(instantiation_error).

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_nl_1_01
?- lgt_run(nl(_)).
   error(instantiation_error).

% iso_nl_1_03
?- lgt_run(nl(user_input)).
   error(permission_error(output, stream, user_input)).

:- clean_binary_output.

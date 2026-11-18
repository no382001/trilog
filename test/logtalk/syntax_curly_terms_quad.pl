% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_curly_bracketed_term_01
?- lgt_run((once((set_text_input('{a}. '), read(T))), T == '{}'(a))).
   true.

% iso_curly_bracketed_term_02
?- lgt_run((once((set_text_input('{a,b}. '), read(T))), T == '{}'(','(a,b)))).
   true.

:- clean_text_input, clean_text_output.

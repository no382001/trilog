% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_term_01
?- lgt_run((set_text_input('f(x,y). '), read(_))).
   true.

% iso_term_02
?- lgt_run((set_text_input('f(:-, ;, [:-, :-|:-]). '), read(_))).
   true.

% iso_term_03
?- lgt_run((set_text_input('f(,,a). '), read(_))).
   error(syntax_error(_)).

% iso_term_04
?- lgt_run((set_text_input('[a,,|v]. '), read(_))).
   error(syntax_error(_)).

% iso_term_05
?- lgt_run((set_text_input('[a,b|,]. '), read(_))).
   error(syntax_error(_)).

% iso_term_06
?- lgt_run((set_text_input('f(\',\',a). '), read(_))).
   true.

% iso_term_07
?- lgt_run((set_text_input('[a,\',\'|v]. '), read(_))).
   true.

% iso_term_08
?- lgt_run((set_text_input('[a,b|\',\']. '), read(_))).
   true.

:- clean_text_input.

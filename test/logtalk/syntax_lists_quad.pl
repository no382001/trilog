% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_list_01
?- once((set_text_input('[a]. '), read(T))), T == .(a, []).
   true.

% iso_list_02
?- once((set_text_input('[a,b]. '), read(T))), T == .(a, .(b, [])).
   true.

% iso_list_03
?- once((set_text_input('[a|b]. '), read(T))), T == .(a, b).
   true.

:- clean_text_input.

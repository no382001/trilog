% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_atom_01
?- lgt_run((once((set_text_input('a. '), read(T))), atom(T))).
   true.

% iso_atom_02
?- lgt_run((once((set_text_input('\'A\'. '), read(T))), atom(T))).
   true.

% iso_atom_03
?- lgt_run((once((set_text_input('\'a''''b\'. '), read(T))), atom(T))).
   true.

% iso_atom_04
?- lgt_run((once((set_text_input('\'a\\\'b\'. '), read(T))), atom(T))).
   true.

% iso_atom_05
?- lgt_run((once((set_text_input('\'a\\\"b\'. '), read(T))), atom(T))).
   true.

% iso_atom_06
?- lgt_run((once((set_text_input('\'a\\\\b\'. '), read(T))), atom(T))).
   true.

% iso_atom_07
?- lgt_run((once((set_text_input('\'a\\123\\b\'. '), read(T))), T == 'aSb')).
   true.

% iso_atom_08
?- lgt_run((once((set_text_input('\'a\\x53\\b\'. '), read(T))), T == 'aSb')).
   true.

:- clean_text_input.

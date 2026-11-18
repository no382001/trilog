% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_line_comment_01
?- lgt_run((once((set_text_input('% abc\n'), read(T))), T == end_of_file)).
   true.

% iso_line_comment_02
?- lgt_run((once((set_text_input('% abc\na.\n% def\n'), (read(T1), read(T2)))), T1-T2 == a-end_of_file)).
   true.

% iso_block_comment_01
?- lgt_run((once((set_text_input('/* abc\ndef\n*/\n'), read(T))), T == end_of_file)).
   true.

% iso_block_comment_02
?- lgt_run((once((set_text_input('/* abc */\na.\n/* def */\n'), (read(T1), read(T2)))), T1-T2 == a-end_of_file)).
   true.

% iso_block_comment_03
?- lgt_run((once((set_text_input('/* /* */\na.\n/* /* */\n'), (read(T1), read(T2)))), T1-T2 == a-end_of_file)).
   true.

% iso_block_comment_04
?- lgt_run((set_text_input('/* */ */\n'), read(_))).
   error(syntax_error(_)).

% iso_block_comment_05
?- lgt_run((set_text_input('/* \n'), read(_))).
   error(syntax_error(_)).

:- clean_text_input.

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

double_quotes_example_1([ '(      current_prolog_flag(double_quotes, chars), atom_chars(\'jim\', "jim")', ';      current_prolog_flag(double_quotes, codes), atom_codes(\'jim\', "jim")', ';      current_prolog_flag(double_quotes, atom), \'jim\' == "jim"', '). ' ]).
double_quotes_example_2([ '(      current_prolog_flag(double_quotes, chars), [] == ""', ';      current_prolog_flag(double_quotes, codes), [] == ""', ';      current_prolog_flag(double_quotes, atom), \'\' == ""', '). ' ]).

% iso_double_quoted_term_01
?- double_quotes_example_1(Contents), set_text_input(Contents), set_prolog_flag(double_quotes, chars), (read(Goal), call(Goal)).
   true.

% iso_double_quoted_term_02
?- double_quotes_example_1(Contents), set_text_input(Contents), set_prolog_flag(double_quotes, codes), (read(Goal), call(Goal)).
   true.

% iso_double_quoted_term_03
?- double_quotes_example_1(Contents), set_text_input(Contents), set_prolog_flag(double_quotes, atom), (read(Goal), call(Goal)).
   true.

% iso_double_quoted_term_04
?- double_quotes_example_2(Contents), set_text_input(Contents), set_prolog_flag(double_quotes, chars), (read(Goal), call(Goal)).
   true.

% iso_double_quoted_term_05
?- double_quotes_example_2(Contents), set_text_input(Contents), set_prolog_flag(double_quotes, codes), (read(Goal), call(Goal)).
   true.

% iso_double_quoted_term_06
?- double_quotes_example_2(Contents), set_text_input(Contents), set_prolog_flag(double_quotes, atom), (read(Goal), call(Goal)).
   true.

% iso_double_quoted_term_07
?- once((set_text_input('"jim". '), set_prolog_flag(double_quotes, chars), read(T))), atom_chars('jim', T).
   true.

% iso_double_quoted_term_08
?- once((set_text_input('"jim". '), set_prolog_flag(double_quotes, codes), read(T))), atom_codes('jim', T).
   true.

% iso_double_quoted_term_09
?- once((set_text_input('"jim". '), set_prolog_flag(double_quotes, atom), read(T))), T == 'jim'.
   true.

% iso_double_quoted_term_10
?- once((set_text_input('"". '), set_prolog_flag(double_quotes, chars), read(T))), T == [].
   true.

% iso_double_quoted_term_11
?- once((set_text_input('"". '), set_prolog_flag(double_quotes, codes), read(T))), T == [].
   true.

% iso_double_quoted_term_12
?- once((set_text_input('"". '), set_prolog_flag(double_quotes, atom), read(T))), T == ''.
   true.

:- clean_text_input.

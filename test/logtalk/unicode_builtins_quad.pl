% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- lgt_files('unicode_builtins').

valid('US-ASCII').
valid('UTF-8').
valid('UTF-16BE').
valid('UTF-16LE').
valid('UTF-16').
valid('UTF-32BE').
valid('UTF-32LE').
valid('UTF-32').
valid('ISO-8859-1').
valid('ISO-8859-2').
valid('ISO-8859-3').
valid('ISO-8859-4').
valid('ISO-8859-5').
valid('ISO-8859-6').
valid('ISO-8859-7').
valid('ISO-8859-8').
valid('ISO-8859-9').
valid('ISO-8859-10').

% sics_unicode_atom_chars_2_14
?- lgt_run((once(atom_chars('Pécs', L)), L == ['P','é','c','s'])).
   true.

% sics_unicode_atom_chars_2_15
?- lgt_run((once(atom_chars(A, ['P','é','c','s'])), A == 'Pécs')).
   true.

% sics_unicode_atom_codes_2_12
?- lgt_run((once(atom_codes('Pécs', C)), C == [0'P,0'é,0'c,0's])).
   true.

% sics_unicode_atom_codes_2_13
?- lgt_run((once(atom_codes(A, [0'P,0'é,0'c,0's])), A == 'Pécs')).
   true.

% sics_unicode_atom_concat_3_11
?- lgt_run((once(atom_concat('Bartók ', 'Béla', N)), N == 'Bartók Béla')).
   true.

% sics_unicode_atom_concat_3_12
?- lgt_run((once(atom_concat(N, 'Béla', 'Bartók Béla')), N == 'Bartók ')).
   true.

% sics_unicode_atom_concat_3_13
?- lgt_run((once(atom_concat('Bartók ', N, 'Bartók Béla')), N == 'Béla')).
   true.

% sics_unicode_atom_concat_3_14
?- lgt_run((once(findall(T1-T2,atom_concat(T1, T2, 'Pécs'),L)), L == [''-'Pécs', 'P'-'écs', 'Pé'-'cs', 'Péc'-'s', 'Pécs'-''])).
   true.

% sics_unicode_atom_length_2_10
?- lgt_run((once(atom_length('Bartók Béla', N)), N == 11)).
   true.

% sics_unicode_sub_atom_5_31
?- lgt_run((once(sub_atom('Bartók Béla', 4, 2, A, S)), A-S == 5-'ók')).
   true.

% sics_unicode_sub_atom_5_32
?- lgt_run((once(sub_atom('Bartók Béla', 4, L, 5, S)), L-S == 2-'ók')).
   true.

% sics_unicode_sub_atom_5_33
?- lgt_run((once(sub_atom('Bartók Béla', B, 2, 5, S)), B-S == 4-'ók')).
   true.

% sics_unicode_sub_atom_5_34
?- lgt_run((once(findall(B-A-S,sub_atom('Pécs',B,2,A,S),L)), L == [0-2-'Pé', 1-1-'éc', 2-0-'cs'])).
   true.

% sics_unicode_sub_atom_5_35
?- lgt_run((once(findall(B-L-A,sub_atom(abracadabra,B,L,A,abra),L)), L == [0-4-7, 7-4-0])).
   true.

:- clean_text_input, clean_text_output, clean_file(sample_utf_8), clean_file(sample_utf_8_bom), clean_file(sample_utf_8_no_bom).

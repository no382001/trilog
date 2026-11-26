% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_atom_chars_2_01
?- once(atom_chars('', L)), L == [].
   true.

% iso_atom_chars_2_02
?- once(atom_chars([], L)), L == ['[',']'].
   true.

% iso_atom_chars_2_03
?- once(atom_chars('''', L)), L == [''''].
   true.

% iso_atom_chars_2_04
?- once(atom_chars('ant', L)), L == ['a','n','t'].
   true.

% iso_atom_chars_2_05
?- once(atom_chars(Str, ['s','o','p'])), Str == 'sop'.
   true.

% iso_atom_chars_2_06
?- once(atom_chars('North', ['N'| X])), X == ['o','r','t','h'].
   true.

% iso_atom_chars_2_07
?- atom_chars('soap', ['s','o','p']).
   false.

% iso_atom_chars_2_08
?- atom_chars(_X, _Y).
   error(instantiation_error).

% eddbali_atom_chars_2_09
?- atom_chars(_A, [a,_E,c]).
   error(instantiation_error).

% eddbali_atom_chars_2_10
?- atom_chars(_A, [a,b|_L]).
   error(instantiation_error).

% eddbali_atom_chars_2_11
?- atom_chars(f(a), _L).
   error(type_error(atom,f(a))).

% eddbali_atom_chars_2_12
?- atom_chars(_A, iso).
   error(type_error(list,iso)).

% eddbali_atom_chars_2_13
?- atom_chars(_A, [a,f(b)]).
   error(type_error(character,f(b))).

% not converted:
% sics_atom_chars_2_14: marked skipped by Logtalk
% sics_atom_chars_2_15: marked skipped by Logtalk

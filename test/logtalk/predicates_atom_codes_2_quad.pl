% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_atom_codes_2_01
?- once(atom_codes('', L)), L == [].
   true.

% iso_atom_codes_2_02
?- once(atom_codes([], L)), L == [0'[, 0']].
   true.

% iso_atom_codes_2_03
?- once(atom_codes('''', L)), L == [39].
   true.

% iso_atom_codes_2_04
?- once(atom_codes('ant', L)), L == [0'a, 0'n, 0't].
   true.

% iso_atom_codes_2_05
?- once(atom_codes(Str, [0's,0'o,0'p])), Str == 'sop'.
   true.

% iso_atom_codes_2_06
?- once(atom_codes('North', [0'N| X])), X == [0'o,0'r,0't,0'h].
   true.

% iso_atom_codes_2_07
?- atom_codes('soap', [0's, 0'o, 0'p]).
   false.

% iso_atom_codes_2_08
?- atom_codes(_X, _Y).
   error(instantiation_error).

% eddbali_atom_codes_2_09
?- atom_codes(f(a), _L).
   error(type_error(atom,f(a))).

% eddbali_atom_codes_2_10
?- atom_codes(_, 0'x).
   error(type_error(list,0'x)).

% eddbali_atom_codes_2_11
?- atom_codes(_A, [0'i,0's,-1]).
   error(representation_error(character_code)).

% not converted:
% sics_atom_codes_2_12: marked skipped by Logtalk
% sics_atom_codes_2_13: marked skipped by Logtalk

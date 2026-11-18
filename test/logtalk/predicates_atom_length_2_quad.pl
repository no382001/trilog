% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_atom_length_2_01
?- once(atom_length('enchanted evening', N)), N == 17.
   true.

% iso_atom_length_2_02
?- once(atom_length('enchanted evening', N)), N == 17.
   true.

% iso_atom_length_2_03
?- once(atom_length('', N)), N == 0.
   true.

% iso_atom_length_2_04
?- atom_length('scarlet', 5).
   false.

% iso_atom_length_2_05
?- atom_length(_Atom, 4).
   error(instantiation_error).

% iso_atom_length_2_06
?- atom_length(1.23, 4).
   error(type_error(atom,1.23)).

% iso_atom_length_2_07
?- atom_length(atom, '4').
   error(type_error(integer,'4')).

% eddbali_atom_length_2_08
?- atom_length(atom, -4).
   error(domain_error(not_less_than_zero,-4)).

% not converted:
% sics_atom_length_2_09: marked skipped by Logtalk

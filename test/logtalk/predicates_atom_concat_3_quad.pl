% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_atom_concat_3_01
?- lgt_run((once(atom_concat('hello', ' world', S3)), S3 == 'hello world')).
   true.

% iso_atom_concat_3_02
?- lgt_run((once(atom_concat(S1, ' world', 'small world')), S1 == 'small')).
   true.

% iso_atom_concat_3_03
?- lgt_run(atom_concat('hello',' world', 'small world')).
   false.

% iso_atom_concat_3_04
?- lgt_run((once(findall(T1-T2,atom_concat(T1, T2, 'hello'),L)), L == [''-'hello', 'h'-'ello', 'he'-'llo', 'hel'-'lo', 'hell'-'o', 'hello'-''])).
   true.

% iso_atom_concat_3_05
?- lgt_run(atom_concat(small, _V2, _V4)).
   error(instantiation_error).

% eddbali_atom_concat_3_06
?- lgt_run(atom_concat(_A, 'iso', _C)).
   error(instantiation_error).

% eddbali_atom_concat_3_07
?- lgt_run(atom_concat('iso', _B, _C)).
   error(instantiation_error).

% eddbali_atom_concat_3_08
?- lgt_run(atom_concat(f(a), 'iso', _C)).
   error(type_error(atom,f(a))).

% eddbali_atom_concat_3_09
?- lgt_run(atom_concat('iso', f(a), _C)).
   error(type_error(atom,f(a))).

% eddbali_atom_concat_3_10
?- lgt_run(atom_concat(_A, _B, f(a))).
   error(type_error(atom,f(a))).

% not converted:
% sics_atom_concat_3_11: marked skipped by Logtalk
% sics_atom_concat_3_12: marked skipped by Logtalk
% sics_atom_concat_3_13: marked skipped by Logtalk
% sics_atom_concat_3_14: marked skipped by Logtalk

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_sub_atom_5_01
?- lgt_run((once(sub_atom(abracadabra, 0, 5, _, S2)), S2 == 'abrac')).
   true.

% iso_sub_atom_5_02
?- lgt_run((once(sub_atom(abracadabra, _, 5, 0, S2)), S2 == 'dabra')).
   true.

% iso_sub_atom_5_03
?- lgt_run((once(sub_atom(abracadabra, 3, Length, 3, S2)), Length-S2 == 5-'acada')).
   true.

% iso_sub_atom_5_04
?- lgt_run((once(findall(Before-After,sub_atom(abracadabra,Before,2,After,ab),L)), L == [0-9, 7-2])).
   true.

% iso_sub_atom_5_05
?- lgt_run((once(sub_atom('Banana', 3, 2, _, S2)), S2 == 'an')).
   true.

% iso_sub_atom_5_06
?- lgt_run((once(findall(S2,sub_atom('charity',_,3,_,S2),L)), L == ['cha', 'har', 'ari', 'rit', 'ity'])).
   true.

% iso_sub_atom_5_07
?- lgt_run((once(findall(Start-Lenght-SubAtom,sub_atom('ab',Start,Lenght,_,SubAtom),L)), L == [0-0-'', 0-1-'a', 0-2-'ab', 1-0-'', 1-1-'b', 2-0-''])).
   true.

% eddbali_sub_atom_5_08
?- lgt_run(sub_atom(_Banana, 3, 2, _, _S)).
   error(instantiation_error).

% eddbali_sub_atom_5_09
?- lgt_run(sub_atom(f(a), 2, 2, _, _S2)).
   error(type_error(atom,f(a))).

% eddbali_sub_atom_5_10
?- lgt_run(sub_atom('Banana', 4, 2, _, 2)).
   error(type_error(atom,2)).

% eddbali_sub_atom_5_11
?- lgt_run(sub_atom('Banana', a, 2, _, _)).
   error(type_error(integer,a)).

% eddbali_sub_atom_5_12
?- lgt_run(sub_atom('Banana', 4, n, _, _)).
   error(type_error(integer,n)).

% eddbali_sub_atom_5_13
?- lgt_run(sub_atom('Banana', 4, _, m, _)).
   error(type_error(integer,m)).

% sics_sub_atom_5_14
?- lgt_run(sub_atom('Banana', -2, 3, 4, _)).
   error(domain_error(not_less_than_zero,-2)).

% sics_sub_atom_5_15
?- lgt_run(sub_atom('Banana', 2, -3, 4, _)).
   error(domain_error(not_less_than_zero,-3)).

% sics_sub_atom_5_16
?- lgt_run(sub_atom('Banana', 2, 3, -4, _)).
   error(domain_error(not_less_than_zero,-4)).

% sics_sub_atom_5_17
?- lgt_run((once(sub_atom('Banana', 2, 3, A, 'nan')), A == 1)).
   true.

% sics_sub_atom_5_18
?- lgt_run((once(sub_atom('Banana', B, 3, 1, 'nan')), B == 2)).
   true.

% sics_sub_atom_5_19
?- lgt_run((once(sub_atom('Banana', 2, L, 1, 'nan')), L == 3)).
   true.

% sics_sub_atom_5_20
?- lgt_run((once(sub_atom('Banana', 2, L, A, 'nan')), A-L == 1-3)).
   true.

% sics_sub_atom_5_21
?- lgt_run((once(sub_atom('Banana', B, L, 1, 'nan')), B-L == 2-3)).
   true.

% sics_sub_atom_5_22
?- lgt_run(sub_atom('Banana', 2, 3, 1, 'ana')).
   false.

% sics_sub_atom_5_23
?- lgt_run(sub_atom('Banana', 2, 3, 2, 'nan')).
   false.

% sics_sub_atom_5_24
?- lgt_run(sub_atom('Banana', 2, 3, 2, _)).
   false.

% sics_sub_atom_5_25
?- lgt_run(sub_atom('Banana', 2, 3, 1, 'anan')).
   false.

% sics_sub_atom_5_26
?- lgt_run(sub_atom('Banana', 0, 7, 0, _)).
   false.

% sics_sub_atom_5_27
?- lgt_run(sub_atom('Banana', 7, 0, 0, _)).
   false.

% sics_sub_atom_5_28
?- lgt_run(sub_atom('Banana', 0, 0, 7, _)).
   false.

% sics_sub_atom_5_33
?- lgt_run((once(findall(B-L-A,sub_atom(abracadabra,B,L,A,abra),L)), L == [0-4-7, 7-4-0])).
   true.

% not converted:
% sics_sub_atom_5_29: marked skipped by Logtalk
% sics_sub_atom_5_30: marked skipped by Logtalk
% sics_sub_atom_5_31: marked skipped by Logtalk
% sics_sub_atom_5_32: marked skipped by Logtalk

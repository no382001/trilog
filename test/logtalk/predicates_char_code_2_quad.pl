% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_char_code_2_01
?- once(char_code(a, Code)), Code == 0'a.
   true.

% iso_char_code_2_02
?- once((char_code(Char, 99), atom_codes(Atom, [99]))), Char == Atom.
   true.

% iso_char_code_2_03
?- once(char_code(Char, 0'c)), Char == c.
   true.

% iso_char_code_2_04
?- catch(char_code(_Char, 163),Error,true), (var(Error) -> true ; subsumes_term(error(representation_error(character_code),_), Error)).
   true.

% iso_char_code_2_05
?- char_code(b, 0'b).
   true.

% iso_char_code_2_06
?- char_code('ab', _Code).
   error(type_error(character,'ab')).

% iso_char_code_2_07
?- char_code(_Char, _Code).
   error(instantiation_error).

% eddbali_char_code_2_08
?- char_code(a, x).
   error(type_error(integer,x)).

% eddbali_char_code_2_09
?- char_code(_Char, -2).
   error(representation_error(character_code)).

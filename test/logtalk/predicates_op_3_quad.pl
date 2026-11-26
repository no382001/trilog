% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

o(1).
o(2).
o(3).

% iso_op_3_01
?- op(30, xfy, ++), (current_op(30, xfy, ++), op(0, xfy, ++)).
   true.

% iso_op_3_02
?- (op(30, xfy, ++), op(0, xfy, ++)), \+ current_op(_, xfy, ++).
   true.

% iso_op_3_03
?- op(max, xfy, ++).
   error(type_error(integer,max)).

% iso_op_3_04
?- op(-30, xfy, ++).
   error(domain_error(operator_priority,-30)).

% iso_op_3_05
?- op(1201, xfy, ++).
   error(domain_error(operator_priority,1201)).

% iso_op_3_06
?- op(30, _XFY, ++).
   error(instantiation_error).

% iso_op_3_07
?- op(30, yfy, ++).
   error(domain_error(operator_specifier,yfy)).

% iso_op_3_08
?- op(30, xfy, 0).
   error(type_error(list,0)).

% iso_op_3_09
?- (op(30, xfy, ++), op(40, xfx, ++)), (current_op(40, xfx, ++), op(0, xfx, ++)).
   true.

% iso_op_3_10
?- op(30, xfy, ++), op(50, yf, ++).
   error(permission_error(create,operator,++)).

% iso_op_3_11
?- op(500, xfy, []).
   error(permission_error(create,operator,[])).

% iso_op_3_12
?- op(500, xfy, [[]]).
   error(permission_error(create,operator,[])).

% iso_op_3_13
?- op(500, xfy, {}).
   error(permission_error(create,operator,{})).

% iso_op_3_14
?- op(500, xfy, [{}]).
   error(permission_error(create,operator,{})).

% iso_op_3_15
?- op(1000, xfy, '|').
   error(permission_error(create,operator,'|')).

% iso_op_3_16
?- op(1000, xfy, ['|']).
   error(permission_error(create,operator,'|')).

% iso_op_3_17
?- op(1000, fx, '|').
   error(permission_error(create,operator,'|')).

% iso_op_3_18
?- op(333, xfy, [abc, abc, abc]), current_op(333, xfy, abc).
   true.

% iso_op_3_19
?- op(0, xfx, (',')).
   error(permission_error(modify,operator,(','))).

% iso_op_3_20
?- once((set_text_output(''), ((op(555, fx, o), o(X), write(o(X)), nl, op(555, xf, o), fail) ; text_output_assertion('o 1\no 2\no 3\n', Assertion)))), Assertion.
   true.

% iso_op_3_21
?- op(1105, xfy, '|'), current_op(Priority, Specifier, '|'), Priority == 1105, Specifier == xfy.
   true.

% iso_op_3_22
?- op(0, xfy, '|'), \+ current_op(_, xfy, '|').
   true.

% sics_op_3_23
?- op(_, xfx, ++).
   error(instantiation_error).

% sics_op_3_24
?- op(100, xfx, _).
   error(instantiation_error).

% sics_op_3_25
?- op(100, xfx, [a|_]).
   error(instantiation_error).

% sics_op_3_26
?- op(100, xfx, [a,_]).
   error(instantiation_error).

% sics_op_3_27
?- op(100, 200, [a]).
   error(type_error(atom,200)).

% sics_op_3_28
?- op(100, f(1), [a]).
   error(type_error(atom,f(1))).

% sics_op_3_29
?- op(100, xfx, [a,a+b]).
   error(type_error(atom,a+b)).

% sics_op_3_30
?- op(100, xfx, (',')).
   error(permission_error(modify,operator,(','))).

% sics_op_3_31
?- op(100, xfx, [a,(',')]).
   error(permission_error(modify,operator,(','))).

:- clean_text_input.

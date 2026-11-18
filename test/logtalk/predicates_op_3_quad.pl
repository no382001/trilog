% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

o(1).
o(2).
o(3).

% iso_op_3_01
?- lgt_run((op(30, xfy, ++), (current_op(30, xfy, ++), op(0, xfy, ++)))).
   true.

% iso_op_3_02
?- lgt_run(((op(30, xfy, ++), op(0, xfy, ++)), \+ current_op(_, xfy, ++))).
   true.

% iso_op_3_03
?- lgt_run(op(max, xfy, ++)).
   error(type_error(integer,max)).

% iso_op_3_04
?- lgt_run(op(-30, xfy, ++)).
   error(domain_error(operator_priority,-30)).

% iso_op_3_05
?- lgt_run(op(1201, xfy, ++)).
   error(domain_error(operator_priority,1201)).

% iso_op_3_06
?- lgt_run(op(30, _XFY, ++)).
   error(instantiation_error).

% iso_op_3_07
?- lgt_run(op(30, yfy, ++)).
   error(domain_error(operator_specifier,yfy)).

% iso_op_3_08
?- lgt_run(op(30, xfy, 0)).
   error(type_error(list,0)).

% iso_op_3_09
?- lgt_run(((op(30, xfy, ++), op(40, xfx, ++)), (current_op(40, xfx, ++), op(0, xfx, ++)))).
   true.

% iso_op_3_10
?- lgt_run((op(30, xfy, ++), op(50, yf, ++))).
   error(permission_error(create,operator,++)).

% iso_op_3_11
?- lgt_run(op(500, xfy, [])).
   error(permission_error(create,operator,[])).

% iso_op_3_12
?- lgt_run(op(500, xfy, [[]])).
   error(permission_error(create,operator,[])).

% iso_op_3_13
?- lgt_run(op(500, xfy, {})).
   error(permission_error(create,operator,{})).

% iso_op_3_14
?- lgt_run(op(500, xfy, [{}])).
   error(permission_error(create,operator,{})).

% iso_op_3_15
?- lgt_run(op(1000, xfy, '|')).
   error(permission_error(create,operator,'|')).

% iso_op_3_16
?- lgt_run(op(1000, xfy, ['|'])).
   error(permission_error(create,operator,'|')).

% iso_op_3_17
?- lgt_run(op(1000, fx, '|')).
   error(permission_error(create,operator,'|')).

% iso_op_3_18
?- lgt_run((op(333, xfy, [abc, abc, abc]), current_op(333, xfy, abc))).
   true.

% iso_op_3_19
?- lgt_run(op(0, xfx, (','))).
   error(permission_error(modify,operator,(','))).

% iso_op_3_20
?- lgt_run((once((set_text_output(''), ((op(555, fx, o), o(X), write(o(X)), nl, op(555, xf, o), fail) ; text_output_assertion('o 1\no 2\no 3\n', Assertion)))), Assertion)).
   true.

% iso_op_3_21
?- lgt_run((op(1105, xfy, '|'), current_op(Priority, Specifier, '|'), Priority == 1105, Specifier == xfy)).
   true.

% iso_op_3_22
?- lgt_run((op(0, xfy, '|'), \+ current_op(_, xfy, '|'))).
   true.

% sics_op_3_23
?- lgt_run(op(_, xfx, ++)).
   error(instantiation_error).

% sics_op_3_24
?- lgt_run(op(100, xfx, _)).
   error(instantiation_error).

% sics_op_3_25
?- lgt_run(op(100, xfx, [a|_])).
   error(instantiation_error).

% sics_op_3_26
?- lgt_run(op(100, xfx, [a,_])).
   error(instantiation_error).

% sics_op_3_27
?- lgt_run(op(100, 200, [a])).
   error(type_error(atom,200)).

% sics_op_3_28
?- lgt_run(op(100, f(1), [a])).
   error(type_error(atom,f(1))).

% sics_op_3_29
?- lgt_run(op(100, xfx, [a,a+b])).
   error(type_error(atom,a+b)).

% sics_op_3_30
?- lgt_run(op(100, xfx, (','))).
   error(permission_error(modify,operator,(','))).

% sics_op_3_31
?- lgt_run(op(100, xfx, [a,(',')])).
   error(permission_error(modify,operator,(','))).

:- clean_text_input.

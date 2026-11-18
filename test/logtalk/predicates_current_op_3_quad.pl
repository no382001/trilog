% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

infix(yfx).
infix(xfx).
infix(xfy).

% iso_current_op_3_01
?- lgt_run((current_op(P, T, ':-'), P-T == 1200-xfx)).
   true.

% iso_current_op_3_02
?- lgt_run((current_op(P, T, '-->'), P-T == 1200-xfx)).
   true.

% iso_current_op_3_03
?- lgt_run((current_op(P, T, ':-'), P-T == 1200-fx)).
   true.

% iso_current_op_3_04
?- lgt_run((current_op(P, T, '?-'), P-T == 1200-fx)).
   true.

% iso_current_op_3_05
?- lgt_run((current_op(P, T, ';'), P-T == 1100-xfy)).
   true.

% iso_current_op_3_06
?- lgt_run((current_op(P, T, '->'), P-T == 1050-xfy)).
   true.

% iso_current_op_3_07
?- lgt_run((current_op(P, T, ','), P-T == 1000-xfy)).
   true.

% iso_current_op_3_08
?- lgt_run((current_op(P, T, '\\+'), P-T == 900-fy)).
   true.

% iso_current_op_3_09
?- lgt_run((current_op(P, T, '='), P-T == 700-xfx)).
   true.

% iso_current_op_3_10
?- lgt_run((current_op(P, T, '\\='), P-T == 700-xfx)).
   true.

% iso_current_op_3_11
?- lgt_run((current_op(P, T, '=='), P-T == 700-xfx)).
   true.

% iso_current_op_3_12
?- lgt_run((current_op(P, T, '\\=='), P-T == 700-xfx)).
   true.

% iso_current_op_3_13
?- lgt_run((current_op(P, T, '@<'), P-T == 700-xfx)).
   true.

% iso_current_op_3_14
?- lgt_run((current_op(P, T, '@=<'), P-T == 700-xfx)).
   true.

% iso_current_op_3_15
?- lgt_run((current_op(P, T, '@>'), P-T == 700-xfx)).
   true.

% iso_current_op_3_16
?- lgt_run((current_op(P, T, '@>='), P-T == 700-xfx)).
   true.

% iso_current_op_3_17
?- lgt_run((current_op(P, T, '=..'), P-T == 700-xfx)).
   true.

% iso_current_op_3_18
?- lgt_run((current_op(P, T, 'is'), P-T == 700-xfx)).
   true.

% iso_current_op_3_19
?- lgt_run((current_op(P, T, '=:='), P-T == 700-xfx)).
   true.

% iso_current_op_3_20
?- lgt_run((current_op(P, T, '=\\='), P-T == 700-xfx)).
   true.

% iso_current_op_3_21
?- lgt_run((current_op(P, T, '<'), P-T == 700-xfx)).
   true.

% iso_current_op_3_22
?- lgt_run((current_op(P, T, '=<'), P-T == 700-xfx)).
   true.

% iso_current_op_3_23
?- lgt_run((current_op(P, T, '>'), P-T == 700-xfx)).
   true.

% iso_current_op_3_24
?- lgt_run((current_op(P, T, '>='), P-T == 700-xfx)).
   true.

% iso_current_op_3_25
?- lgt_run((current_op(P, T, '+'), P-T == 500-yfx)).
   true.

% iso_current_op_3_26
?- lgt_run((current_op(P, T, '-'), P-T == 500-yfx)).
   true.

% iso_current_op_3_27
?- lgt_run((current_op(P, T, '/\\'), P-T == 500-yfx)).
   true.

% iso_current_op_3_28
?- lgt_run((current_op(P, T, '\\/'), P-T == 500-yfx)).
   true.

% iso_current_op_3_29
?- lgt_run((current_op(P, T, '*'), P-T == 400-yfx)).
   true.

% iso_current_op_3_30
?- lgt_run((current_op(P, T, '/'), P-T == 400-yfx)).
   true.

% iso_current_op_3_31
?- lgt_run((current_op(P, T, '//'), P-T == 400-yfx)).
   true.

% iso_current_op_3_32
?- lgt_run((current_op(P, T, 'rem'), P-T == 400-yfx)).
   true.

% iso_current_op_3_33
?- lgt_run((current_op(P, T, 'mod'), P-T == 400-yfx)).
   true.

% iso_current_op_3_34
?- lgt_run((current_op(P, T, '<<'), P-T == 400-yfx)).
   true.

% iso_current_op_3_35
?- lgt_run((current_op(P, T, '>>'), P-T == 400-yfx)).
   true.

% iso_current_op_3_36
?- lgt_run((current_op(P, T, '**'), P-T == 200-xfx)).
   true.

% iso_current_op_3_37
?- lgt_run((current_op(P, T, '^'), P-T == 200-xfy)).
   true.

% iso_current_op_3_38
?- lgt_run((current_op(P, T, '-'), P-T == 200-fy)).
   true.

% iso_current_op_3_39
?- lgt_run((current_op(P, T, '\\'), P-T == 200-fy)).
   true.

% iso_current_op_3_40
?- lgt_run((once((set_text_output(''), ((op(444, fy, baz), op(444, fy, quux), current_op(444, fy, Op), write(Op), op(0, fy, quux), fail) ; text_output_contents(Contents)))), (Contents == [b,a,z,q,u,u,x] ; Contents == [q,u,u,x,b,a,z]))).
   true.

% sics_current_op_3_41
?- lgt_run(current_op(1201, _, _)).
   error(domain_error(operator_priority,1201)).

% sics_current_op_3_42
?- lgt_run(current_op(_, yfy, _)).
   error(domain_error(operator_specifier,yfy)).

% sics_current_op_3_43
?- lgt_run(current_op(_, 0, _)).
   error(type_error(atom,0))
|  error(domain_error(operator_specifier,0)).

% sics_current_op_3_44
?- lgt_run(current_op(_, _, 5)).
   error(type_error(atom,5)).

% iso_current_op_3_45
?- lgt_run((current_op(P, T, '|') -> P >= 1001, infix(T) ; true)).
   true.

% iso_current_op_3_46
?- lgt_run((current_op(P, T, div), P-T == 400-yfx)).
   true.

% iso_current_op_3_47
?- lgt_run((current_op(P, T, '+'), P-T == 200-fy)).
   true.

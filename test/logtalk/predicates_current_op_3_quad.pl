% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

infix(yfx).
infix(xfx).
infix(xfy).

% iso_current_op_3_01
?- current_op(P, T, ':-'), P-T == 1200-xfx.
   true.

% iso_current_op_3_02
?- current_op(P, T, '-->'), P-T == 1200-xfx.
   true.

% iso_current_op_3_03
?- current_op(P, T, ':-'), P-T == 1200-fx.
   true.

% iso_current_op_3_04
?- current_op(P, T, '?-'), P-T == 1200-fx.
   true.

% iso_current_op_3_05
?- current_op(P, T, ';'), P-T == 1100-xfy.
   true.

% iso_current_op_3_06
?- current_op(P, T, '->'), P-T == 1050-xfy.
   true.

% iso_current_op_3_07
?- current_op(P, T, ','), P-T == 1000-xfy.
   true.

% iso_current_op_3_08
?- current_op(P, T, '\\+'), P-T == 900-fy.
   true.

% iso_current_op_3_09
?- current_op(P, T, '='), P-T == 700-xfx.
   true.

% iso_current_op_3_10
?- current_op(P, T, '\\='), P-T == 700-xfx.
   true.

% iso_current_op_3_11
?- current_op(P, T, '=='), P-T == 700-xfx.
   true.

% iso_current_op_3_12
?- current_op(P, T, '\\=='), P-T == 700-xfx.
   true.

% iso_current_op_3_13
?- current_op(P, T, '@<'), P-T == 700-xfx.
   true.

% iso_current_op_3_14
?- current_op(P, T, '@=<'), P-T == 700-xfx.
   true.

% iso_current_op_3_15
?- current_op(P, T, '@>'), P-T == 700-xfx.
   true.

% iso_current_op_3_16
?- current_op(P, T, '@>='), P-T == 700-xfx.
   true.

% iso_current_op_3_17
?- current_op(P, T, '=..'), P-T == 700-xfx.
   true.

% iso_current_op_3_18
?- current_op(P, T, 'is'), P-T == 700-xfx.
   true.

% iso_current_op_3_19
?- current_op(P, T, '=:='), P-T == 700-xfx.
   true.

% iso_current_op_3_20
?- current_op(P, T, '=\\='), P-T == 700-xfx.
   true.

% iso_current_op_3_21
?- current_op(P, T, '<'), P-T == 700-xfx.
   true.

% iso_current_op_3_22
?- current_op(P, T, '=<'), P-T == 700-xfx.
   true.

% iso_current_op_3_23
?- current_op(P, T, '>'), P-T == 700-xfx.
   true.

% iso_current_op_3_24
?- current_op(P, T, '>='), P-T == 700-xfx.
   true.

% iso_current_op_3_25
?- current_op(P, T, '+'), P-T == 500-yfx.
   true.

% iso_current_op_3_26
?- current_op(P, T, '-'), P-T == 500-yfx.
   true.

% iso_current_op_3_27
?- current_op(P, T, '/\\'), P-T == 500-yfx.
   true.

% iso_current_op_3_28
?- current_op(P, T, '\\/'), P-T == 500-yfx.
   true.

% iso_current_op_3_29
?- current_op(P, T, '*'), P-T == 400-yfx.
   true.

% iso_current_op_3_30
?- current_op(P, T, '/'), P-T == 400-yfx.
   true.

% iso_current_op_3_31
?- current_op(P, T, '//'), P-T == 400-yfx.
   true.

% iso_current_op_3_32
?- current_op(P, T, 'rem'), P-T == 400-yfx.
   true.

% iso_current_op_3_33
?- current_op(P, T, 'mod'), P-T == 400-yfx.
   true.

% iso_current_op_3_34
?- current_op(P, T, '<<'), P-T == 400-yfx.
   true.

% iso_current_op_3_35
?- current_op(P, T, '>>'), P-T == 400-yfx.
   true.

% iso_current_op_3_36
?- current_op(P, T, '**'), P-T == 200-xfx.
   true.

% iso_current_op_3_37
?- current_op(P, T, '^'), P-T == 200-xfy.
   true.

% iso_current_op_3_38
?- current_op(P, T, '-'), P-T == 200-fy.
   true.

% iso_current_op_3_39
?- current_op(P, T, '\\'), P-T == 200-fy.
   true.

% iso_current_op_3_40
?- once((set_text_output(''), ((op(444, fy, baz), op(444, fy, quux), current_op(444, fy, Op), write(Op), op(0, fy, quux), fail) ; text_output_contents(Contents)))), (Contents == [b,a,z,q,u,u,x] ; Contents == [q,u,u,x,b,a,z]).
   true.

% sics_current_op_3_41
?- current_op(1201, _, _).
   error(domain_error(operator_priority,1201)).

% sics_current_op_3_42
?- current_op(_, yfy, _).
   error(domain_error(operator_specifier,yfy)).

% sics_current_op_3_43
?- current_op(_, 0, _).
   error(type_error(atom,0))
|  error(domain_error(operator_specifier,0)).

% sics_current_op_3_44
?- current_op(_, _, 5).
   error(type_error(atom,5)).

% iso_current_op_3_45
?- current_op(P, T, '|') -> P >= 1001, infix(T) ; true.
   true.

% iso_current_op_3_46
?- current_op(P, T, div), P-T == 400-yfx.
   true.

% iso_current_op_3_47
?- current_op(P, T, '+'), P-T == 200-fy.
   true.

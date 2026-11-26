% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo42(foo42).

% iso_is_2_01
?- once(X is '+'(7, 35)), X == 42.
   true.

% iso_is_2_02
?- once(X is '+'(0, 3+11)), X == 14.
   true.

% iso_is_2_03
?- once(X is '+'(0, 3.2+11)), X == 14.2.
   true.

% iso_is_2_04
?- variable(N), _X is '+'(77, N).
   error(instantiation_error).

% iso_is_2_05
?- foo(0, Foo), _X is '+'(Foo, 77).
   error(type_error(evaluable,foo/0)).

% iso_is_2_06
?- once(X is '-'(7)), X == -7.
   true.

% iso_is_2_07
?- once(X is '-'(3-11)), X == 8.
   true.

% iso_is_2_08
?- once(X is '-'(3.2-11)), X == 7.8.
   true.

% iso_is_2_09
?- variable(N), _X is '-'(N).
   error(instantiation_error).

% iso_is_2_10
?- foo(0, Foo), _X is '-'(Foo).
   error(type_error(evaluable,foo/0)).

% iso_is_2_11
?- once(X is '-'(7, 35)), X == -28.
   true.

% iso_is_2_12
?- once(X is '-'(20, 3+11)), X == 6.
   true.

% iso_is_2_13
?- once(X is '-'(0, 3.2+11)), X == -14.2.
   true.

% iso_is_2_14
?- variable(N), _X is '-'(77, N).
   error(instantiation_error).

% iso_is_2_15
?- foo(0, Foo), _X is '-'(Foo, 77).
   error(type_error(evaluable,foo/0)).

% iso_is_2_16
?- once(X is '*'(7,35)), X == 245.
   true.

% iso_is_2_17
?- once(X is '*'(0, 3+11)), X == 0.
   true.

% iso_is_2_18
?- once(X is '*'(1.5, 3.2+11)), X =~= 21.3.
   true.

% iso_is_2_19
?- variable(N), _X is '*'(77, N).
   error(instantiation_error).

% iso_is_2_20
?- foo(0, Foo), _X is '*'(Foo, 77).
   error(type_error(evaluable,foo/0)).

% iso_is_2_21
?- once(X is '//'(7,35)), X == 0.
   true.

% iso_is_2_22
?- once(X is '/'(7.0,35)), X == 0.2.
   true.

% iso_is_2_23
?- once(X is '//'(140,3+11)), X == 10.
   true.

% iso_is_2_24
?- once(X is '/'(20.164, 3.2+11)), X =~= 1.42.
   true.

% iso_is_2_25
?- once(X is '//'(7, -3)), (X == -2 ; X == -3).
   true.

% iso_is_2_26
?- once(X is '//'(-7, 3)), (X == -2 ; X == -3).
   true.

% iso_is_2_27
?- variable(N), _X is '/'(77, N).
   error(instantiation_error).

% iso_is_2_28
?- foo(0, Foo), _X is '/'(Foo, 77).
   error(type_error(evaluable,foo/0)).

% iso_is_2_29
?- foo(1, Foo), _X is '/'(77, Foo).
   error(type_error(evaluable,foo/1)).

% iso_is_2_30
?- G = (_X is '/'(3, 0)), call(G).
   error(evaluation_error(zero_divisor)).

% iso_is_2_31
?- current_prolog_flag(max_integer, MI), _X is '+'(MI,1).
   error(evaluation_error(int_overflow)).

% iso_is_2_32
?- current_prolog_flag(max_integer, MI), _X is '-'('+'(MI,1),1).
   error(evaluation_error(int_overflow)).

% iso_is_2_33
?- current_prolog_flag(max_integer, MI), _X is '-'(-2,MI).
   error(evaluation_error(int_overflow)).

% iso_is_2_34
?- current_prolog_flag(max_integer, MI), _X is '*'(MI,2).
   error(evaluation_error(int_overflow)).

% iso_is_2_35
?- current_prolog_flag(max_integer, MI), R is float(MI)*2, _X is floor(R).
   error(evaluation_error(int_overflow)).

:- clean_text_input.

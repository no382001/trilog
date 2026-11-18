% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- op(100, fx, fx).
:- op(100, xf, xf).
:- op(100, xfx, xfx).
:- op(100, fy, fy).
:- op(100, yf, yf).
:- op(100, xfy, xfy).
:- op(100, yfx, yfx).

% iso_operators_01
?- set_text_input('fx fx 1. '), read(_).
   error(syntax_error(_)).

% iso_operators_02
?- set_text_input('fx (fx 1). '), read(_).
   true.

% iso_operators_03
?- set_text_input('1 xf xf. '), read(_).
   error(syntax_error(_)).

% iso_operators_04
?- set_text_input('(1 xf) xf. '), read(_).
   true.

% iso_operators_05
?- set_text_input('1 xfx 2 xfx 3. '), read(_).
   error(syntax_error(_)).

% iso_operators_06
?- set_text_input('(1 xfx 2) xfx 3. '), read(_).
   true.

% iso_operators_07
?- set_text_input('1 xfx (2 xfx 3). '), read(_).
   true.

% iso_operators_08
?- once((set_text_input('fy fy 1. fy (fy 1). '), (read(TU), read(TB)))), TU == TB.
   true.

% iso_operators_09
?- once((set_text_input(['1 xfy  2 xfy 3. ','1 xfy (2 xfy 3). ']), (read(TU), read(TB)))), TU == TB.
   true.

% iso_operators_10
?- once((set_text_input(['1 xfy  2 yfx 3. ','1 xfy (2 yfx 3). ']), (read(TU), read(TB)))), TU == TB.
   true.

% iso_operators_11
?- once((set_text_input('fy 2 yf. fy (2 yf). '), (read(TU), read(TB)))), TU == TB.
   true.

% iso_operators_12
?- once((set_text_input('1 yf yf. (1 yf) yf. '), (read(TU), read(TB)))), TU == TB.
   true.

% iso_operators_13
?- once((set_text_input([' 1 yfx 2  yfx 3. ','(1 yfx 2) yfx 3. ']), (read(TU), read(TB)))), TU == TB.
   true.

% iso_operators_14
?- once((set_text_input('-(1,2). '), read(T))), T == -(1,2).
   true.

% iso_operators_15
?- set_text_input('- (1,2). '), read(T), assertion(T == -((1,2))).
   true.

:- clean_text_input.

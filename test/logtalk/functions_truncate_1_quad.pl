% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).

% iso_truncate_1_01
?- once(X is truncate(-0.5)), X == 0.
   true.

% iso_truncate_1_02
?- foo(0, Foo), _X is truncate(Foo).
   error(type_error(evaluable,foo/0)).

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_copy_term_2_01
?- copy_term(_X, _Y).
   true.

% iso_copy_term_2_02
?- copy_term(_X, 3).
   true.

% iso_copy_term_2_03
?- copy_term(_, a).
   true.

% iso_copy_term_2_04
?- once(copy_term(a+X, X+b)), X == a.
   true.

% iso_copy_term_2_05
?- copy_term(_, _).
   true.

% iso_copy_term_2_06
?- once(copy_term(X+X+_Y, A+B+B)), A == B.
   true.

% iso_copy_term_2_07
?- copy_term(a, b).
   false.

% iso_copy_term_2_08
?- copy_term(a+X,X+b), copy_term(a+X,X+b).
   false.

% iso_copy_term_2_09
?- copy_term(demoen(X,X), demoen(Y,f(Y))).
   true.

% iso_copy_term_2_10
?- once((Term1 = a(X, Y), Term2 = a(_, _), copy_term(Term1, Term2), Term1 = a(A, B))), (X == A, Y == B).
   true.

% iso_copy_term_2_11
?- once((Term1 = a(X, Y), Term2 = a(Z, W), copy_term(Term1, Term2))), (X \== Z, X \== W, Y \== W, Y \== Z).
   true.

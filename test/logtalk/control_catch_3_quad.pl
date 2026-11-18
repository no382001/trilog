% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

foo(X) :- Y is X * 2, throw(test(Y)).
bar(X) :- X = Y, throw(Y).
coo(X) :- throw(X).
car(X) :- X = 1, throw(X).
g :- catch(p,_B,write(h2)), coo(c).
p.
p :- throw(b).
q :- catch((true ; throw(err)),E,write(E)), fail.
r(1).
one(1).

% iso_catch_3_01
?- lgt_run((once(catch(foo(5), test(Y), true)), Y == 10)).
   true.

% iso_catch_3_02
?- lgt_run((once(catch(bar(3), Z, true)), Z == 3)).
   true.

% iso_catch_3_03
?- lgt_run(catch(true, _, 3)).
   true.

% iso_catch_3_04
?- lgt_run((catch(((catch(true, _C, write(demoen)), throw(bla)), fail), LgtBall, true), subsumes_term(bla, LgtBall))).
   true.

% iso_catch_3_05
?- lgt_run((once(catch(car(_X), Y, true)), Y == 1)).
   true.

% iso_catch_3_06
?- lgt_run(catch(number_chars(_X,['1',a,'0']), error(syntax_error(_),_), fail)).
   false.

% iso_catch_3_07
?- lgt_run((once((suppress_text_output, (catch(g, C, write(h1)), nl))), C == c)).
   true.

% iso_catch_3_08
?- lgt_run((once(catch(coo(_X), Y, true)), subsumes_term(error(instantiation_error,_), Y))).
   true.

:- clean_text_output.

% module/2, use_module/1,2 and Module:Goal. Expected answers are Scryer Prolog's.
% test/quad/files/shapes.pl exports area/2, shape//1 and bump/0.

:- use_module('test/quad/files/shapes.pl').

sq(_, user_sq).
helper(user).

?- area(square(3), A).
   A = 9.

?- sq(3, X).
   X = user_sq.

?- shapes:sq(3, X).
   X = 9.

?- shapes:helper(X).
   X = private.

?- helper(X).
   X = user.

?- phrase(shape(S), "circle").
   S = circle.

?- phrase(word(W), "square").
   error(existence_error(procedure, word/3)).

?- shapes:checked(A).
   A = 4.

?- bump, shapes:counter(X).
   X = 1.

?- shapes:area(circle(1), A).
   A = 3.

?- user:helper(X).
   X = user.

?- nomodule:helper(X).
   error(existence_error(procedure, nomodule:helper/1)).

?- _:helper(X).
   error(instantiation_error).

?- 1:helper(X).
   error(type_error(atom, 1)).

?- use_module('test/quad/files/shapes.pl', [area/2, shape//1]).
   true.

?- use_module('test/quad/files/shapes.pl', [area]).
   error(syntax_error(invalid_module_declaration)).

?- use_module('test/quad/files/shapes.pl', foo).
   error(syntax_error(invalid_module_declaration)).

?- use_module('test/quad/files/shapes.pl', _).
   error(syntax_error(invalid_module_declaration)).

?- use_module('test/quad/files/shapes.pl', [nosuch/1]).
   true.

?- shapes:nosuch(X).
   error(existence_error(procedure, nosuch/1)).

?- use_module('test/quad/files/bad_module_name.pl').
   error(type_error(atom, 1)).

?- use_module('test/quad/files/bad_module_exports.pl').
   error(syntax_error(invalid_module_declaration)).

?- use_module('test/quad/files/bad_module_entry.pl').
   error(syntax_error(invalid_module_declaration)).

?- use_module(library(nosuchlib)).
   error(existence_error(source_sink, library(nosuchlib))).

?- use_module(_).
   error(instantiation_error).

?- module(m4, []).
   error(existence_error(procedure, module/2)).

% meta_predicate/1: a module's private closures keep their module.

?- squares([1, 2], Ys).
   Ys = [1,4].

?- total([1, 2, 3], T).
   T = 14.

?- sq_list(L).
   L = [1,4,9].

?- words(Ws).
   Ws = [square,circle].

?- smallest(S).
   S = 1-b.

?- dyn(Y).
   Y = 9.

?- call(shapes:sq, 4, X).
   X = 16.

?- maplist(shapes:sq, [2, 3], L).
   L = [4,9].

?- foldl(shapes:add_sq, [1, 2], 0, T).
   T = 5.

?- findall(X, shapes:sq(5, X), L).
   L = [25].

?- run(helper(X)).
   X = user.

?- run(help).
   error(existence_error(procedure, help/0)).

?- shapes:run(shapes:help).
   true.

?- meta_predicate(foo(0, ?)).
   error(existence_error(procedure, meta_predicate/1)).

?- consult('test/quad/files/bad_meta_spec.pl').
   error(syntax_error(invalid_meta_predicate_decl)).

?- consult('test/quad/files/bad_meta_var.pl').
   error(syntax_error(invalid_meta_predicate_decl)).

?- catch(consult('test/quad/files/bad_meta_spec.pl'), _, true), meta_rest.
   error(existence_error(procedure, meta_rest/0)).

% A file name without .pl is tried with .pl added, as in Scryer.

?- use_module('test/quad/files/shapes').
   true.

?- consult('test/quad/files/colors'), color(C).
   C = red
;  C = green.

% Module:Goal inside a module is settled when the module loads.

?- use_module('test/quad/files/callers').
   true.

?- c1(X).
   X = 9.

?- c2(A).
   A = 4.

?- c3(X).
   X = ok.

?- c4(W).
   W = circle.

?- later(X).
   error(existence_error(procedure, later/1)).

% A dynamic predicate declared in a module is private to it; assertz/1 and
% retract/1 in the module change that one.

?- use_module('test/quad/files/flags').
   true.

?- toggle(A), toggle(B), toggle(C).
   A = on, B = off, C = on.

?- flag.
   error(existence_error(procedure, flag/0)).

?- flags:flag.
   true.

% A clause built at run time goes to the module's own predicate too.

?- save(1), save(2), saved(Xs).
   Xs = [1,2].

?- fact(_).
   error(existence_error(procedure, fact/1)).

?- assertz(flags:fact(3)), saved(Xs).
   Xs = [1,2,3].

?- retract(flags:fact(1)), saved(Xs).
   Xs = [2,3].

?- retractall(flags:fact(_)), saved(Xs).
   Xs = [].

?- save_rule(1), ruled(X).
   X = 1.

?- positive(1).
   error(existence_error(procedure, positive/1)).

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

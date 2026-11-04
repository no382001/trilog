% --- literals ---

?- X = 3.3.
   X = 3.3.

?- X = -3.3.
   X = -3.3.

?- X = 0.5, Y = 1, Z is X + Y.
   X = 0.5, Y = 1, Z = 1.5.

% --- printing ---

?- X is float(7), Y = X.
   X = 7.0, Y = 7.0.

?- X is float(7.3).
   X = 7.3.

% --- type-checking predicates ---

?- atom(3.3).
   false.

?- integer(3.3).
   false.

?- float(3.3).
   true.

?- float(-3.3).
   true.

?- float(3).
   false.

?- float(atom).
   false.

?- float(_X).
   false.

?- number(3.3).
   true.

?- atomic(3.3).
   true.

?- compound(33.3).
   false.

?- nonvar(33.3).
   true.

% --- unification ---

?- '='(1, 1.0).
   false.

?- \=(1, 1.0).
   true.

?- '='(1.0, 1.0).
   true.

% --- standard order of terms ---
% ISO: Number sorts between Var and Atom; equal-valued Float sorts before Int.

?- '@=<'(1.0, 1).
   true.

?- '@<'(1.0, 1).
   true.

?- '@=<'(aardvark, zebra).
   true.

% --- functor/3, univ (=..) ---

?- functor(X, 1.1, 0).
   X = 1.1.

?- functor(_F, 1.5, 1).
   error(type_error(atom, 1.5)).

?- '=..'(_X, [1.1, foo]).
   error(type_error(atom, 1.1)).

?- '=..'(1, [1]).
   true.

% --- atom_number/2, number_codes/2, number_chars/2 ---

?- atom_number('3.5', X).
   X = 3.5.

?- atom_number(X, 3.5).
   X = 3.5.

?- number_codes(33.0, [0'3|_L]).
   true.

?- number_chars(X, ['3', '.', '3']).
   X = 3.3.

?- number_chars(X, ['3', '.', '3', 'E', '+', '0']).
   X = 3.3.

% --- arithmetic: +, -, *, / with int/float promotion ---

?- X is '+'(0, 3.2+11).
   X = 14.2.

?- X is '-'(3.2-11).
   X = 7.8.

?- X is '-'(0, 3.2+11).
   X = -14.2.

?- X is '/'(7.0, 35).
   X = 0.2.

?- _X is '/'(3, 0).
   error(evaluation_error(zero_divisor)).

?- X is '//'(7, 35).
   X = 0.

% --- floor, ceiling, round, truncate, float, abs ---

?- X is floor(7.4).
   X = 7.

?- X is floor(-0.4).
   X = -1.

?- X is round(7.5).
   X = 8.

?- X is round(7.6).
   X = 8.

?- X is round(-0.6).
   X = -1.

?- _X is round(_N).
   error(instantiation_error).

?- X is ceiling(-0.5).
   X = 0.

?- X is truncate(-0.5).
   X = 0.

?- _X is truncate(foo).
   error(type_error(evaluable, foo/0)).

?- X is float(5//3).
   X = 1.0.

?- _X is float(_N).
   error(instantiation_error).

?- _X is float(foo).
   error(type_error(evaluable, foo/0)).

?- X is abs(3.2-11.0).
   X = 7.8.

% --- int-only ops reject float operands ---

?- _X is mod(7.5, 2).
   error(type_error(integer, 7.5)).

?- _X is '\\'(7.5).
   error(type_error(integer, 7.5)).

% --- comparisons ---

?- '=:='(1.0, 1).
   true.

?- =\=(1.0, 1).
   false.

?- '<'(1.0, 1).
   false.

?- '>'(1.0, 1).
   false.

?- '>='(1.0, 1).
   true.

?- '=<'(1.0, 1).
   true.

% --- overflow: floor/ceiling/round/truncate range-check against 32-bit int ---

?- (current_prolog_flag(max_integer, MI), R is float(MI)*2, _X is floor(R)).
   error(evaluation_error(int_overflow)).

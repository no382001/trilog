% error tests

% --- is/2 instantiation errors ---

?- X is Y.
   error(instantiation_error).

?- X is Y + 1.
   error(instantiation_error).

?- X is 2 * (Y + 3).
   error(instantiation_error).

% --- arithmetic comparison instantiation errors ---

?- X < 3.
   error(instantiation_error).

?- 3 < X.
   error(instantiation_error).

?- X > 3.
   error(instantiation_error).

?- X =< 3.
   error(instantiation_error).

?- X >= 3.
   error(instantiation_error).

?- X =:= 3.
   error(instantiation_error).

?- X =\= 3.
   error(instantiation_error).

% --- functor/3 instantiation errors ---

?- functor(X, Y, Z).
   error(instantiation_error).

?- functor(X, Y, 2).
   error(instantiation_error).

?- functor(X, foo, Z).
   error(instantiation_error).

% --- functor/3 still works when properly called ---

?- functor(foo(a, b), N, A).
   N = foo, A = 2.

?- functor(T, foo, 2), T = foo(a, b).
   T = foo(a, b).

% --- error propagation ---

?- once(X is Y).
   error(instantiation_error).

?- \+ (X is Y).
   error(instantiation_error).

% --- error does not bleed into next query ---

?- X is Y.
   error(instantiation_error).

?- 1 < 2.
   true.

% --- bound variable does not error ---

?- Y = 5, X is Y + 1.
   Y = 5, X = 6.

?- Y = 3, Y < 5.
   Y = 3.

% --- division by zero ---

?- X is 5 / 0.
   error(evaluation_error).

?- X is 10 mod 0.
   error(evaluation_error).

?- X is 10 // 0.
   error(evaluation_error).

% --- ISO error terms are catchable ---

catch_inst(C) :- catch(X is Y, error(instantiation_error, C), true), X = 0, Y = 0.

?- catch_inst(C).
   C = is/2.

catch_div(C) :- catch(X is 5 / 0, error(evaluation_error(zero_divisor), C), true), X = 0.

?- catch_div(C).
   C = is/2.

catch_functor(C) :- catch(functor(X, Y, Z), error(instantiation_error, C), true), X = 0, Y = 0, Z = 0.

?- catch_functor(C).
   C = functor/3.

% --- catching generic error(_,_) ---

catch_any_inst(E) :- catch(X is Y, error(E, _), true), X = 0, Y = 0.

?- catch_any_inst(E).
   E = instantiation_error.

% --- uncaught ISO error still reports ---

?- X is Y.
   error(instantiation_error).

% --- call/1 type_error for integer ---

?- catch(call(42), error(type_error(callable, 42), _), true).
   true.

% --- trailing input parse error ---

?- catch(true, _, false).
   true.

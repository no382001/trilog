% op/3 and current_op/3 tests

% --- current_op/3 (querying built-in ops) ---

?- current_op(700, xfx, =).
   true.

?- current_op(700, xfx, is).
   true.

?- current_op(1100, xfy, ;).
   true.

?- current_op(1050, xfy, ->).
   true.

?- current_op(1000, xfy, ',').
   true.

?- current_op(900, fy, \+).
   true.

?- current_op(500, yfx, +).
   true.

?- current_op(400, yfx, *).
   true.

?- current_op(200, fy, -).
   true.

?- current_op(P, xfx, =).
   P = 700.

?- current_op(700, T, =).
   T = xfx.

?- current_op(_, _, no_such_op_xyz).
   false.

% --- op/3 (defining new operators) ---

:- op(700, xfx, ===).

?- current_op(700, xfx, ===).
   true.

:- op(600, xfy, ##).

?- current_op(600, xfy, ##).
   true.

% use newly defined operator
myeq(X, X).

?- myeq(a, a).
   true.

?- myeq(a, b).
   false.

% --- op/3 prefix ---

:- op(900, fy, not2).

?- current_op(900, fy, not2).
   true.

% --- op/3 remove operator (priority 0) ---

:- op(0, xfx, ===).

?- current_op(_, _, ===).
   false.

% --- op/3 list of names ---

:- op(500, yfx, [op1, op2]).

?- current_op(500, yfx, op1).
   true.

?- current_op(500, yfx, op2).
   true.

% --- op/3 errors ---

?- op(700, bad_type, foo).
   error(domain_error(operator_specifier, bad_type)).

?- op(foo, xfx, bar).
   error(type_error(integer, foo)).

?- op(700, xfx, []).
   error(permission_error(create, operator, [])).

?- op(700, xfx, {}).
   error(permission_error(create, operator, {})).

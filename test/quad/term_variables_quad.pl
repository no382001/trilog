
?- term_variables(t, Vars).
   Vars = [].

?- term_variables(A+B*C/B-D, Vars).
   Vars = [A,B,C,D].

?- term_variables(t, [_, _|a]).
   error(type_error(list, [_,_|a])).

?- term_variables(f(X, Y, X, g(Z)), Vars).
   Vars = [X,Y,Z].

?- S = s(A,B), term_variables(f(S,S,S), Vars).
   S = s(A,B), Vars = [A,B].

?- term_variables(t, foo).
   error(type_error(list, foo)).

?- L = [a|L], term_variables(t, L).
   error(type_error(list, [a|...])).

% Rational trees end: each structure is walked once.

?- X = f(X, Y), term_variables(X, Vars).
   sto, X = f(X,Y), Vars = [Y].

?- L = [A,B|L], term_variables(L, Vars).
   sto, L = [A,B|L], Vars = [A,B].

?- X = f(X), ground(X).
   sto, X = f(X).

?- X = f(X, _), ground(X).
   sto, false.

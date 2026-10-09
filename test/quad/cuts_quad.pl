% cut tests

% --- cut prevents backtracking ---

ca(1).
ca(2).
ca(3).
cfirst(X) :- ca(X), !.

?- once(cfirst(X)).
   X = 1.

% --- cut in middle of clause ---

cb(1).
cb(2).
ctest(X, Y) :- ca(X), !, cb(Y).

?- ctest(1, Y).
   Y = 1
;  Y = 2.

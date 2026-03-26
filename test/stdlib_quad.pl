% stdlib tests

% --- between/3 ---

?- findall(X, between(1, 5, X), L).
   L = [1, 2, 3, 4, 5].

?- findall(X, between(3, 3, X), L).
   L = [3].

?- between(5, 3, _).
   false.

?- between(1, 10, 5).
   true.

?- between(1, 10, 11).
   false.

?- findall(X, between(-2, 2, X), L).
   L = [-2, -1, 0, 1, 2].

% --- once/1 ---

?- once(member(X, [a, b, c])).
   X = a.

?- once(true).
   true.

?- once(fail).
   false.

?- findall(X, once(member(X, [1, 2, 3])), L).
   L = [1].

% --- forall/2 ---

?- forall(member(X, [2, 4, 6]), 0 =:= X mod 2).
   true.

?- forall(member(X, [2, 3, 6]), 0 =:= X mod 2).
   false.

?- forall(member(_, []), fail).
   true.

?- forall(between(1, 5, X), X > 0).
   true.

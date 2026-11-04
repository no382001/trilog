% bagof/3 and setof/3 group by the free variables. Expected answers are
% Scryer Prolog's.

?- bagof(X, member(X-Y, [1-b,2-a,3-b]), L).
   Y = a, L = [2]
;  Y = b, L = [1,3].

?- setof(X, member(X-Y, [3-b,2-a,1-b,1-b]), L).
   Y = a, L = [2]
;  Y = b, L = [1,3].

?- bagof(X, Y^member(X-Y, [1-b,2-a,3-b]), L).
   L = [1,2,3].

?- bagof(X, member(X, []), L).
   false.

?- bagof(X-Z, member(X-Y-Z, [1-a-p,2-b-q,3-a-r]), L).
   Y = a, L = [1-p,3-r]
;  Y = b, L = [2-q].

?- setof(K-V, member(K-V, [b-1,a-2,a-1]), L).
   L = [a-1,a-2,b-1].

?- bagof(X, (member(X, [1,2]) ; member(X, [3])), L).
   L = [1,2,3].

?- bagof(X, Z^Y^member(X-Y-Z, [1-a-p,2-b-q]), L).
   L = [1,2].

?- bagof(X, G, L).
   error(instantiation_error).

?- bagof(X, 1, L).
   error(type_error(callable, 1)).

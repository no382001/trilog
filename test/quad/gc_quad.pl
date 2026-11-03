% Garbage collection keeps data alive across collections.

gc_mk(0, []) :- !.
gc_mk(N, [N|T]) :- N1 is N-1, gc_mk(N1, T).

gc_churn(0) :- !.
gc_churn(K) :- gc_mk(200, _), K1 is K-1, gc_churn(K1).

gc_bind_all([], _).
gc_bind_all([V|Vs], N) :- gc_churn(1), V = f(N), N1 is N+1, gc_bind_all(Vs, N1).

gc_sum([], S, S).
gc_sum([f(X)|Xs], S0, S) :- S1 is S0+X, gc_sum(Xs, S1, S).

gc_len([], N, N).
gc_len([_|T], N0, N) :- N1 is N0+1, gc_len(T, N1, N).

% Variables made before a collection, bound to terms made after it.
?- length(_L, 2000), gc_mk(2000, _Keep), gc_bind_all(_L, 1), gc_sum(_L, 0, S), gc_len(_Keep, 0, K).
   S = 2001000, K = 2000.

% Backtracking past data that survived a collection.
?- ( gc_mk(30000, _L), gc_churn(100), fail ; gc_mk(10, _L) ), gc_len(_L, 0, N).
   N = 10.

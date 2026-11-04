app([], L, L).
app([H|T], L, [H|R]) :- app(T, L, R).

nrev([], []).
nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R).

range(N, N, [N]) :- !.
range(I, N, [I|T]) :- I < N, I1 is I + 1, range(I1, N, T).

main :- range(1, 300, L), nrev(L, _).

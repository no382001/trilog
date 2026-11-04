sel(X, [X|T], T).
sel(X, [H|T], [H|R]) :- sel(X, T, R).

perm([], []).
perm(L, [H|T]) :- sel(H, L, R), perm(R, T).

safe([]).
safe([Q|Qs]) :- noatk(Q, Qs, 1), safe(Qs).

noatk(_, [], _).
noatk(Q, [Q1|Qs], D) :- Q =\= Q1 + D, Q =\= Q1 - D, D1 is D + 1, noatk(Q, Qs, D1).

queens(Qs) :- perm([1,2,3,4,5,6,7,8], Qs), safe(Qs).

main :- queens(_), fail.
main.

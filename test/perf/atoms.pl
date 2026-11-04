mk(N, N) :- !.
mk(I, N) :- number_codes(I, Cs), atom_codes(_, [0'a|Cs]), I1 is I + 1, mk(I1, N).

main :- mk(0, 20000).

loop(0) :- !.
loop(N) :- number_chars(_, ['1','2']), N1 is N - 1, loop(N1).

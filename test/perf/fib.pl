fib(N, N) :- N < 2, !.
fib(N, F) :- A is N - 1, B is N - 2, fib(A, FA), fib(B, FB), F is FA + FB.

main :- fib(21, _).

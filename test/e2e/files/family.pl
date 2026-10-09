parent(tom,bob).
parent(bob,ann).
parent(tom,liz).

grandparent(X,Z) :- parent(X,Y), parent(Y,Z).

double(X,Y) :- Y is X*2.

choice(a).
choice(b).
choice(c).
first_choice(X) :- choice(X), !.

% regression: cut must prune THIS call's choice point, not get clobbered
% by the nested call to q in between the call and the '!'.
q.
p(1) :- q, !.
p(2).

first_gt3([X|_], X) :- X > 3, !.
first_gt3([_|T], X) :- first_gt3(T, X).

% GC stress fixture: loop/1 leaves no choice points, so its garbage is
% only ever reclaimed by real GC, never by backtracking.
loop(0) :- !.
loop(N) :- N > 0, !, N1 is N - 1, loop(N1).

count_list(0, []) :- !.
count_list(N, [N|T]) :- N > 0, !, N1 is N - 1, count_list(N1, T).

list_len([], 0) :- !.
list_len([_|T], N) :- list_len(T, N1), N is N1 + 1.

% first-argument indexing fixtures: constants that let a bound call skip
% non-matching clauses without rendering or unifying them.
item(one, 1).
item(two, 2).
item(three, 3).

% No cut: indexing alone must prove this deterministic via disjoint
% first-argument keys, or it blows up in time/space at any real N.
count(0).
count(N) :- N > 0, N1 is N - 1, count(N1).

% catch/3 fixture: opt/1's 2nd clause throws only on backtrack into it,
% after opt(a) already succeeded once.
opt(a).
opt(b) :- throw(bad_b).
opt(c).

% findall/3 nesting fixture: inner_choice must yield [a,b,c] each time,
% independent of the outer binding.
inner_choice(a).
inner_choice(b).
inner_choice(c).

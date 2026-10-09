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

% --- length/2 (generative modes and errors) ---

?- length([_,_,_], N).
   N = 3.

?- length(L, 0).
   L = [].

?- length(L, 3), L = [1,2,3].
   L = [1, 2, 3].

?- length([], -1).
   error(domain_error(not_less_than_zero, -1)).

?- length([], foo).
   error(type_error(integer, foo)).

% --- select/3 ---

?- select(X, [1,2,3], Rest).
   X = 1, Rest = [2, 3]
;  X = 2, Rest = [1, 3]
;  X = 3, Rest = [1, 2].

?- select(2, [1,2,3], Rest).
   Rest = [1, 3].

?- select(4, [1,2,3], _).
   false.

?- select(1, Xs, [2,3]).
   Xs = [1, 2, 3]
;  Xs = [2, 1, 3]
;  Xs = [2, 3, 1].

% --- nth0/3 ---

?- nth0(0, [a,b,c], E).
   E = a.

?- nth0(1, [a,b,c], E).
   E = b.

?- nth0(2, [a,b,c], E).
   E = c.

?- nth0(3, [a,b,c], _).
   false.

?- nth0(N, [a,b,c], b).
   N = 1.

% --- nth0/4 ---

?- nth0(1, [1,2,3], E, Rest).
   E = 2, Rest = [1, 3].

?- nth0(0, [1,2,3], E, Rest).
   E = 1, Rest = [2, 3].

% --- nth1/3 ---

?- nth1(1, [a,b,c], E).
   E = a.

?- nth1(2, [a,b,c], E).
   E = b.

?- nth1(3, [a,b,c], E).
   E = c.

?- nth1(0, [a,b,c], _).
   false.

?- nth1(N, [a,b,c], b).
   N = 2.

% --- nth1/4 ---

?- nth1(2, [1,2,3], E, Rest).
   E = 2, Rest = [1, 3].

% --- maplist/2 ---

?- maplist(>(3), [1,2]).
   true.

?- maplist(>(3), [1,2,3]).
   false.

?- maplist(atom, [a,b,c]).
   true.

?- maplist(atom, [a,1,c]).
   false.

?- maplist(atom, []).
   true.

% --- maplist/3 ---

?- maplist(succ, [1,2,3], Ys).
   Ys = [2, 3, 4].

?- maplist(succ, [10,20,30], Ys).
   Ys = [11, 21, 31].

?- maplist(atom_length, [a,bb,ccc], Ls).
   Ls = [1, 2, 3].

?- maplist(succ, [], Ys).
   Ys = [].

% --- maplist/4 ---

maplist4_add(X, Y, Z) :- Z is X + Y.

?- maplist(maplist4_add, [1,2,3], [10,20,30], Sums).
   Sums = [11, 22, 33].

% --- foldl/4 ---

foldl_add(X, A, B) :- B is A + X.

?- foldl(foldl_add, [1,2,3], 0, S).
   S = 6.

?- foldl(append, [[1,2],[3],[4,5]], [], Xs).
   Xs = [4, 5, 3, 1, 2].

?- foldl(_, [], acc, S).
   S = acc.

% --- foldl/5 ---

foldl5_add(X, Y, A, B) :- B is A + X + Y.

?- foldl(foldl5_add, [1,2,3], [10,20,30], 0, S).
   S = 66.

% --- foldl/6 ---

foldl6_add(X, Y, Z, A, B) :- B is A + X + Y + Z.

?- foldl(foldl6_add, [1,2], [10,20], [100,200], 0, S).
   S = 333.

% --- countall/2 ---

?- countall(member(_, [a,b,c]), N).
   N = 3.

?- countall(member(_, []), N).
   N = 0.

?- countall(between(1,10,_), N).
   N = 10.

?- countall(fail, N).
   N = 0.

% --- compare/3 ---

?- compare(Order, a, b).
   Order = <.

?- compare(Order, b, a).
   Order = >.

?- compare(Order, a, a).
   Order = =.

% --- memberchk/2 ---

?- memberchk(b, [a,b,c]).
   true.

?- memberchk(z, [a,b,c]).
   false.

% --- delete/3 ---

?- delete([1,2,1,3,1], 1, L).
   L = [2, 3].

?- delete([aa,bb,cc], z, L).
   L = [aa, bb, cc].

% --- include/3, exclude/3, partition/4 ---

gt2(X) :- X > 2.

?- include(gt2, [1,2,3,4], L).
   L = [3, 4].

?- exclude(gt2, [1,2,3,4], L).
   L = [1, 2].

?- partition(gt2, [1,2,3,4], In, Out).
   In = [3, 4], Out = [1, 2].

% --- subtract/3, intersection/3, union/3 ---

?- subtract([1,2,3], [2], L).
   L = [1, 3].

?- intersection([1,2,3], [2,3,4], L).
   L = [2, 3].

?- union([1,2], [2,3], L).
   L = [1, 2, 3].

% --- sum_list/2, max_list/2, min_list/2, max_member/2, min_member/2 ---

?- sum_list([1,2,3], S).
   S = 6.

?- max_list([3,1,4,1,5], M).
   M = 5.

?- min_list([3,1,4,1,5], M).
   M = 1.

?- max_member(M, [3,1,4,1,5]).
   M = 5.

?- min_member(M, [3,1,4,1,5]).
   M = 1.

% --- numlist/3 ---

?- numlist(1, 5, L).
   L = [1, 2, 3, 4, 5].

?- numlist(3, 1, L).
   L = [].

% --- flatten/2 ---

?- flatten([1,[2,[3,4],5],6], L).
   L = [1, 2, 3, 4, 5, 6].

?- flatten([], L).
   L = [].

% --- list_to_set/2 ---

?- list_to_set([1,2,1,3,2], L).
   L = [1, 2, 3].

% --- permutation/2 ---

?- findall(P, permutation([1,2,3], P), L), length(L, N).
   L = [[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]], N = 6.

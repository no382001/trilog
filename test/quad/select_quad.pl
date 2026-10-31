% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/select_quad.pl

% ISO Prolog Prologue select/3 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue
%
% p.p.5 select/3
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% select(X, Xs, Ys) is true if X is an element of the list Xs and Ys is the list Xs with one occurrence of X removed.
% 
% More precisely, select(X, Xs, Ys) is true iff X is an element of a list prefix of Xs and Ys is Xs with one occurrence of X removed.
% 
% Procedurally, select/3 is defined with the following clauses. 

select(E, [E|Xs], Xs).
select(E, [X|Xs], [X|Ys]) :-
   select(E, Xs, Ys).

% Template and modes:  select(?term, ?term, ?term) 

?- select(X, [1,2], Xs).
   X = 1, Xs = [2]
;  X = 2, Xs = [1].

?- select(X, [Y|nonlist], Xs).
   X = Y, Xs = nonlist.

?- select(E, Xs, Xs).
   sto, % occurs-check
   loops
|  sto, % rational trees
   Xs = [E|Xs]
;  Xs = [_A|_B], _B = [E|_B]
;  ..., ad_infinitum
|  sto, % literal substitutions
   Xs = [E,E|_A]
;  Xs = [_A,E,E|_B]
;  ..., ad_infinitum.

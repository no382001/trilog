% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/foldl_quad.pl

% ISO Prolog Prologue foldl/4..6 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue#foldl
%
% p.p.10 foldl/4..6
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% foldl(R_3, Xs, S0,S) is true iff Xs is a list and for all elements X1..Xn of Xs the following is true.
% 
% call(R_3, X1, S0,S1),
% call(R_3, X2, S1,S2),
% ...,
% call(R_3, Xn, Spn,S).
% 
% foldl(R_4, Xs, Ys, S0,S) is true iff Xs and Ys are lists of same length and for all elements X1..Xn of Xs and Y1..Yn of Ys the following is true.
% 
% call(R_4, X1, Y1, S0,S1),
% call(R_4, X2, Y2, S1,S2),
% ...,
% call(R_4, Xn, Yn, Spn,S).
% 
% foldl(R_5, Xs, Ys, Zs, S0,S) is true iff Xs, Ys, and Zs are lists of same length and for all elements X1..Xn of Xs, Y1..Yn of Ys, and Z1..Zn of Zs the following is true.
% 
% call(R_5, X1, Y1, Z1, S0,S1),
% call(R_5, X2, Y2, Z2, S1,S2),
% ...,
% call(R_5, Xn, Yn, Zn, Spn,S).
% 
% Procedurally, foldl/4..6 is defined with the following clauses. 

foldl(_, [], S,S).
foldl(R_3, [X|Xs], S0,S) :-
   call(R_3, X, S0,S1),
   foldl(R_3, Xs, S1,S).

foldl(_, [], [], S,S).
foldl(R_4, [X|Xs], [Y|Ys], S0,S) :-
   call(R_4, X, Y, S0,S1),
   foldl(R_4, Xs, Ys, S1,S).

foldl(_, [], [], [], S,S).
foldl(R_5, [X|Xs], [Y|Ys], [Z|Zs], S0,S) :-
   call(R_5, X, Y, Z, S0,S1),
   foldl(R_5, Xs, Ys, Zs, S1,S).

% Template and modes:
% foldl(?term, ?term, ?term,?term)
% foldl(?term, ?term, ?term, ?term,?term)
% foldl(?term, ?term, ?term, ?term, ?term,?term)

?- foldl(append, [[1,2],[3],[4,5]], [],Xs).
   Xs = [4,5,3,1,2].


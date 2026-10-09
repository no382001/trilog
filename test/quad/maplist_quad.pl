% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/maplist_quad.pl

% ISO Prolog Prologue maplist/2..8 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue#maplist
%
% p.p.7 maplist/2..8
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% maplist(R_1, E1s) is true iff E1s is a list and for each element E1 of E1s, call(R_1, E1) is true.
% 
% maplist(R_2, E1s, E2s) is true iff E1s and E2s are lists of same length and for each element E1 of E1s and each corresponding element of E2, call(R_2, E1, E2) is true.
% 
% maplist(R_n, E1s, E2s, ... Ens) is true iff E1s, E2s up to Ens are lists of same length and call(R_n, E1_i, E2_i, ... En_i) is true for each i where Ek_i is the i-th element of Listk.
% 
% Procedurally, maplist/2..8 is defined with the following clauses. 

maplist(_R_1, []).
maplist(R_1, [E1|E1s]) :-
   call(R_1, E1),
   maplist(R_1, E1s).

maplist(_R_2, [], []).
maplist(R_2, [E1|E1s], [E2|E2s]) :-
   call(R_2, E1, E2),
   maplist(R_2, E1s, E2s).

maplist(_R_3, [], [], []).
maplist(R_3, [E1|E1s], [E2|E2s], [E3|E3s]) :-
   call(R_3, E1, E2, E3),
   maplist(R_3, E1s, E2s, E3s).
    
% ...
% 
% maplist(_R_n, [], [], ... []).
% maplist(R_n, [E1|E1s], [E2|E2s], ... [En|Ens]) :-
%    call(R_n, E1, E2, ... En),
%    maplist(R_n, E1s, E2s, ... Ens).

% Template and modes:
% maplist(?term, ?term)
% maplist(?term, ?term, ?term)
% maplist(?term, ?term, ?term, ?term)
% ...
% maplist(?term, ?term, ?term, ... ?term)

?- maplist(>(3), [1, 2]).
   true.

?- maplist(>(3), [1, 2, 3]).
   false.

?- maplist(=(X), Xs).
   Xs = []
;  Xs = [X]
;  Xs = [X, X]
;  Xs = [X, X, X]
;  ..., ad_infinitum.

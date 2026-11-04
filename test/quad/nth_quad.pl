% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/nth_quad.pl

% ISO Prolog Prologue nth0/3, nth1/3, nth0/4, nth1/4 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue
%
% p.p.8 nth0/4, nth0/3, nth1/4, nth1/3
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% nth0(N, Es0, E, Es) is true if E is an element of the list Es0 and there are N elements before E. Es is the list without this occurence of E.
%
% More precisely, nth0(N, Es0, E, Es) is true iff there is a list prefix Prefix of Es0 and length(Prefix,N), append(Prefix,[E|Postfix], Es0), append(Prefix, Postfix, Es) is true. 
%
% Template and modes:
% nth0(?integer, ?term, ?term, ?term)
% nth0(?integer, ?term, ?term)
% nth1(?integer, ?term, ?term, ?term)
% nth1(?integer, ?term, ?term)
%
% Errors:
% a) N is neither a variable nor an integer
% — type_error(integer, N).
% b) N is an integer that is less than zero
% — domain_error(not_less_than_zero, N). 

?- nth0(1, [a,b,c], E).
   E = b.

?- nth0(N, [a,b,c], E).
   N = 0, E = a
;  N = 1, E = b
;  N = 2, E = c.

?- nth0(0, [A,B|non_list], E).
   A = E.

?- nth0(2, Es, E).
   Es = [_A,_B,E|_C].

?- nth0(N, Es, E).
   N = 0, Es = [E|_A]
;  N = 1, Es = [_A,E|_B]
;  N = 2, Es = [_A,_B,E|_C]
;  N = 3, Es = [_A,_B,_C,E|_D]
;  ..., ad_infinitum.

?- nth0(non_integer, Es, E).
   type_error(integer, non_integer).

?- nth0(-1, Es, E).
   domain_error(not_less_than_zero, -1).

?- nth0(N, [[]|Es], Es).
   N = 0, Es = []
;  sto, % occurs-check
   loops
|  N = 0, Es = []
;  sto, % rational trees
   N = 1, Es = [Es|_A]
;  N = 2, Es = [_A,Es|_B]
;  ..., ad_infinitum.

?- nth1(0, Es, E).
   false.

% The built-in predicates nth0/3, nth1/4, and nth1/3 all provide similar functionality to nth0/4.

nth0(N, Es0, E) :-
   nth0(N, Es0, E, _).

nth1(N, Es0, E, Es) :-
   N \== 0,
   nth0(N, [_|Es0], E, [_|Es]),
   N \== 0.

nth1(N, Es0, E) :-
   nth1(N, Es0, E, _).

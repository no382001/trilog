% ISO Prolog Prologue member/2 Tests
% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/member_quad.pl, itself based on
% https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue#member

?- member(X, [1, 2]).
   X = 1
;  X = 2.

?- member(1, L).
   L = [1|_A]
;  L = [_A, 1|_B]
;  L = [_A, _B, 1|_C]
;  ..., ad_infinitum.

?- member(X, [_Y, _Z|nonlist]).
   X = _A
;  X = _A.

?- member(X, nonlist).
   false.

?- member(X, X).
   sto, % occurs-check
   loops
|  sto, % rational trees
   X = [X|_A]
;  X = [_A,X|_B]
;  X = [_A,_B,X|_C]
;  ..., ad_infinitum
|  sto, % literal substitutions
   X = [_A|_B]
;  X = [_A,[_A,[_A|_B]|_C]|_C]
;  X = [_A,_B,[_A,_B,[_A,_B|_C]|_D]|_D]
;  ..., ad_infinitum.

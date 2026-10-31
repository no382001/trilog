% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/between_quad.pl

% ISO Prolog Prologue between/3 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue#between
%
% p.p.4 between/3
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
%  between(Lower, Upper, X) is true iff X is greater than or equal to Lower, and less than or equal to Upper. 
%
% Template and modes: between(+integer, +integer, ?integer)

between(Lower, Upper, Lower) :-
   Lower =< Upper.
between(Lower1, Upper, X) :-
   Lower1 < Upper,
   Lower2 is Lower1 + 1,
   between(Lower2, Upper, X).

?- between(1, 2, 0).
   false.

?- between(1, 2, I).
   I = 1
;  I = 2.

?- between(2, 1, I).
   false.

?- between(I, I, 0).
   instantiation_error.

?- between(1, I, 0).
   instantiation_error.

?- between(I, -1, 0).
   instantiation_error.

?- between(1, c, 0).
   type_error(integer, c).

?- between(1+1,2,I).
   type_error(integer, 1+1).

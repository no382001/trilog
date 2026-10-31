% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/length_quad.pl

% ISO Prolog Prologue length/2 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue#length
%
% p.p.3 length/2
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% length(List, Length) is true iff List is a list of length Length.
% 
% Procedurally, length(List, Length) is executed as follows:
% 
% a) If List is neither a partial list nor a list, then the goal fails.
% b) If List is a list, then unifies Length with the length of List.
% c) Else the goal fails.
% d) If Length is an integer, then unifies List with a list of length Length with Length distinct fresh variables as elements.
% e) Else the goal fails.
% f) Chooses the first element Len of N0 being the integer 0.
% g) The goal succeeds, unifying Length with Len and List with a list of length Len with Len distinct fresh variables as elements.
% h) If List is a partial list and Length is a variable, chooses the next element Len of N0 and proceeds to step p.p.3.1 g.
% i) Else the goal fails.
% 
% length(List, Length) is re-executable. On backtracking, continue at p.p.3.1 h above. 
%
% Template and modes: length(?term, ?integer)
%
% Errors:
% a) Length is neither a variable nor an integer
% — type_error(integer, Length).
% b) Length is an integer that is less than zero
% — domain_error(not_less_than_zero, Length). 

?- length([a,b,c], Length).
   Length = 3.

?- length(List, 5).
   List = [_A,_B,_C,_D,_E].

?- length(List, Length).
   List = [], Length = 0
;  List = [_A], Length = 1
;  List = [_A,_B], Length = 2
;  ..., ad_infinitum.

?- length([a|List],Length).
   List = [], Length = 1
;  List = [_A], Length = 2
;  List = [_A,_B], Length = 3
;  ..., ad_infinitum.

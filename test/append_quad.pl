% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/append_quad.pl

% ISO Prolog Prologue append/3 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue#append
%
% p.p.2 append/3
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% append(Xs, Ys, Zs) is true if Zs is the concatenation of the lists Xs and Ys.
% 
% More precisely, append(Xs, Ys, Zs) is true iff the list Xs is a list prefix of Zs and Ys is Zs with prefix Xs removed.
%
% Template and modes: append(?term, ?term, ?term)

append([], Zs, Zs).
append([X|Xs], Ys, [X|Zs]) :-
   append(Xs, Ys, Zs).

?- append([a,b],[c,d], Xs).
   Xs = [a,b,c,d].

?- append([a], nonlist, Xs).
   Xs = [a|nonlist].

?- append([a], Ys, Zs).
   Zs = [a|Ys].

?- append(Xs, Ys, [a,b,c]).
   Xs = [], Ys = [a,b,c]
;  Xs = [a], Ys = [b,c]
;  Xs = [a,b], Ys = [c]
;  Xs = [a,b,c], Ys = [].

?- append(Xs, Ys, [a,b|Xs]).
   Xs = [], Ys = [a,b]
;  Xs = [a], Ys = [b,a]
;  Xs = [a,b], Ys = [a,b]
;  Xs = [a,b,a], Ys = [b,a]
;  ..., ad_infinitum.

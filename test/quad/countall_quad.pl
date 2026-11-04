% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/countall_quad.pl

% ISO Prolog Prologue countall/2 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/countall
%
% countall/2
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% countall(G_0, N) is true iff N unifies with the total number of answers of call(G_0).
% 
% The following defines the procedural behaviour when no error conditions are satisified. 

countall(G_0, N) :-
   findall(t, G_0, Ts),
   length(Ts, N).

% Template and modes:  countall(+callable_term, ?integer) 
%
% Errors:
% a) G_0 is a variable
% — instantiation_error.
% b) G_0 is neither a variable nor a callable term
% — type_error(callable, G_0).
% c) N is neither a variable nor an integer
% — type_error(integer, Nth).
% d) N is an integer less than zero
% — domain_error(not_less_than_zero, Nth).
% e) The value of flag bounded is true and N is larger than max_integer
% — evaluation_error(int_overflow).
% —representation_error(max_integer). 

?- countall((X=1;X=2), N).
   N = 2.

?- countall((true;true), N).
   N = 2.

?- countall(G_0, N).
   instantiation_error.

?- countall((length(L,5),nth0(_,L,_),nth0(_,L,_)), N).
   N = 25.

?- countall(N = 1, N).
   N = 1.

?- countall(N = non_integer, N).
   N = 1.

?- countall(false, 1).
   false.

?- countall(false, -1).
   domain_error(not_less_than_zero,-1).

?- countall(false, non_integer).
   type_error(integer,non_integer).

% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/call_nth_quad.pl

% ISO Prolog Prologue call_nth/2 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/call_nth
%
% call_nth/2
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% call_nth(G_0, Nth) is true iff call(G_0) is true and N being the number of re-executions of call(G_0), Nth unifies with the integer N+1.
% 
% Procedurally, call_nth(G_0, Nth) is executed as follows:
% 
% a) Creates a counter N with value zero,
% b) If Nth is an integer smaller or equal N, the goal fails,
% or b') If there is no value greater N that is unifiable with Nth, the goal fails,
% c) (Re-)executes call(G_0),
% d) If it fails, the goal fails,
% e) Else if it succeeds, sets N to N+1,
% f) Unifies Nth with counter N,
% g) If the unification succeeds, the goal succeeds,
% h) Else proceeds to p.p.9.1 b,
% 
% call_nth(G_0, Nth) is re-executable. On backtracking, continue at p.p.9.1 g. 
%
% Template and modes: call_nth(?term, ?integer)
%
% errors:
% a) G_0 is a variable and Nth is not zero
% — instantiation_error.
% b) G_0 is neither a variable nor a callable term
% and Nth is not zero
% — type_error(callable, G_0).
% c) Nth is neither a variable nor an integer
% — type_error(integer, Nth).
% d) Nth is an integer less than zero
% — domain_error(not_less_than_zero, Nth).
% e) The value of flag bounded is true and at step
% p.p.9.1 e N+1 is larger than max_integer
% — evaluation_error(int_overflow).
% —representation_error(max_integer). 

?- call_nth(true, Nth).
   Nth = 1.

?- call_nth(false, Nth).
   false.

?- call_nth(repeat, Nth).
   Nth = 1
;  Nth = 2
;  Nth = 3
;  Nth = 4
;  Nth = 5
;  ... .

?- call_nth(( N = 1 ; N = 2 ), Nth).
   N = 1, Nth = 1
;  N = 2, Nth = 2.

?- call_nth(true, non_integer).
   type_error(integer,non_integer).

?- call_nth(true, 1.0).
   type_error(integer,1.0).

?- call_nth(true, 0).
   false.

?- call_nth(repeat, 0).
   false.

?- call_nth(repeat, -1).
   domain_error(not_less_than_zero,-1).

?- call_nth(length(L,N), 3).
   L = [_A,_B], N = 2.

?- call_nth(inex, 0).
   false. % thus not existence_error(procedure,inex/0)

?- call_nth(inex, 0).
   existence_error(procedure,_), unexpected.

?- call_nth(1, 0).
   false.

?- call_nth(V, 0).
   false.

?- call_nth(N = 1, N).
   N = 1.

?- call_nth(N = -1, N).
   false.

?- call_nth(repeat,1+1).
   type_error(integer,1+1).

% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/succ_quad.pl

% ISO Prolog Prologue succ/2 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue
%
% p.p.6 succ/2
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% succ(X, S) is true iff S is the successor of the non-negative integer X.
% 
% Procedurally, succ(X, S) is defined with the following clauses when no error condition is satisfied. 

succ(X, S) :-
   ( nonvar(S) -> S > 0, X is S-1 ; S is X+1 ).

% Template and modes:
% succ(?integer,+integer)
% succ(+integer,-integer)
%
% Errors:
% a) X is a variable and S is a variable.
% — instantiation_error.
% b) X is neither a variable nor an integer
% — type_error(integer, X).
% c) S is neither a variable nor an integer
% — type_error(integer, S).
% d) X is an integer that is less than zero
% — domain_error(not_less_than_zero, X).
% e) S is an integer that is less than zero
% — domain_error(not_less_than_zero, S).
% f) Flag bounded is true and X is maxint and S is a variable.
% — evaluation_error(int_overflow).
% — repesentation_error(max_integer). 
% NOTE — succ(X, X) requires an instantiation error although there is no solution. 

?- succ(X, S).
   instantiation_error.

?- succ(X, X).
   instantiation_error.

?- succ(0, S).
   S = 1.

?- succ(1, 1+1).
   type_error(integer, 1+1).

?- succ(X, 0).
   false.

?- succ(-1, S).
   domain_error(not_less_than_zero, -1).

?- current_prolog_flag(max_integer, MI), succ(MI, 0).
   false.

?- current_prolog_flag(max_integer, MI), succ(MI, 1).
   false.

?- current_prolog_flag(max_integer, MI), succ(MI, MI).
   false.

?- current_prolog_flag(max_integer, MI), succ(MI, S).
   false
|  evaluation_error(int_overflow)
|  representation_error(max_integer).


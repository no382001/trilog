%!  solve(+Goal) is nondet.
%   Cut: '$$choice_mark'/'$$cut_to' discard choice points, not the trail.
solve(Goal) :- '$$choice_mark'(Mark), solve(Goal, Mark).

solve(true, _Mark) :- !.
solve((A, B), Mark) :- !, solve(A, Mark), solve(B, Mark).
solve(!, Mark) :- !, '$$cut_to'(Mark).
solve(A, _Mark) :-
    '$$clause_candidates'(A, Cands),
    ( Cands == [] ->
        call(A)
    ; '$$choice_mark'(NewMark),
      '$solve_alts'(Cands, A, NewMark)
    ).

% This works like member/2 over the candidates, but the last one leaves no choicepoint.
'$solve_alts'([A1 - Body|Cs], A, Mark) :- '$solve_alt'(Cs, A1, Body, A, Mark).

% Indexing on [] vs [_|_] keeps a single candidate choicepoint-free.
'$solve_alt'([], A1, Body, A, Mark) :- A = A1, solve(Body, Mark).
'$solve_alt'([_|_], A1, Body, A, Mark) :- A = A1, solve(Body, Mark).
'$solve_alt'([C|Cs], _, _, A, Mark) :- '$solve_alts'([C|Cs], A, Mark).

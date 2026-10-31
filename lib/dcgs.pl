:- '$builtin_file'.

:- op(1200, xfx, '-->').
:- dynamic('$dcg_compiled'/2).

dcg_constr([]).
dcg_constr([_|_]).
dcg_constr((_, _)).
dcg_constr((_ ; _)).
dcg_constr((_ -> _)).
dcg_constr({_}).
dcg_constr(!).
dcg_constr(\+ _).
dcg_constr(G) :- compound(G), functor(G, call, N), N >= 1.

dcg_body(Var, S0, S, phrase(Var, S0, S)) :- var(Var), !.
dcg_body(GRBody, S0, S, Body) :-
    nonvar(GRBody),
    dcg_constr(GRBody),
    !,
    dcg_cbody(GRBody, S0, S, Body).
dcg_body(NonTerminal, S0, S, Goal) :-
    functor(NonTerminal, Name, Arity),
    '$dcg_ensure'(Name, Arity),
    NonTerminal =.. [Name|Args],
    append(Args, [S0, S], Args2),
    Goal =.. [Name|Args2].

dcg_cbody([], S0, S, S0 = S) :- !.
dcg_cbody([T|Ts], S0, S, Goal) :-
    !,
    dcg_terminals([T|Ts], S0, S, Goal).
% A leading ! or {} passes S0 straight on: its own output list is a fresh
% variable, so aliasing it at translation time saves an S1 = S0 goal.
dcg_cbody((A, B), S0, S, Goal) :-
    !,
    ( nonvar(A), A == ! -> Goal = (!, BT), dcg_body(B, S0, S, BT)
    ; nonvar(A), A = {G} -> Goal = (G, BT), dcg_body(B, S0, S, BT)
    ; Goal = (AT, BT), dcg_body(A, S0, S1, AT), dcg_body(B, S1, S, BT)
    ).
dcg_cbody((A ; B), S0, S, (AT ; BT)) :-
    !,
    dcg_body(A, S0, S, AT),
    dcg_body(B, S0, S, BT).
dcg_cbody((A -> B), S0, S, (AT -> BT)) :-
    !,
    dcg_body(A, S0, S1, AT),
    dcg_body(B, S1, S, BT).
dcg_cbody({G}, S0, S, (G, S0 = S)) :- !.
dcg_cbody(!, S0, S, (!, S0 = S)) :- !.
dcg_cbody(\+ G, S0, S, (\+ GT, S0 = S)) :- !, dcg_body(G, S0, _, GT).
dcg_cbody(Call, S0, S, '$dcg_call'(G, Extra, S0, S)) :- Call =.. [call, G|Extra].

% call//N compiles the nonterminal it builds, as a direct call would.
'$dcg_call'(G, Extra, S0, S) :-
    G =.. Parts0,
    append(Parts0, Extra, Parts),
    NonTerminal =.. Parts,
    functor(NonTerminal, Name, Arity),
    '$dcg_ensure'(Name, Arity),
    append(Parts, [S0, S], GoalParts),
    Goal =.. GoalParts,
    call(Goal).

dcg_terminals(Terminals, S0, S, S0 = List) :-
    append(Terminals, S, List).

%!  phrase(:Body, ?List) is nondet.
%!  phrase(:Body, ?List, ?Rest) is nondet.
phrase(GRBody, S0) :- phrase(GRBody, S0, []).

phrase(GRBody, S0, S) :-
    ( var(GRBody) -> throw(error(instantiation_error, phrase/3)) ; true ),
    dcg_body(GRBody, S0, S, Goal),
    call(Goal).

% A nonterminal's --> rules are stored as plain '-->' facts; translating a
% call to it compiles them into ordinary Name/Arity+2 clauses, so body calls
% go straight to Name(..., S0, S). Marked before compiling, so recursion stops.
'$dcg_ensure'(Name, Arity) :- '$dcg_compiled'(Name, Arity), !.
'$dcg_ensure'(Name, Arity) :-
    functor(Skel, Name, Arity),
    '$dcg_rules'(Skel, Rules),
    ( Rules == []
    -> true % hand-written Name/Arity+2, or undefined: the call decides
    ;  assertz('$dcg_compiled'(Name, Arity)),
       forall(member('-->'(H, B), Rules), '$dcg_compile'(H, B))
    ).

% Skel's rules in source order; a pushback rule's head is (Skel, Pushback).
'$dcg_rules'(Skel, Rules) :-
    '$$clause_candidates'('-->'((Skel, _), _), Pushback),
    (   Pushback == []
    ->  '$$clause_candidates'('-->'(Skel, _), Cands)
    ;   '$$clause_candidates'('-->'(_, _), Cands)
    ),
    findall('-->'(H, B),
            ( member('-->'(H, B) - true, Cands), ( H = (Skel, _) ; H = Skel ) ),
            Rules).

'$dcg_compile'((H, Pushback), B) :-
    !,
    '$dcg_head'(H, S0, S, H2),
    dcg_body(B, S0, S1, Body0),
    dcg_terminals(Pushback, S, S1, Back),
    '$dcg_fold_head'((Body0, Back), S0, Body),
    '$$assertz'((H2 :- Body)).
'$dcg_compile'(H, B) :-
    '$dcg_head'(H, S0, S, H2),
    dcg_body(B, S0, S, Body0),
    '$dcg_fold_head'(Body0, S0, Body),
    '$$assertz'((H2 :- Body)).

'$dcg_head'(H, S0, S, H2) :-
    H =.. [Name|Args],
    append(Args, [S0, S], Args2),
    H2 =.. [Name|Args2].

% A body starting with S0 = T unifies the head's input list first thing
% anyway, so do it in the head: count([_|S1], ...) instead of S0 = [_|S1].
'$dcg_fold_head'((A, B), S0, Body) :- !,
    '$dcg_fold_head'(A, S0, A1),
    ( A1 == true -> Body = B ; Body = (A1, B) ).
'$dcg_fold_head'(V = T, S0, true) :- V == S0, !, V = T.
'$dcg_fold_head'(G, _, G).

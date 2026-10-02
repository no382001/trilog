:- op(1200, xfx, '-->').

dcg_constr([]).
dcg_constr([_|_]).
dcg_constr((_, _)).
dcg_constr((_ ; _)).
dcg_constr((_ -> _)).
dcg_constr({_}).
dcg_constr(!).
dcg_constr(call(_)).

dcg_body(Var, S0, S, phrase(Var, S0, S)) :- var(Var), !.
dcg_body(GRBody, S0, S, Body) :-
    nonvar(GRBody),
    dcg_constr(GRBody),
    !,
    dcg_cbody(GRBody, S0, S, Body).
dcg_body(NonTerminal, S0, S, phrase(NonTerminal, S0, S)).

dcg_cbody([], S0, S, S0 = S) :- !.
dcg_cbody([T|Ts], S0, S, Goal) :-
    !,
    dcg_terminals([T|Ts], S0, S, Goal).
dcg_cbody((A, B), S0, S, (AT, BT)) :-
    !,
    dcg_body(A, S0, S1, AT),
    dcg_body(B, S1, S, BT).
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
dcg_cbody(call(G), S0, S, call(G, S0, S)) :- !.

dcg_terminals(Terminals, S0, S, S0 = List) :-
    append(Terminals, S, List).

%!  phrase(:Body, ?List) is nondet.
%!  phrase(:Body, ?List, ?Rest) is nondet.
phrase(GRBody, S0) :- phrase(GRBody, S0, []).

phrase(GRBody, S0, S) :-
    ( var(GRBody) ->
        throw(error(instantiation_error, phrase/3))
    ; dcg_constr(GRBody) ->
        dcg_body(GRBody, S0, S, Goal), call(Goal)
    ; '$$choice_mark'(Mark),
      '$$clause_candidates'('-->'(GRBody, RawBody), Cands),
      member('-->'(GRBody, RawBody) - true, Cands),
      dcg_body(RawBody, S0, S, Goal),
      solve(Goal, Mark)
    ).

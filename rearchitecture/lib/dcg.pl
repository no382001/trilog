:- op(1200, xfx, '-->').
:- dynamic('$dcg_compiled'/2).

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
dcg_body(NonTerminal, S0, S, '$dcg_call'(NonTerminal, S0, S)).

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
    ( var(GRBody) -> throw(error(instantiation_error, phrase/3)) ; true ),
    dcg_body(GRBody, S0, S, Goal),
    call(Goal).

% A nonterminal's --> rules are stored as plain '-->' facts; the first call
% compiles them into ordinary Name/Arity+2 clauses, run natively from then on.
'$dcg_call'(NT, S0, S) :-
    functor(NT, Name, Arity),
    '$dcg_ensure'(Name, Arity),
    call(NT, S0, S).

'$dcg_ensure'(Name, Arity) :- '$dcg_compiled'(Name, Arity), !.
'$dcg_ensure'(Name, Arity) :-
    functor(Skel, Name, Arity),
    '$$clause_candidates'('-->'(Skel, _), Cands),
    ( Cands == []
    -> true % hand-written Name/Arity+2, or undefined: call/3 decides
    ;  forall(member('-->'(H, B) - true, Cands), '$dcg_compile'(H, B)),
       assertz('$dcg_compiled'(Name, Arity))
    ).

'$dcg_compile'(H, B) :-
    H =.. [Name|Args],
    append(Args, [S0, S], Args2),
    H2 =.. [Name|Args2],
    dcg_body(B, S0, S, Body),
    assertz((H2 :- Body)).

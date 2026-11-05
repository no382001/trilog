:- '$builtin_file'.

:- module(trace, [trace_goal/1,
                  trace_goal/2]).

:- dynamic(mode/1).

%!  trace_goal(:Goal) is nondet.
%!  trace_goal(:Goal, +VarNames) is nondet.
%   Runs Goal like call/1, printing the Call, Exit, Redo, Fail and Exception
%   ports of the predicates current_predicate/1 sees; built-ins and library
%   predicates are one step each. VarNames, Name=Var pairs as read_term/3
%   gives them, name Goal's variables in the ports. At a terminal each port
%   waits for a key; h lists them.
trace_goal(G) :- trace_goal(G, []).
trace_goal(G, VNs) :-
    retractall(mode(_)),
    assertz(mode(creep)),
    '$$choice_mark'(M),
    solve(G, t(0, VNs), M).

solve(V, _, _) :- var(V), !, throw(error(instantiation_error, call/1)).
solve(true, _, _) :- !.
solve((A, B), D, M) :- !, solve(A, D, M), solve(B, D, M).
solve((C -> T ; E), D, M) :- !,
    (   '$$choice_mark'(M1), solve(C, D, M1) -> solve(T, D, M) ; solve(E, D, M) ).
solve((C -> T), D, M) :- !,
    (   '$$choice_mark'(M1), solve(C, D, M1) -> solve(T, D, M) ).
solve((A ; B), D, M) :- !, ( solve(A, D, M) ; solve(B, D, M) ).
solve(\+ G, D, _) :- !, \+ ( '$$choice_mark'(M1), solve(G, D, M1) ).
solve(!, _, M) :- !, '$$cut_to'(M).
solve(Mod:G, D, M) :- !, '$$qualify'(Mod, G, G1), solve(G1, D, M).
solve(catch(G, C, R), D, M) :- !,
    catch(( '$$choice_mark'(M1), solve(G, D, M1) ), C, solve(R, D, M)).
solve(G, D, _) :-
    G =.. [call, G0|Extra],
    !,
    (   Extra == [] -> G1 = G0
    ;   G0 =.. L0, append(L0, Extra, L), G1 =.. L
    ),
    '$$choice_mark'(M1),
    solve(G1, D, M1).
solve(G, t(D, VNs), _) :-
    D1 is D + 1,
    port(G, t(D1, VNs)).

% One goal's box: Call, then Exit or Fail, and Redo when it is backtracked
% into; an exception leaving it shows as Exception.
port(G, D) :-
    show(call, G, D),
    (   catch(run(G, D), E, ( show(exception(E), G, D), throw(E) ))
    ;   show(fail, G, D),
        fail
    ),
    (   show(exit, G, D)
    ;   show(redo, G, D),
        fail
    ).

run(G, T) :-
    functor(G, N, A),
    (   current_predicate(N/A)
    ->  '$$clause_candidates'(G, Cands),
        '$$choice_mark'(M),
        member(H-B, Cands),
        G = H,
        solve(B, T, M)
    ;   call(G)
    ).

show(Port, G, t(D, VNs)) :-
    mode(Mode),
    (   Mode == leap
    ->  true
    ;   Mode = skip(S), D > S
    ->  true
    ;   Mode = skip(S), D =:= S, Port \== exit, Port \== fail, \+ Port = exception(_)
    ->  true
    ;   write_port(Port, G, D, VNs),
        (   catch('$tl_tty', _, fail) -> ask(Port, D) ; nl )
    ).

write_port(Port, G, D, VNs) :-
    write('   '),
    (   Port = exception(E)
    ->  port_name(exception, X), write(X), write(' '), writeq(E)
    ;   port_name(Port, Name), write(Name)
    ),
    write(' ('), write(D), write(') '),
    write_term(G, [quoted(true), variable_names(VNs)]).

port_name(call, 'call:').
port_name(exit, 'exit:').
port_name(redo, 'redo:').
port_name(fail, 'fail:').
port_name(exception, 'exception:').

ask(Port, D) :-
    write(' ? '),
    flush_output,
    '$tl_key'(K),
    nl,
    (   key(K, Action) -> true ; Action = help ),
    act(Action, Port, D).

key(0'\r, creep).
key(0'\n, creep).
key(0'  , creep).
key(0'c, creep).
key(0's, skip).
key(0'l, leap).
key(0'a, abort).

act(creep, _, _) :- set_mode(creep).
act(skip, call, D) :- !, set_mode(skip(D)).
act(skip, _, _) :- set_mode(creep).
act(leap, _, _) :- set_mode(leap).
act(abort, _, _) :- throw(trace_aborted).
act(help, Port, D) :-
    write('   Enter, space or c: step to the next port'), nl,
    write('   s: skip over this goal (at a Call)'), nl,
    write('   l: run on without stopping'), nl,
    write('   a: abort the query'), nl,
    write('  '),
    ask(Port, D).

set_mode(M) :- retractall(mode(_)), assertz(mode(M)).

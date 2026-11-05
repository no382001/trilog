:- '$builtin_file'.

:- module(trace, [trace_goal/1]).

:- dynamic(mode/1).

%!  trace_goal(:Goal) is nondet.
%   Runs Goal like call/1, printing the Call, Exit, Redo, Fail and Exception
%   ports of the predicates current_predicate/1 sees; built-ins and library
%   predicates are one step each. At a terminal each port waits for a key:
%   Enter or c steps, s skips the goal, l runs on without stopping, a aborts.
trace_goal(G) :-
    retractall(mode(_)),
    assertz(mode(creep)),
    '$$choice_mark'(M),
    solve(G, 0, M).

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
solve(G, D, _) :-
    D1 is D + 1,
    port(G, D1).

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

run(G, D) :-
    functor(G, N, A),
    (   current_predicate(N/A)
    ->  '$$clause_candidates'(G, Cands),
        '$$choice_mark'(M),
        member(H-B, Cands),
        G = H,
        solve(B, D, M)
    ;   call(G)
    ).

show(Port, G, D) :-
    mode(Mode),
    (   Mode == leap
    ->  true
    ;   Mode = skip(S), D > S
    ->  true
    ;   Mode = skip(S), D =:= S, Port \== exit, Port \== fail, \+ Port = exception(_)
    ->  true
    ;   write_port(Port, G, D),
        (   catch('$tl_tty', _, fail) -> ask(Port, D) ; nl )
    ).

write_port(Port, G, D) :-
    write('   '),
    (   Port = exception(E)
    ->  port_name(exception, X), write(X), write(' '), writeq(E)
    ;   port_name(Port, Name), write(Name)
    ),
    write(' ('), write(D), write(') '),
    writeq(G).

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
    (   K =:= 0'a
    ->  throw(trace_aborted)
    ;   K =:= 0'l
    ->  set_mode(leap)
    ;   K =:= 0's, Port == call
    ->  set_mode(skip(D))
    ;   set_mode(creep)
    ).

set_mode(M) :- retractall(mode(_)), assertz(mode(M)).

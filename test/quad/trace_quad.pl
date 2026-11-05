% library(trace): the ports trace_goal/1 prints. Not at a terminal, it does
% not wait for keys.

:- use_module(library(trace)).

tp(1).
tp(2).
tq(X) :- tp(X), X > 1.
tc(X) :- tp(X), !.
tn :- \+ tp(3).
te :- throw(oops).
tf(X) :- catch(te, oops, X = caught).

traced(G, A) :- with_output_to(atom(A), once(trace_goal(G))).

?- traced(tq(2), A).
   A = '   Call: (1) tq(2)\n   Call: (2) tp(2)\n   Exit: (2) tp(2)\n   Call: (2) 2>1\n   Exit: (2) 2>1\n   Exit: (1) tq(2)\n'.

?- traced(tc(1), A).
   A = '   Call: (1) tc(1)\n   Call: (2) tp(1)\n   Exit: (2) tp(1)\n   Exit: (1) tc(1)\n'.

?- traced(tn, A).
   A = '   Call: (1) tn\n   Call: (2) tp(3)\n   Fail: (2) tp(3)\n   Exit: (1) tn\n'.

?- traced(tf(caught), A).
   A = '   Call: (1) tf(caught)\n   Call: (2) te\n   Call: (3) throw(oops)\n   Exception: oops (3) throw(oops)\n   Exception: oops (2) te\n   Call: (2) caught=caught\n   Exit: (2) caught=caught\n   Exit: (1) tf(caught)\n'.

?- with_output_to(atom(_), trace_goal(tq(1))).
   false.

?- with_output_to(atom(_), findall(X, trace_goal(tp(X)), Xs)).
   Xs = [1,2].

?- with_output_to(atom(_), trace_goal(member(X, [a]))).
   X = a.

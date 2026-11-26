% library(trace): the ports trace_goal/1,2 print. Not at a terminal, it does
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
   A = '   call: (1) tq(2)\n   call: (2) tp(2)\n   exit: (2) tp(2)\n   call: (2) 2>1\n   exit: (2) 2>1\n   exit: (1) tq(2)\n'.

?- traced(tc(1), A).
   A = '   call: (1) tc(1)\n   call: (2) tp(1)\n   exit: (2) tp(1)\n   exit: (1) tc(1)\n'.

?- traced(tn, A).
   A = '   call: (1) tn\n   call: (2) tp(3)\n   fail: (2) tp(3)\n   exit: (1) tn\n'.

?- traced(tf(caught), A).
   A = '   call: (1) tf(caught)\n   call: (2) te\n   call: (3) throw(oops)\n   exception: oops (3) throw(oops)\n   exception: oops (2) te\n   call: (2) caught=caught\n   exit: (2) caught=caught\n   exit: (1) tf(caught)\n'.

?- with_output_to(atom(_), trace_goal(tq(1))).
   false.

?- with_output_to(atom(_), findall(X, trace_goal(tp(X)), Xs)).
   Xs = [1,2].

?- with_output_to(atom(_), trace_goal(member(X, [a]))).
   X = a.

?- with_output_to(atom(A), once(trace_goal(tp(Y), ['Y'=Y]))).
   A = '   call: (1) tp(Y)\n   exit: (1) tp(1)\n', Y = 1.

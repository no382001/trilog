% parser tests

% --- valid terms ---

?- pfoo_atom.
   false.

pnum(42).

?- pnum(42).
   true.

pneg(-5).

?- pneg(-5).
   true.

pfvar(a).

?- pfvar(X).
   X = a.

pfvar2(a, b).

?- pfvar2(_, X).
   X = b.

pfnoarg.

?- pfnoarg.
   true.

pfone(a).

?- pfone(a).
   true.

pfmulti(a, b, c).

?- pfmulti(a, b, c).
   true.

pfnest(bar(baz(x))).

?- pfnest(bar(baz(X))).
   X = x.

% --- lists ---

pfl([]).

?- pfl([]).
   true.

pfl2([a]).

?- pfl2([X]).
   X = a.

pfl3([a, b, c]).

?- pfl3([a, b, c]).
   true.

pfl4([1, 2, 3]).

?- pfl4([H|T]).
   H = 1, T = [2, 3].

pfl5([1]).

?- pfl5([H|T]).
   H = 1, T = [].

?- pfl4([A, B|T]).
   A = 1, B = 2, T = [3].

pfnl([[a, b], [c]]).

?- pfnl([[a, X], Y]).
   X = b, Y = "c".

% --- clauses ---

plikes(mary, food).

?- plikes(mary, food).
   true.

pa(x).
pb(X) :- pa(X).

?- pb(X).
   X = x.

pa2(x).
pb2(x).
pc(X) :- pa2(X), pb2(X).

?- pc(X).
   X = x.

% --- whitespace handling ---

pws(  a  ,  b  ).

?- pws( a , b ).
   true.

ptab(	a	).

?- ptab(X).
   X = a.

pa3(x).
pb3(X):-pa3(X).

?- pb3(X).
   X = x.

% --- queries ---

pq(a).

?- pq(X).
   X = a.

pq2(a).
pq3(a).

?- pq2(X), pq3(X).
   X = a.

% --- edge cases ---

pfoo_bar(x).

?- pfoo_bar(X).
   X = x.

pfoo123(x).

?- pfoo123(X).
   X = x.

pfvar3(a).

?- pfvar3(X_1).
   X_1 = a.

% --- multiline clauses ---

pparent(tom, bob).
pancestor(X, Y) :-
  pparent(X, Y).

?- pancestor(tom, bob).
   true.

pfoo4(
  a,
  b,
  c
).

?- pfoo4(a, b, c).
   true.

paa(x).
pbb(x).
pcc(X) :-
  paa(X),
  pbb(X).

?- pcc(X).
   X = x.

% full-line comment
pfoo5(a).

?- pfoo5(a).
   true.

pfoo6(a). % this is ignored

?- pfoo6(a).
   true.

pfoo7(a).



pbar7(b).

?- pfoo7(a), pbar7(b).
   true.

pgreeting([104, 101, 108, 108, 111, 46, 119, 111, 114, 108, 100]).

?- pgreeting(X).
   X = [104, 101, 108, 108, 111, 46, 119, 111, 114, 108, 100].

pcolor(red).
pcolor(green).
pcolor(blue).

?- pcolor(green).
   true.

% core.pl

% --- true/false ---

?- true.
   true.

?- fail.
   false.

% --- unification ---

?- X = hello.
   X = hello.

?- X = 1, Y = 2.
   X = 1, Y = 2.

?- foo = foo.
   true.

?- foo = bar.
   false.

% --- member/2 ---

?- member(X, [a, b, c]).
   X = a
;  X = b
;  X = c.

?- member(d, [a, b, c]).
   false.

% --- append/3 ---

?- append([1, 2], [3, 4], X).
   X = [1, 2, 3, 4].

?- append([], [a], X).
   X = [a].

% --- length/2 ---

?- length([a, b, c], N).
   N = 3.

?- length([], N).
   N = 0.

% --- reverse/2 ---

?- reverse([1, 2, 3], X).
   X = [3, 2, 1].

?- reverse([], X).
   X = [].

% --- between/3 ---

?- between(1, 3, X).
   X = 1
;  X = 2
;  X = 3.

?- between(5, 5, X).
   X = 5.

% --- last/2 ---

?- last(X, [a, b, c]).
   X = c.

% --- arithmetic ---

?- X is 2 + 3.
   X = 5.

?- X is 10 - 4.
   X = 6.

?- X is 3 * 4.
   X = 12.

?- X is 10 / 2.
   X = 5.

?- X is 7 mod 3.
   X = 1.

% --- comparison ---

?- 3 < 5.
   true.

?- 5 < 3.
   false.

?- 3 =< 3.
   true.

?- 3 >= 3.
   true.

?- 3 =:= 3.
   true.

?- 3 =\= 4.
   true.

% --- lists ---

?- X = [1, 2, 3], member(2, X).
   X = [1, 2, 3].

?- append(X, Y, [1, 2]).
   X = [], Y = [1, 2]
;  X = [1], Y = [2]
;  X = [1, 2], Y = [].

% --- with helper clause ---

color(red).
color(green).
color(blue).

?- color(X).
   X = red
;  X = green
;  X = blue.

?- color(yellow).
   false.

% --- findall/3 ---

?- findall(X, member(X, [a, b, c]), L).
   L = [a, b, c].

?- findall(X, member(X, []), L).
   L = [].

% --- once/1 ---

?- once(member(X, [a, b, c])).
   X = a.

% --- negation ---

?- \+ fail.
   true.

?- \+ true.
   false.

% --- disjunction ;/2 ---

?- (true ; true).
   true
;  true.

?- (fail ; true).
   true.

?- (true ; fail).
   true.

?- (fail ; fail).
   false.

?- (X = a ; X = b).
   X = a
;  X = b.

?- findall(X, (X = a ; X = b), L).
   L = [a, b].

?- findall(X, (X = a ; X = b ; X = c), L).
   L = [a, b, c].

?- (fail ; X = hello).
   X = hello.

% --- if-then -> ---

?- (true -> X = yes).
   X = yes.

?- (fail -> X = yes).
   false.

% --- if-then-else (-> ;) ---

?- (true -> X = yes ; X = no).
   X = yes.

?- (fail -> X = yes ; X = no).
   X = no.

?- (true -> true ; fail).
   true.

?- (fail -> true ; true).
   true.

?- (fail -> true ; fail).
   false.

% -> commits: only first solution of condition
?- findall(X, ((X = a ; X = b) -> true ; true), L).
   L = [a].

% nested if-then-else
?- (true -> (true -> X = deep ; X = no) ; X = outer).
   X = deep.

?- (fail -> X = yes ; (true -> X = inner ; X = no)).
   X = inner.

% if-then-else with arithmetic
?- (1 =:= 1 -> X = equal ; X = not_equal).
   X = equal.

?- (1 =:= 2 -> X = equal ; X = not_equal).
   X = not_equal.

% --- structural equality ==/2 and \==/2 ---

?- a == a.
   true.

?- a == b.
   false.

?- f(a, b) == f(a, b).
   true.

?- f(a, b) == f(a, c).
   false.

?- X = a, X == a.
   X = a.

?- X == Y.
   false.

?- X = Y, X == Y.
   X = Y.

?- a \== b.
   true.

?- a \== a.
   false.

?- f(X) \== f(Y).
   true.

?- X = a, X \== a.
   false.

?- [1, 2, 3] == [1, 2, 3].
   true.

?- [1, 2] == [1, 2, 3].
   false.

% --- compare/3 ---

?- compare(Order, a, b).
   Order = <.

?- compare(Order, b, a).
   Order = >.

?- compare(Order, a, a).
   Order = =.

?- compare(Order, 1, 2).
   Order = <.

?- compare(Order, 3, 1).
   Order = >.

?- compare(Order, 1, a).
   Order = <.

?- compare(Order, f(1), f(2)).
   Order = <.

?- compare(Order, f(a, b), g(a, b)).
   Order = <.

?- compare(Order, f(a), f(a, b)).
   Order = <.

% --- term ordering @</2 @>/2 @=</2 @>=/2 ---

?- a @< b.
   true.

?- b @< a.
   false.

?- a @> b.
   false.

?- a @=< a.
   true.

?- a @>= a.
   true.

?- 1 @< a.
   true.

?- a @< f(a).
   true.

% --- msort/2 ---

?- msort([], X).
   X = [].

?- msort([3, 1, 2], X).
   X = [1, 2, 3].

?- msort([b, a, c], X).
   X = [a, b, c].

?- msort([b, a, c, a], X).
   X = [a, a, b, c].

?- msort([1, a, f(x)], X).
   X = [1, a, f(x)].

% --- sort/2 ---

?- sort([], X).
   X = [].

?- sort([3, 1, 2], X).
   X = [1, 2, 3].

?- sort([b, a, c, a], X).
   X = [a, b, c].

?- sort([1, 1, 1], X).
   X = [1].

?- sort([c, a, b, a, c], X).
   X = [a, b, c].

% --- throw/1 and catch/3 ---

?- catch(true, _, fail).
   true.

?- catch(fail, _, true).
   false.

?- catch(throw(oops), E, true).
   E = oops.

?- catch(throw(hello), hello, true).
   true.

?- catch(throw(foo), bar, true).
   error(unhandled exception).

?- catch(throw(error(type, ctx)), error(type, X), true).
   X = ctx.

throw_bound(X) :- X = 1, throw(X).

?- catch(throw_bound(X), 1, true).
   true.

?- catch(throw(a), E, (E == a)).
   E = a.

throw_first :- throw(first), throw(second).

?- catch(throw_first, E, true).
   E = first.

?- catch(catch(throw(inner), inner, throw(outer)), outer, true).
   true.

?- catch(catch(throw(deep), no_match, true), deep, true).
   true.

bind_and_succeed(X) :- X = 42.

?- catch(bind_and_succeed(X), _, fail).
   X = 42.

% --- re-consult ---

% core.pl is already auto-loaded; consulting it again should replace, not duplicate
:- consult('core.pl').

?- findall(X, member(X, [a, b, c]), L).
   L = [a, b, c].

:- consult('core.pl').

?- findall(X, member(X, [a, b, c]), L).
   L = [a, b, c].

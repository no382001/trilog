% ISO 13211 conformity tests (Szabo & Szeredi)

% --- true/0 ---

?- true.
   true.

% --- fail/0 ---

?- fail.
   false.

% --- !/0 ---

?- !.
   true.

?- (!,fail;true).
   false.

?- (call(!),fail;true).
   true.

% --- call/1 ---

b(X) :-
                Y = (write(X), X),
                call(Y).
a(1).
a(2).

?- call(!).
   true.

?- call(fail).
   false.

?- call((fail, _X)).
   false.

?- call((fail, call(1))).
   false.

?- (Z=!, call((Z=!, a(X), Z))).
   Z = !, X = 1.

?- (call((Z=!, a(X), Z))).
   Z = !, X = 1.
   Z = !, X = 2.

?- call(_X).
   error(instantiation_error).

?- call(1).
   error(type_error(callable,1)).

?- call((fail, 1)).
   error(type_error(callable,(fail,1))).

?- call((1; true)).
   error(type_error(callable,(1;true))).

% --- (,)/2 ---

?- ','(X=1, var(X)).
   false.

?- ','(var(X), X=1).
   X = 1.

?- ','(X = true, call(X)).
   X = true.

% --- (;)/2 ---

?- ';'(true, fail).
   true.

?- ';'((!, fail), true).
   false.

?- ';'(!, call(3)).
   true.

?- ';'((X=1, !), X=2).
   X = 1.

?- ';'(X=1, X=2).
   X = 1.
   X = 2.

% --- (->)/2 ---

?- '->'(true, true).
   true.

?- '->'(true, fail).
   false.

?- '->'(fail, true).
   false.

?- '->'(true, X=1).
   X = 1.

?- '->'(';'(X=1, X=2), true).
   X = 1.

?- '->'(true, ';'(X=1, X=2)).
   X = 1.
   X = 2.

% --- if-then-else ---

?- ';'('->'(true, true), fail).
   true.

?- ';'('->'(fail, true), true).
   true.

?- ';'('->'(true, fail), fail).
   false.

?- ';'('->'(fail, true), fail).
   false.

?- ';'('->'(true, X=1), X=2).
   X = 1.

?- ';'('->'(fail, X=1), X=2).
   X = 2.

?- ';'('->'(true, ';'(X=1, X=2)), true).
   X = 1.
   X = 2.

?- ';'('->'(';'(X=1, X=2), true), true).
   X = 1.

?- ';'('->'(','(!, fail), true), true).
   true.

% --- (\+)/1 ---

?- '\\+'(true).
   false.

?- '\\+'(!).
   false.

?- '\\+'((!,fail)).
   true.

?- ((X=1;X=2),'\\+'((!,fail))).
   X = 1.
   X = 2.

?- '\\+'(4 = 5).
   true.

?- '\\+'(3).
   error(type_error(callable,3)).

?- '\\+'(_X).
   error(instantiation_error).

% --- once/1 ---

?- once(!).
   true.

?- (once(!), (X=1; X=2)).
   X = 1.
   X = 2.

?- once(repeat).
   true.

?- once(fail).
   false.

?- once(3).
   error(type_error(callable,3)).

?- once(_X).
   error(instantiation_error).

% --- repeat/0 ---

?- (repeat, !, fail).
   false.

% --- (=)/2 ---

?- '='(1,1).
   true.

?- '='(X,1).
   X = 1.

?- '='(X,Y).
   X = Y.

?- '='(_,_).
   true.

?- ('='(X,Y),'='(X,abc)).
   X = abc, Y = abc.

?- '='(f(X,def),f(def,Y)).
   X = def, Y = def.

?- '='(1,2).
   false.

?- '='(1,1.0).
   false.

?- '='(g(X),f(f(X))).
   false.

?- '='(f(X,1),f(a(X))).
   false.

?- '='(f(X,Y,X),f(a(X),a(Y),Y,2)).
   false.

% --- (\=)/2 ---

?- '\\='(1,1).
   false.

?- \=(_X,1).
   false.

?- '\\='(_X,_Y).
   false.

?- \=(_,_).
   false.

?- \=(f(_X,def),f(def,_Y)).
   false.

?- '\\='(1,2).
   true.

?- \=(1,1.0).
   true.

?- '\\='(g(X),f(f(X))).
   true.

?- \=(f(X,1),f(a(X))).
   true.

?- '\\='(f(X,Y,X), f(a(X),a(Y),Y,2)).
   true.

% --- var/1 ---

?- var(foo).
   false.

?- var(_Foo).
   true.

?- (foo = Foo, var(Foo)).
   false.

?- var(_).
   true.

% --- atom/1 ---

?- atom(atom).
   true.

?- atom('string').
   true.

?- atom(a(b)).
   false.

?- atom(_Var).
   false.

?- atom([]).
   true.

?- atom(6).
   false.

?- atom(3.3).
   false.

% --- integer/1 ---

?- integer(3).
   true.

?- integer(-3).
   true.

?- integer(3.3).
   false.

?- integer(_X).
   false.

?- integer(atom).
   false.

% --- float/1 ---

?- float(3.3).
   true.

?- float(-3.3).
   true.

?- float(3).
   false.

?- float(atom).
   false.

?- float(_X).
   false.

% --- number/1 ---

?- number(3).
   true.

?- number(3.3).
   true.

?- number(-3).
   true.

?- number(a).
   false.

?- number(_X).
   false.

% --- atomic/1 ---

?- atomic(atom).
   true.

?- atomic(a(b)).
   false.

?- atomic(_Var).
   false.

?- atomic(6).
   true.

?- atomic(3.3).
   true.

% --- compound/1 ---

?- compound(33.3).
   false.

?- compound(-33.3).
   false.

?- compound(-a).
   true.

?- compound(_).
   false.

?- compound(a).
   false.

?- compound(a(b)).
   true.

?- compound([]).
   false.

?- compound([a]).
   true.

% --- nonvar/1 ---

?- nonvar(33.3).
   true.

?- nonvar(foo).
   true.

?- nonvar(_Foo).
   false.

?- (foo = Foo, nonvar(Foo)).
   true.

?- nonvar(_).
   false.

?- nonvar(a(b)).
   true.

% --- term comparison ---

?- '@=<'(1.0, 1).
   true.

?- '@<'(1.0, 1).
   true.

?- '\\=='(1, 1).
   false.

?- '@=<'(aardvark, zebra).
   true.

?- '@=<'(short, short).
   true.

?- '@=<'(short, shorter).
   true.

?- '@>='(short, shorter).
   false.

?- '@<'(foo(a,b), north(a)).
   false.

?- '@>'(foo(b), foo(a)).
   true.

?- '@<'(foo(a, _X), foo(b, _Y)).
   true.

?- '@=<'(X, X).
   true.

?- '=='(X, X).
   true.

?- '=='(_X, _Y).
   false.

?- \==(_, _).
   true.

?- '=='(_, _).
   false.

% --- functor/3 ---

?- functor(foo(a,b,c), foo, 3).
   true.

?- functor(foo(a,b,c),X,Y).
   X = foo, Y = 3.

?- functor(X,foo,3).
   X = foo(_A,_B,_C).

?- functor(X,foo,0).
   X = foo.

?- functor(mats(A,B),A,B).
   A = mats, B = 2.

?- functor(foo(a),foo,2).
   false.

?- functor(foo(a),fo,1).
   false.

?- functor(1,X,Y).
   X = 1, Y = 0.

?- functor(X,1.1,0).
   X = 1.1.

?- functor([_|_],'.',2).
   true.

?- functor([],[],0).
   true.

?- functor(_X, _Y, 3).
   error(instantiation_error).

?- functor(_X, foo, _N).
   error(instantiation_error).

?- functor(_X, foo, a).
   error(type_error(integer,a)).

?- functor(_F, 1.5, 1).
   error(type_error(atom,1.5)).

?- functor(_F,foo(a),1).
   error(type_error(atomic,foo(a))).

% --- arg/3 ---

?- arg(1, foo(a,b), a).
   true.

?- arg(1,foo(a,b),X).
   X = a.

?- arg(1,foo(X,b),a).
   X = a.

?- arg(1,foo(X,b),Y).
   Y = X.

?- arg(1,foo(a,b),b).
   false.

?- arg(0,foo(a,b),foo).
   false.

?- arg(3,foo(3,4),_N).
   false.

?- arg(_X,foo(a,b),a).
   error(instantiation_error).

?- arg(1,_X,a).
   error(instantiation_error).

?- arg(0,atom,_A).
   error(type_error(compound,atom)).

?- arg(0,3,_A).
   error(type_error(compound,3)).

?- arg(a,foo(a,b),_X).
   error(type_error(integer,a)).

?- arg(2,foo(a,f(X,b),c), f(a,Y)).
   X = a, Y = b.

?- arg(1,3,_A).
   error(type_error(compound,3)).

% --- (=..)/2 ---

?- '=..'(foo(a,b), [foo,a,b]).
   true.

?- '=..'(X, [foo,a,b]).
   X = foo(a,b).

?- '=..'(foo(a,b), L).
   L = [foo,a,b].

?- '=..'(foo(X,b), [foo,a,Y]).
   X = a, Y = b.

?- '=..'(1, [1]).
   true.

?- '=..'(foo(a,b), [foo,b,a]).
   false.

?- '=..'(_X, _Y).
   error(instantiation_error).

?- '=..'(_X, [foo,a|_Y]).
   error(instantiation_error).

?- '=..'(_X, [foo|bar]).
   error(type_error(list,[foo|bar])).

?- '=..'(_X, [_Foo,bar]).
   error(instantiation_error).

?- '=..'(_X, [3,1]).
   error(type_error(atom,3)).

?- '=..'(_X, [1.1,foo]).
   error(type_error(atom,1.1)).

?- '=..'(_X, [a(b),1]).
   error(type_error(atom,a(b))).

?- '=..'(_X, 4).
   error(type_error(list,4)).

?- '=..'(_X, [f(a)]).
   error(type_error(atomic,f(a))).

% --- copy_term/2 ---

?- copy_term(_X,_Y).
   true.

?- copy_term(_X,3).
   true.

?- copy_term(_,a).
   true.

?- copy_term(a+X,X+b).
   X = a.

?- copy_term(_,_).
   true.

?- copy_term(X+X+_Y,A+B+B).
   A = B.

?- copy_term(a,b).
   false.

?- (copy_term(a+X,X+b), copy_term(a+X,X+b)).
   false.

% --- (is)/2 ---

?- X is '+'(7, 35).
   X = 42.

?- X is '+'(0, 3+11).
   X = 14.

?- X is '+'(0, 3.2+11).
   X = 14.2.

?- _X is '+'(77, _N).
   error(instantiation_error).

?- _X is '+'(foo, 77).
   error(type_error(evaluable,foo/0)).

?- X is '-'(7).
   X = -7.

?- X is '-'(3-11).
   X = 8.

?- X is '-'(3.2-11).
   X = 7.8.

?- _X is '-'(_N).
   error(instantiation_error).

?- _X is '-'(foo).
   error(type_error(evaluable,foo/0)).

?- X is '-'(7,35).
   X = -28.

?- X is '-'(20,3+11).
   X = 6.

?- X is '-'(0,3.2+11).
   X = -14.2.

?- _X is '-'(77, _N).
   error(instantiation_error).

?- _X is '-'(foo, 77).
   error(type_error(evaluable,foo/0)).

?- X is '*'(7,35).
   X = 245.

?- X is '*'(0,3+11).
   X = 0.

?- _X is '*'(77, _N).
   error(instantiation_error).

?- _X is '*'(foo, 77).
   error(type_error(evaluable,foo/0)).

?- X is '//'(7,35).
   X = 0.

?- X is '/'(7.0,35).
   X = 0.2.

?- X is '//'(140,3+11).
   X = 10.

?- _X is '/'(77, _N).
   error(instantiation_error).

?- _X is '/'(foo, 77).
   error(type_error(evaluable,foo/0)).

?- _X is '/'(3, 0).
   error(evaluation_error(zero_divisor)).

?- X is mod(7,3).
   X = 1.

?- X is mod(0,3+11).
   X = 0.

?- X is mod(7,-2).
   X = -1.

?- _X is mod(77, _N).
   error(instantiation_error).

?- _X is mod(foo, 77).
   error(type_error(evaluable,foo/0)).

?- _X is mod(7.5, 2).
   error(type_error(integer,7.5)).

?- _X is mod(7, 0).
   error(evaluation_error(zero_divisor)).

?- X is floor(7.4).
   X = 7.

?- X is floor(-0.4).
   X = -1.

?- X is round(7.5).
   X = 8.

?- X is round(7.6).
   X = 8.

?- X is round(-0.6).
   X = -1.

?- _X is round(_N).
   error(instantiation_error).

?- X is ceiling(-0.5).
   X = 0.

?- X is truncate(-0.5).
   X = 0.

?- _X is truncate(foo).
   error(type_error(evaluable,foo/0)).

?- X is float(7).
   X = 7.0.

?- X is float(7.3).
   X = 7.3.

?- X is float(5//3).
   X = 1.0.

?- _X is float(_N).
   error(instantiation_error).

?- _X is float(foo).
   error(type_error(evaluable,foo/0)).

?- X is abs(7).
   X = 7.

?- X is abs(3-11).
   X = 8.

?- X is abs(3.2-11.0).
   X = 7.8.

?- _X is abs(_N).
   error(instantiation_error).

?- _X is abs(foo).
   error(type_error(evaluable,foo/0)).

?- (current_prolog_flag( max_integer, MI), _X is '+'(MI,1)).
   error(evaluation_error(int_overflow)).

?- (current_prolog_flag( max_integer, MI), _X is '-'('+'(MI,1),1)).
   error(evaluation_error(int_overflow)).

?- (current_prolog_flag( max_integer, MI), _X is '-'( -2,MI)).
   error(evaluation_error(int_overflow)).

?- (current_prolog_flag( max_integer, MI), _X is '*'(MI,2)).
   error(evaluation_error(int_overflow)).

?- (current_prolog_flag( max_integer, MI), R is float(MI)*2, _X is floor(R)).
   error(evaluation_error(int_overflow)).

% --- arithmetic comparison ---

?- '=:='(0,1).
   false.

?- '=\\='(0, 1).
   true.

?- '<'(0, 1).
   true.

?- '>'(0, 1).
   false.

?- '>='(0, 1).
   false.

?- '=<'(0, 1).
   true.

?- '=:='(1.0, 1).
   true.

?- =\=(1.0, 1).
   false.

?- '<'(1.0, 1).
   false.

?- '>'(1.0, 1).
   false.

?- '>='(1.0, 1).
   true.

?- '=<'(1.0, 1).
   true.

?- '=:='(3*2, 7-1).
   true.

?- '=\\='(3*2, 7-1).
   false.

?- '<'(3*2, 7-1).
   false.

?- '>'(3*2, 7-1).
   false.

?- '>='(3*2, 7-1).
   true.

?- '=<'(3*2, 7-1).
   true.

?- '=:='(_X, 5).
   error(instantiation_error).

?- =\=(_X, 5).
   error(instantiation_error).

?- '<'(_X, 5).
   error(instantiation_error).

?- '>'(_X, 5).
   error(instantiation_error).

?- '>='(_X, 5).
   error(instantiation_error).

?- '=<'(_X, 5).
   error(instantiation_error).

% --- findall/3 ---

?- findall(X,(X=1;X=2),S).
   S = [1,2].

?- findall(X+_Y,(X=1),S).
   S = [1+_].

?- findall(_X,fail,L).
   L = [].

?- findall(X,(X=1;X=1),S).
   S = [1,1].

?- findall(X,(X=2;X=1),[1,2]).
   false.

?- findall(X,(X=1;X=2),[X,Y]).
   X = 1, Y = 2.

?- findall(_X,_Goal,_S).
   error(instantiation_error).

?- findall(_X,4,_S).
   error(type_error(callable,4)).

?- findall(X,X=1,[A|1]).
   error(type_error(list,[A|1])).

% --- bagof/3 ---

?- bagof(X,(X=1;X=2),S).
   S = [1, 2].

?- bagof(X,(X=1;X=2),X).
   X = [1, 2].

?- bagof(X,(X=Y;X=Z),S).
   S = [Y, Z].

?- bagof(_X,fail,_S).
   false.

?- bagof(f(X,Y),(X=a;Y=b),L).
   L = [f(a, _), f(_, b)].

?- bagof(X,Y^((X=1,Y=1) ;(X=2,Y=2)),S).
   S = [1, 2].

?- bagof(X,Y^((X=1;Y=1) ;(X=2,Y=2)),S).
   S = [1, _, 2].

?- bagof(_X,_Y^_Z,_L).
   error(instantiation_error).

?- bagof(_X,1,_L).
   error(type_error(callable,1)).

% --- setof/3 ---

my_member(X, [X|_]).
my_member(X, [_|L]) :-
                my_member(X, L).

?- setof(X,(X=1;X=2),S).
   S = [1, 2].

?- setof(X,(X=1;X=2),X).
   X = [1, 2].

?- setof(X,(X=2;X=1),S).
   S = [1, 2].

?- setof(X,(X=2;X=2),S).
   S = [2].

?- setof(_X,fail,_S).
   false.

?- setof(f(X,Y),(X=a;Y=b),L).
   L = [f(_, b),f(a, _)].

?- setof(X,Y^((X=1,Y=1) ;(X=2,Y=2)),S).
   S = [1, 2].

?- setof(X,Y^((X=1;Y=1) ;(X=2,Y=2)),S).
   S = [_, 1, 2].

?- setof(X,my_member(X,[f(b,U), f(c,V)]), [f(b,a),f(c,a)]).
   U = a, V = a.

?- setof(X, my_member(X,[V,U,f(U),f(V)]), [a,b,f(b),f(a)]).
   false.

?- setof(X, exists(U,V)^my_member(X,[V,U,f(U),f(V)]), [a,b,f(a),f(b)]).
   true.

?- setof(X, X^(true; 4),_L).
   error(type_error(callable,(true;4))).

?- setof(_X,A^A^1,_L).
   error(type_error(callable,1)).

?- setof(X,X=1,[1|A]).
   A = [].

?- setof(X,X=1,[A|1]).
   error(type_error(list,[A|1])).

% --- asserta/1 ---

:- dynamic(legs/2).
legs(A, 4) :- animal(A).
legs(octopus, 8).
legs(A, 6) :- insect(A).
:- dynamic(insect/1).
insect(ant).
insect(bee).

:- dynamic(legs/2).
legs(A, 6) :- insect(A).
:- dynamic(insect/1).
insect(ant).
insect(bee).

:- dynamic(legs/2).
legs(octopus, 8).
legs(A, 6) :- insect(A).
:- dynamic(insect/1).
insect(ant).
insect(bee).

?- asserta(legs(octopus, 8)).
   true.

?- asserta( (legs(A,4):-animal(A))).
   true.

?- asserta((foo(X) :- X,call(X))).
   true.

?- asserta(_).
   error(instantiation_error).

?- asserta(4).
   error(type_error(callable,4)).

?- asserta((foo :- 4)).
   error(type_error(callable,4)).

?- asserta((atom(_) :- true)).
   error(permission_error(modify,static_procedure, @atom/1)).

?- (asserta(insct(bee)), insct(X), asserta(insct(ant)),insct(Y)).
   X = bee, Y = ant.
   X = bee, Y = bee.

% --- assertz/1 ---

:- dynamic(legs/2).
legs(A, 4) :- animal(A).
legs(octopus, 8).
legs(A, 6) :- insect(A).
:- dynamic(insect/1).
insect(ant).
insect(bee).
:- dynamic(foo/1).
foo(X) :- call(@X), call(@X).

:- dynamic(legs/2).
legs(A, 4) :- animal(A).
legs(octopus, 8).
legs(A, 6) :- insect(A).
legs(spider, 8).
legs(B, 2) :- bird(B).
:- dynamic(insect/1).
insect(ant).
insect(bee).
:- dynamic(foo/1).
foo(X) :- call(@X), call(@X).

:- dynamic(legs/2).
legs(A, 4) :- animal(A).
legs(octopus, 8).
legs(A, 6) :- insect(A).
legs(spider, 8).
:- dynamic(insect/1).
insect(ant).
insect(bee).
:- dynamic(foo/1).
foo(X) :- call(@X), call(@X).

?- assertz(legs(spider, 8)).
   true.

?- assertz((legs(B, 2):-bird(B))).
   true.

?- assertz((foo(X):-X->call(X))).
   true.

?- assertz(_).
   error(instantiation_error).

?- assertz(4).
   error(type_error(callable,4)).

?- assertz((foo :- 4)).
   error(type_error(callable,4)).

?- assertz((atom(_) :- true)).
   error(permission_error(modify,static_procedure, @atom/1)).

% --- retract/1 ---

:- dynamic(legs/2).
legs(A, 4) :- animal(A).
legs(octopus, 8).
legs(A, 6) :- insect(A).
legs(spider, 8).
legs(B, 2) :- bird(B).
:- dynamic(insect/1).
insect(ant).
insect(bee).
:- dynamic(foo/1).
foo(X) :- call(@X), call(@X).
foo(X) :- call(@X) -> call(@X).

:- dynamic(legs/2).
legs(A, 4) :- animal(A).
legs(A, 6) :- insect(A).
legs(spider, 8).
:- dynamic(insect/1).
insect(ant).
insect(bee).
:- dynamic(foo/1).
foo(X) :- call(@X), call(@X).
foo(X) :- call(@X) -> call(@X).

:- dynamic(legs/2).
legs(A, 4) :- animal(A).
legs(A, 6) :- insect(A).
legs(spider, 8).
legs(B, 2) :- bird(B).
:- dynamic(insect/1).
insect(ant).
insect(bee).
:- dynamic(foo/1).
foo(X) :- call(@X), call(@X).
foo(X) :- call(@X) -> call(@X).

:- dynamic(legs/2).
:- dynamic(insect/1).
insect(ant).
insect(bee).
:- dynamic(foo/1).
foo(X) :- call(@X), call(@X).
foo(X) :- call(@X) -> call(@X).

?- retract(legs(octopus, 8)).
   true.

?- retract(legs(spider, 6)).
   false.

?- retract((legs(X, 2) :- T)).
   T = bird(X).

?- retract((legs(X, Y) :- Z)).
   Y = 4, Z = animal(X).
   Y = 6, Z = insect(X).
   X = spider, Y = 8, Z = true.

?- retract((legs(_X, _Y) :- _Z)).
   false.

?- retract((_X :- in_eec(_Y))).
   error(instantiation_error).

?- retract((4 :- _X)).
   error(type_error(callable,4)).

?- retract((atom(X) :- X =='[]')).
   error(permission_error(modify,static_procedure, @atom/1)).

% --- abolish/1 ---

:- dynamic(insect/1).
insect(ant).
insect(bee).
:- dynamic(foo/1).
foo(X) :- call(X), call(X).
foo(X) :- call(X) -> call(X).
bar(X) :- true.

?- abolish(foo/2).
   true.

?- abolish(foo/_).
   error(instantiation_error).

?- abolish(foo).
   error(type_error(predicate_indicator,@foo)).

?- abolish(foo(X)).
   error(type_error(predicate_indicator,@foo(X))).

?- abolish(abolish/1).
   error(permission_error(modify,static_procedure, @abolish/1)).

?- abolish(foo/1).
   true.

?- (insect(X), abolish(insect/1)).
   X = ant.
   X = bee.

?- abolish(foo/_).
   error(instantiation_error).

?- abolish(bar/1).
   error(permission_error(modify,static_procedure, @bar/1)).

?- abolish(foo/a).
   error(type_error(integer,a)).

?- abolish(5/2).
   error(type_error(atom,5)).

?- abolish(insect).
   error(type_error(predicate_indicator,@insect)).

% --- atom_length/2 ---

?- atom_length( 'enchanted evening', N).
   N = 17.

?- atom_length( 'enchanted\ evening', N).
   N = 17.

?- atom_length('', N).
   N = 0.

?- atom_length('scarlet', 5).
   false.

?- atom_length(_Atom, 4).
   error(instantiation_error).

?- atom_length(1.23, 4).
   error(type_error(atom,1.23)).

?- atom_length(atom, '4').
   error(type_error(integer,'4')).

?- atom_length('Bartók Béla', L).
   L = 11.

?- atom_length(_Atom, N).
   error(instantiation_error).

?- atom_length(atom, N).
   false.

% --- atom_concat/3 ---

?- atom_concat('hello', ' world', S3).
   S3 = 'hello world'.

?- atom_concat(T, ' world', 'small world').
   T = 'small'.

?- atom_concat('hello',' world', 'small world').
   false.

?- atom_concat(T1, T2, 'hello').
   T1 = '', T2 = 'hello'.
   T1 = 'h', T2 = 'ello'.
   T1 = 'he', T2 = 'llo'.
   T1 = 'hel', T2 = 'lo'.
   T1 = 'hell', T2 = 'o'.
   T1 = 'hello', T2 = ''.

?- atom_concat(small, _V2, _V4).
   error(instantiation_error).

?- atom_concat(_A, 'iso', _C).
   error(instantiation_error).

?- atom_concat('iso', _B, _C).
   error(instantiation_error).

?- atom_concat(f(a), 'iso', _C).
   error(type_error(atom,f(a))).

?- atom_concat('iso', f(a), _C).
   error(type_error(atom,f(a))).

?- atom_concat(_A, _B, f(a)).
   error(type_error(atom,f(a))).

?- atom_concat('Bartók ', 'Béla', N).
   N = 'Bartók Béla'.

?- atom_concat(N, 'Béla', 'Bartók Béla').
   N = 'Bartók '.

?- atom_concat('Bartók ', N, 'Bartók Béla').
   N = 'Béla'.

?- atom_concat(T1, T2, 'Pécs').
   T1 = '', T2 = 'Pécs'.
   T1 = 'P', T2 = 'écs'.
   T1 = 'Pé', T2 = 'cs'.
   T1 = 'Péc', T2 = 's'.
   T1 = 'Pécs', T2 = ''.

% --- atom_chars/2 ---

?- atom_chars('', L).
   L = [].

?- atom_chars([], L).
   L = ['[',']'].

?- atom_chars('''', L).
   L = [''''].

?- atom_chars('ant', L).
   L = ['a','n','t'].

?- atom_chars(Str, ['s','o','p']).
   Str = 'sop'.

?- atom_chars('North', ['N'|X]).
   X = ['o','r','t','h'].

?- atom_chars('soap', ['s','o','p']).
   false.

?- atom_chars(_X, _Y).
   error(instantiation_error).

?- atom_chars(_A, [a,_E,c]).
   error(instantiation_error).

?- atom_chars(_A, [a,b|_L]).
   error(instantiation_error).

?- atom_chars(f(a), _L).
   error(type_error(atom,f(a))).

?- atom_chars(_A, iso).
   error(type_error(list,iso)).

?- atom_chars(_A, [a,f(b)]).
   error(type_error(character,f(b))).

?- atom_chars('Pécs', L).
   L = ['P','é','c','s'].

?- atom_chars(A, ['P','é','c','s']).
   A = 'Pécs'.

% --- atom_codes/2 ---

?- atom_codes('', L).
   L = [].

?- atom_codes([], L).
   L = [0'[, 0']].

?- atom_codes('''',L).
   L = [39 ].

?- atom_codes('ant', L).
   L = [0'a, 0'n, 0't].

?- atom_codes(Str, [0's,0'o,0'p]).
   Str = 'sop'.

?- atom_codes('North',[0'N|X]).
   X = [0'o,0'r,0't,0'h].

?- atom_codes('soap', [0's, 0'o, 0'p]).
   false.

?- atom_codes(_X, _Y).
   error(instantiation_error).

?- atom_codes(f(a), _L).
   error(type_error(atom,f(a))).

?- atom_codes(_, 0'x).
   error(type_error(list,0'x)).

?- atom_codes('Pécs', C).
   C = [0'P,0'é,0'c,0's].

?- atom_codes(A, [0'P,0'é,0'c,0's]).
   A = 'Pécs'.

% --- char_code/2 ---

?- char_code(a, Code).
   Code = 0'a.

?- char_code(Char, 0'c).
   Char = c.

?- char_code(b, 0'b).
   true.

?- char_code('ab', _Code).
   error(type_error(character,'ab')).

?- char_code(_Char, _Code).
   error(instantiation_error).

?- char_code(a, x).
   error(type_error(integer,x)).

% --- number_chars/2 ---

?- number_chars(33, L).
   L = ['3','3'].

?- number_chars(33, ['3','3']).
   true.

?- number_chars(X, ['3','.','3','E','+','0']).
   X = 3.3.

?- number_chars(3.3, ['3'|_L]).
   true.

?- number_chars(A, ['-','2','5']).
   A = -25.

?- number_chars(A,['\n',' ','3']).
   A = 3.

?- number_chars(A, ['0',x,f]).
   A = 15.

?- number_chars(A, ['0','''',a]).
   A = 0'a.

?- number_chars(A, ['4','.','2']).
   A = 4.2.

?- number_chars(A, ['4','2','.','0','e','-','1']).
   A = 4.2.

?- number_chars(_A, _L).
   error(instantiation_error).

?- number_chars(a, _L).
   error(type_error(number,a)).

?- number_chars(_A, 4).
   error(type_error(list,4)).

?- number_chars(_A, ['4',2]).
   error(type_error(character,2)).

?- number_chars(_A, [a|_L]).
   error(instantiation_error).

?- number_chars(_A, [a,_L]).
   error(instantiation_error).

?- number_chars(X, [' ', '0', 'o', '1', '1']).
   X = 9.

?- number_chars(X, [' ', '0', 'x', '1', '1']).
   X = 17.

?- number_chars(X, [' ', '0', 'b', '1', '1']).
   X = 3.

% --- number_codes/2 ---

?- number_codes(33, L).
   L = [0'3,0'3].

?- number_codes(33, [0'3,0'3]).
   true.

?- number_codes(33.0, [0'3|_L]).
   true.

?- number_codes(A, [0'-,0'2,0'5]).
   A = -25.

?- number_codes(A, [0' , 0'3]).
   A = 3.

?- number_codes(A, [0'0,0'x,0'f]).
   A = 15.

?- number_codes(A,[0'0,39,0'a]).
   A = 0'a.

?- number_codes(A, [0'4,0'.,0'2]).
   A = 4.2.

?- number_codes(A, [ 0'4,0'2,0'.,0'0,0'e,0'-,0'1]).
   A = 4.2.

?- number_codes(_A, _L).
   error(instantiation_error).

?- number_codes(a, _L).
   error(type_error(number,a)).

?- number_codes(_A, 4).
   error(type_error(list,4)).

?- number_codes(_A, [0'a|_L]).
   error(instantiation_error).

?- number_codes(_A, [0'a,_L]).
   error(instantiation_error).

?- (number_chars(X, [' ', '0', 'x', '1', '1', '1']), number_codes(X, Y)).
   X = 273, Y = [50,55,51].

?- (number_chars(X, [' ', '0', 'o', '1', '1', '1']), number_codes(X, Y)).
   X = 73, Y = [55,51].

?- (number_chars(X, [' ', '0', 'b', '1', '1', '1']), number_codes(X, Y)).
   X = 7, Y = [55].

% --- sub_atom/5 ---

?- sub_atom(abracadabra,3, Length,3,S2).
   Length = 5, S2 = 'acada'.

?- sub_atom(abracadabra, Before, 2, After, ab).
   Before = 0, After = 9.
   Before = 7, After = 2.

?- sub_atom(_Banana, 3, 2, _, _S).
   error(instantiation_error).

?- sub_atom(f(a), 2, 2, _, _S2).
   error(type_error(atom,f(a))).

?- sub_atom('Banana', 4, 2, _, 2).
   error(type_error(atom,2)).

?- sub_atom('Banana', a, 2, _, _).
   error(type_error(integer,a)).

?- sub_atom('Banana', 4, n, _, _).
   error(type_error(integer,n)).

?- sub_atom('Banana', 4, _, m, _).
   error(type_error(integer,m)).

?- sub_atom('Banana', 2, 3, A, 'nan').
   A = 1.

?- sub_atom('Banana', B, 3, 1, 'nan').
   B = 2.

?- sub_atom('Banana', 2, L, 1, 'nan').
   L = 3.

?- sub_atom('Banana', 2, L, A, 'nan').
   A = 1, L = 3.

?- sub_atom('Banana', B, L, 1, 'nan').
   B = 2, L = 3.

?- sub_atom('Banana', 2, 3, 1, 'ana').
   false.

?- sub_atom('Banana', 2, 3, 2, 'nan').
   false.

?- sub_atom('Banana', 2, 3, 2, _).
   false.

?- sub_atom('Banana', 2, 3, 1, 'anan').
   false.

?- sub_atom('Banana', 0, 7, 0, _).
   false.

?- sub_atom('Banana', 7, 0, 0, _).
   false.

?- sub_atom('Banana', 0, 0, 7, _).
   false.

?- sub_atom(a, N, 1, 2, 1+2).
   error(type_error(atom,1+2)).

?- sub_atom(a, N, 1, 2, 1+2).
   error(type_error(atom,1+2)).

?- sub_atom('Bartók Béla', 4, 2, A, S).
   A = 5, S = 'ók'.

?- sub_atom('Bartók Béla', 4, L, 5, S).
   L = 2, S = 'ók'.

?- sub_atom('Bartók Béla', B, 2, 5, S).
   B = 4, S = 'ók'.

?- sub_atom('Pécs',B,2,A,S).
   B = 0, A = 2, S = 'Pé'.
   B = 1, A = 1, S = 'éc'.
   B = 2, A = 0, S = 'cs'.

?- sub_atom(abracadabra,B,L,A,abra).
   B = 0, L = 4, A = 7.
   B = 7, L = 4, A = 0.

?- sub_atom(a, N, 1, 2, _).
   false.

?- sub_atom(a, 1, N, 2, _).
   false.

?- sub_atom(a, 1, 2, N, _).
   false.

% --- catch/3 and throw/1 ---

foo(X) :-
                Y is X * 2, throw(test(Y)).
bar(X) :-
                X = Y, throw(Y).
coo(X) :-
                throw(X).
car(X) :-
                X = 1, throw(X).
g :-
                catch(p, _B, write(h2)),
                coo(c).
p.
p :-
                throw(b).

?- catch(foo(5),test(Y), true).
   Y = 10.

?- catch(bar(3),Z,true).
   Z = 3.

?- catch(true,_,3).
   true.

?- catch(car(_X),Y,true).
   Y = 1.

?- catch( number_chars(_X,['1',a,'0']), error(syntax_error(_),_), fail).
   false.

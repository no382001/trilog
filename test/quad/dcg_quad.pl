% DCG translation: the ISO DCG draft (ISO/IEC DTS 13211-3) control constructs

:- consult('test/quad/files/dcg_rules.pl').

% --- terminals, sequences, alternatives, {}, ! and -> ---

?- phrase(greeting, [hello, world]).
   true.

?- findall(N, phrase(greeting, [hello, N]), Ns).
   Ns = [world,prolog].

?- phrase(digits(Ds), ['4','2'], Rest).
   Ds = ['4','2'], Rest = []
;  Ds = ['4'], Rest = ['2'].

?- phrase(ab, [a, b]).
   true.

?- phrase(ab, [c]).
   true.

?- phrase(ab, [a, c]).
   false.

?- phrase(first_only, [x, z]).
   false.

?- phrase([a, b], [a, b, c], R).
   R = [c].

?- phrase(([a] ; [b]), [b]).
   true.

% --- \+//1: succeeds without consuming input when its body cannot parse ---

?- phrase(not_b, [a]).
   true.

?- phrase(not_b, [b]).
   false.

?- phrase(\+ [a], [b], R).
   R = [b].

?- phrase(\+ [a], [a], R).
   false.

% --- call//N: calls a nonterminal built from a goal, compiling it first ---

?- phrase(call(never_called_before), [p]).
   true.

?- phrase(call(with_arg, q), [q]).
   true.

?- phrase(call(pair(a), b), L).
   L = [a,b].

?- phrase((call(with_arg, X), [z]), [y, z]).
   X = y.

?- catch(phrase(call(_), [a]), error(E, _), true).
   E = instantiation_error.

% --- pushback: Head, PB --> Body puts PB back on the input ---

?- phrase(peek(C), [x, y], R).
   C = x, R = [x,y].

?- phrase((peek(C), [C]), [x]).
   C = x.

?- findall(R, phrase(one_of, [a], R), Rs).
   Rs = [[b]].

?- findall(In-R, ( member(In, [[a], [c], [e]]), phrase(one_of, In, R) ), Ps).
   Ps = [[a]-[b],[c]-[],[e]-[d]].

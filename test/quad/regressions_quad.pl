% regression: for 0'c parsing and dcg

?- atom_chars('?- number_codes(33.0, [0''3|_L]).', _Cs), has_complete_clause(_Cs).
   true.

?- atom_chars('?- X = 0''\\n.', _Cs), has_complete_clause(_Cs).
   true.

?- atom_chars('?- X is 0''\\\\ + 1.', _Cs), has_complete_clause(_Cs).
   true.

?- atom_chars('?- foo([0''a, 0''b], X).', _Cs), has_complete_clause(_Cs).
   true.

?- atom_chars('?- X = 0''a, Y = ''real atom''.', _Cs), has_complete_clause(_Cs).
   true.

?- atom_chars('?- X = ''unterminated atom.', _Cs), \+ has_complete_clause(_Cs).
   true.

?- atom_chars('X is 0''a.', _Cs), strip_terminating_dot(_Cs, _Ys), atom_chars(Y, _Ys).
   Y = 'X is 0\'a'.

?- atom_chars('X is 0''a', _Cs), strip_terminating_dot(_Cs, _Ys), atom_chars(Y, _Ys).
   Y = 'X is 0\'a'.

?- atom_chars('X is 0''a. % a comment', _Cs), uncommented(_Cs, _Ys), atom_chars(Y, _Ys).
   Y = 'X is 0\'a. '.

% regression: an assertz'd rule holding an integer literal past the end of
% the query used to dangle once the temp pool it pointed into got compacted.

?- assertz((dyn_gt2(X) :- X > 2)), dyn_gt2(3).
   true.

?- dyn_gt2(5).
   true.

% regression: indexing must deref the goal's argument, or a spurious choice
% point steals the cut instead of being pruned by it.

cset(x).
cset(y).
cdispatch(X, matched) :- cset(X), !.
cdispatch(_, fallback).

?- findall(R, cdispatch(x, R), L).
   L = [matched].

% regression: builtin-created bindings (is/2) must get reclaimed in step
% with the recursive clause match, not accumulate until MAX_BINDINGS.

qcount(0) :- !.
qcount(N) :- N > 0, N1 is N - 1, qcount(N1).

?- qcount(5000).
   true.

% regression: a var bound deep inside a ->'s condition (via recursion in
% another predicate) must still be valid for goals after the -> returns.

qsplit([], []).
qsplit([_|T], Rest) :- qsplit(T, Rest).
qjoin([], B, B) :- !.
qjoin([H|A], B, [H|C]) :- qjoin(A, B, C).

?- ( qsplit([x], _Suffix) -> qjoin([], "hi", _Tmp), qjoin(_Tmp, _Suffix, R) ; true ).
   R = "hi".

% [file] shorthand for consult tests

% --- [] as a goal succeeds ---

?- [].
   true.

?- [], true.
   true.

?- ([] -> true ; false).
   true.

% --- [file] loads predicates ---

?- ['test/family.pl'].
   true.

?- parent(tom, bob).
   true.

?- father(tom, bob).
   true.

?- findall(C, parent(tom, C), L).
   L = [bob, liz].

% --- [file] is tracked by make/0 ---

?- \+ consulted([]).
   true.

% --- re-consulting the same file succeeds ---

?- ['test/family.pl'].
   true.

?- parent(tom, bob).
   true.

% --- [f1, f2] loads multiple files ---

?- ['test/family.pl', 'core.pl'].
   true.

?- parent(bob, ann).
   true.

?- append([1], [2], L).
   L = [1, 2].

% --- nonexistent file fails ---

?- ['no_such_file.pl'].
   false.

% --- list with bad element type errors ---

?- catch([42], error(type_error(atom, _), _), true).
   true.

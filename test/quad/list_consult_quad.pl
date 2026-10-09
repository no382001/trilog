% [file] shorthand for consult tests

% --- [] as a goal succeeds ---

?- [].
   true.

?- [], true.
   true.

?- ([] -> true ; false).
   true.

% --- [file] loads predicates ---

?- ['test/quad/files/genealogy.pl'].
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

?- ['test/quad/files/genealogy.pl'].
   true.

?- parent(tom, bob).
   true.

% --- [f1, f2] loads multiple files ---

?- ['test/quad/files/genealogy.pl', 'test/quad/files/colors.pl'].
   true.

?- parent(bob, ann).
   true.

?- findall(C, color(C), Cs).
   Cs = [red, green].

% --- nonexistent file fails ---

?- ['no_such_file.pl'].
   false.

% --- list with bad element type errors ---

?- catch([42], error(type_error(atom, _), _), true).
   true.

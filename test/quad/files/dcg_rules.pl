:- ensure_loaded(library(dcgs)).

greeting --> [hello], name.
name --> [world].
name --> [prolog].
digits([D|Ds]) --> digit(D), digits(Ds).
digits([D]) --> digit(D).
digit(D) --> [D], { member(D, ['0','1','2','3','4','5','6','7','8','9']) }.
ab --> ( [a] -> [b] ; [c] ).
first_only --> [x], !, [y].
first_only --> [x], [z].
not_b --> \+ [b], [_].
never_called_before --> [p].
with_arg(X) --> [X].
pair(X, Y) --> [X, Y].
peek(C), [C] --> [C].
one_of, [b] --> [a].
one_of --> [c].
one_of, [d] --> [e].

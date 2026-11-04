% library(error): must_be/2 and can_be/2. Expected answers are Scryer Prolog's.

?- must_be(integer, 1).
   true.

?- must_be(integer, a).
   error(type_error(integer, a)).

?- must_be(integer, _).
   error(instantiation_error).

?- must_be(_, a).
   error(instantiation_error).

?- must_be(atom, f(x)).
   error(type_error(atom, f(x))).

?- must_be(list, [a,b]).
   true.

?- must_be(list, [a|_]).
   error(instantiation_error).

?- L = [a|T], catch(must_be(list, L), _, true), var(T).
   L = [a|T].

?- must_be(list, [a|b]).
   error(type_error(list, [a|b])).

?- must_be(list, a).
   error(type_error(list, a)).

?- must_be(chars, [a,b]).
   true.

?- must_be(chars, [a,1]).
   error(type_error(character, 1)).

?- must_be(chars, [a,_]).
   error(instantiation_error).

?- must_be(chars, [a,bc]).
   error(type_error(character, bc)).

?- must_be(var, _).
   true.

?- must_be(var, a).
   error(uninstantiation_error(a)).

?- must_be(boolean, true).
   true.

?- must_be(boolean, x).
   error(type_error(boolean, x)).

?- must_be(character, ab).
   error(type_error(character, ab)).

?- must_be(not_less_than_zero, 0).
   true.

?- must_be(not_less_than_zero, -1).
   error(domain_error(not_less_than_zero, -1)).

?- must_be(not_less_than_zero, a).
   error(type_error(integer, a)).

?- catch(must_be(integer, a), error(_, C), true).
   C = must_be/2.

?- can_be(integer, _).
   true.

?- can_be(integer, 1).
   true.

?- can_be(integer, 1.0).
   error(type_error(integer, 1.0)).

?- catch(can_be(integer, 1.0), error(_, C), true).
   C = can_be/2.

?- can_be(list, [a|_]).
   true.

?- can_be(list, [a|b]).
   error(type_error(list, [a|b])).

?- can_be(list, a).
   error(type_error(list, a)).

?- can_be(chars, [a|_]).
   true.

?- can_be(chars, [_, b]).
   true.

?- can_be(chars, [a, 1]).
   error(type_error(character, 1)).

?- can_be(_, a).
   error(instantiation_error).

% A built-in that checks its arguments with must_be/2 names itself.

?- catch(sub_atom(1, _, _, _, _), error(E, C), true).
   E = type_error(atom, 1), C = sub_atom/5.

?- catch(atom_concat(a, 1, _), error(E, C), true).
   E = type_error(atom, 1), C = atom_concat/3.

?- catch(keysort([a-1], [b|c]), error(E, C), true).
   E = type_error(list, [b|c]), C = keysort/2.

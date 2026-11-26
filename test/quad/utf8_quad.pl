% Text is UTF-8: the text built-ins count characters, not bytes, and a
% character outside ASCII is a letter.

?- atom_length('Pécs', L).
   L = 4.

?- atom_codes('é', Cs).
   Cs = [233].

?- atom_codes(A, [80,233,99,115]).
   A = 'Pécs'.

?- atom_chars('Pécs', Cs).
   Cs = ['P',é,c,s].

?- char_code(C, 233).
   C = é.

?- char_code('中', C).
   C = 20013.

?- sub_atom('Pécs', 1, 1, A, S).
   A = 2, S = é.

?- sub_atom('árvíztűrő', B, 2, 0, S).
   B = 7, S = 'rő'.

?- atom_concat(X, 'cs', 'Pécs').
   X = 'Pé'.

?- X = 0'é.
   X = 233.

?- X = 0'𝄞.
   X = 119070.

?- atom_codes(A, [119070]), atom_length(A, L).
   A = '𝄞', L = 1.

?- X = "é", X = [C].
   X = "é", C = é.

?- X = é, atom(X).
   X = é.

?- X = 'кот', atom_length(X, L).
   X = кот, L = 3.

?- X = f(é, 'Pécs'), X = f(_, Y), atom(Y).
   X = f(é,'Pécs'), Y = 'Pécs'.

?- with_output_to(atom(A), writeq([é, 'é', 'É', 'a é'])).
   A = '[é,é,É,\'a é\']'.

?- atom_codes(A, [0'a, 0x2200]), atom_length(A, L).
   A = 'a∀', L = 2.

?- atom_length(X, 1), X = é.
   error(instantiation_error).

?- open('_build/utf8_quad.txt', write, _S), write(_S, 'Pé中'), nl(_S), close(_S), open('_build/utf8_quad.txt', read, _R), peek_char(_R, P), get_char(_R, A), peek_code(_R, Q), get_char(_R, B), get_char(_R, C), get_char(_R, D), close(_R).
   P = 'P', A = 'P', Q = 233, B = é, C = 中, D = '\n'.

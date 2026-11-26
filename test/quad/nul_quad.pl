% Code 0 is a character like any other

?- atom_length('\0\', N).
   N = 1.

?- atom_codes(A, [0'a, 0, 0'b]), atom_length(A, N), atom_codes(A, Cs).
   A = 'a\0\b', N = 3, Cs = [97,0,98].

?- char_code(C, 0), atom_chars(_A, [x, C, y]), sub_atom(_A, 1, 1, _, S).
   C = '\0\', S = '\0\'.

?- with_output_to(chars(Cs), writeq('\0\')).
   Cs = "'\\0\\'".

?- with_output_to(chars(Cs), writeq("\0\")).
   Cs = "['\\0\\']".

?- with_output_to(codes(Cs), write('a\0\b')).
   Cs = [97,0,98].

?- open('_build/nul_quad.tmp', write, _S), write(_S, 'a\0\b'), close(_S), open('_build/nul_quad.tmp', read, _R, [type(binary)]), get_byte(_R, B1), get_byte(_R, B2), get_byte(_R, B3), get_byte(_R, E), close(_R).
   B1 = 97, B2 = 0, B3 = 98, E = -1.

?- open('_build/nul_quad.tmp', read, _R), get_char(_R, C1), get_char(_R, C2), close(_R).
   C1 = a, C2 = '\0\'.

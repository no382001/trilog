% get_char/2, get_code/2, peek_char/2, peek_code/2 (ISO 8.12)
% test/quad/files/chars.txt holds "ab\n"; test/quad/files/empty.txt is empty.

% --- reading ---

?- open('test/quad/files/chars.txt', read, _S), get_char(_S, A), get_char(_S, B), get_char(_S, C), get_char(_S, D), close(_S).
   A = a, B = b, C = '\n', D = end_of_file.

?- open('test/quad/files/chars.txt', read, _S), get_code(_S, A), get_code(_S, B), get_code(_S, C), get_code(_S, D), close(_S).
   A = 97, B = 98, C = 10, D = -1.

?- open('test/quad/files/empty.txt', read, _S), get_char(_S, C), close(_S).
   C = end_of_file.

?- open('test/quad/files/empty.txt', read, _S), get_code(_S, C), close(_S).
   C = -1.

?- open('test/quad/files/chars.txt', read, _S), get_char(_S, b), close(_S).
   false.

?- open('test/quad/files/chars.txt', read, _S), get_char(_S, a), get_char(_S, C), close(_S).
   C = b.

% --- peeking does not consume ---

?- open('test/quad/files/chars.txt', read, _S), peek_char(_S, P), peek_char(_S, Q), get_char(_S, G), close(_S).
   P = a, Q = a, G = a.

?- open('test/quad/files/chars.txt', read, _S), peek_code(_S, P), get_code(_S, G), get_code(_S, H), close(_S).
   P = 97, G = 97, H = 98.

?- open('test/quad/files/chars.txt', read, _S), get_char(_S, _), get_char(_S, _), get_char(_S, _), peek_char(_S, P), get_char(_S, G), close(_S).
   P = end_of_file, G = end_of_file.

?- open('test/quad/files/empty.txt', read, _S), peek_code(_S, C), close(_S).
   C = -1.

% --- read_line_to_atom/2 shares the buffer with get_char/2 ---

?- open('test/quad/files/chars.txt', read, _S), get_char(_S, A), read_line_to_atom(_S, L), close(_S).
   A = a, L = b.

?- open('test/quad/files/chars.txt', read, _S), peek_char(_S, A), read_line_to_atom(_S, L), close(_S).
   A = a, L = ab.

% --- errors ---

?- get_char(_, C).
   error(instantiation_error).

?- get_char(foo, C).
   error(domain_error(stream_or_alias, foo)).

?- get_char(user_output, C).
   error(permission_error(input, stream, user_output)).

?- peek_char(user_error, C).
   error(permission_error(input, stream, user_error)).

?- open('test/quad/files/chars.txt', read, _S), get_char(_S, 1).
   error(type_error(in_character, 1)).

?- open('test/quad/files/chars.txt', read, _S), get_code(_S, a).
   error(type_error(integer, a)).

?- open('test/quad/files/chars.txt', read, _S), peek_code(_S, -2).
   error(representation_error(in_character_code)).

?- open('test/quad/files/chars.txt', read, _S), close(_S), get_char(_S, C).
   error(existence_error(stream, _)).

?- open('_build/char_io_quad.tmp', write, _S), get_char(_S, C).
   error(permission_error(input, stream, _)).

?- open('_build/char_io_quad.tmp', write, _S), peek_code(_S, C).
   error(permission_error(input, stream, _)).

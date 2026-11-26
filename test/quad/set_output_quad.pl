% current_output/1 and set_output/1 (ISO 8.11.2, 8.11.4).

?- current_output(S).
   S = user_output.

?- open('_build/set_output_quad.txt', write, _S), set_output(_S), write(f(x)), put_char('.'), nl, writeq('A b'), put_code(0'.), nl, write_term(h, []), write('.'), flush_output, set_output(user_output), close(_S), open('_build/set_output_quad.txt', read, _R), read(_R, T), read(_R, U), read(_R, V), close(_R).
   T = f(x), U = 'A b', V = h.

?- open('_build/set_output_quad.txt', write, _S), set_output(_S), current_output(_C), set_output(user_output), close(_S), _C == _S.
   true.

?- open('_build/set_output_quad.txt', write, _S, [alias(so_out)]), set_output(so_out), current_output(_C), set_output(user_output), close(_S), _C == _S.
   true.

?- open('_build/set_output_quad.txt', write, _S), set_output(_S), close(_S), current_output(C).
   C = user_output.

?- open('_build/set_output_quad.txt', write, _S), set_output(_S), with_output_to(atom(A), write(in)), current_output(_C), set_output(user_output), close(_S), _C == _S.
   A = in.

?- open('_build/set_output_quad.txt', write, _S), set_output(_S), catch(with_output_to(atom(_), throw(x)), x, true), current_output(_C), set_output(user_output), close(_S), _C == _S.
   true.

?- set_output(user_error), current_output(C), set_output(user_output).
   C = user_error.

?- open('_build/set_output_quad.bin', write, _S, [type(binary)]), set_output(_S), put_byte(104), catch(write(a), error(_E, _), true), set_output(user_output), close(_S), _E = permission_error(output, binary_stream, _B), _B == _S.
   true.

?- set_output(_).
   error(instantiation_error).

?- set_output(foo).
   error(existence_error(stream, foo)).

?- set_output(1).
   error(domain_error(stream_or_alias, 1)).

?- set_output(user_input).
   error(permission_error(output, stream, user_input)).

?- open('test/quad/files/terms.pl', read, _S), catch(set_output(_S), error(_E, _), true), close(_S), _E = permission_error(output, stream, _B), _B == _S.
   true.

?- catch(set_output(foo), error(_, C), true).
   C = set_output/1.

?- current_output(foo).
   error(domain_error(stream, foo)).

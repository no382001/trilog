% put_char/1,2, put_code/1,2, current_output/1, flush_output/0,1, close/2

% --- writing ---

?- with_output_to(chars(Cs), (put_char(a), put_char(user_output, b))).
   Cs = "ab".

?- with_output_to(chars(Cs), (put_code(0'a), put_code(user_output, 0'b))).
   Cs = "ab".

?- with_output_to(chars(Cs), put_char('\n')).
   Cs = "\n".

?- open('_build/char_out_quad.txt', write, _S), put_char(_S, x), put_code(_S, 0'y), close(_S), open('_build/char_out_quad.txt', read, _R), get_char(_R, A), get_char(_R, B), get_char(_R, C), close(_R).
   A = x, B = y, C = end_of_file.

% --- current_output ---

?- current_output(S).
   S = user_output.

?- current_output(user_output).
   true.

?- current_output(user_error).
   false.

?- current_output(foo).
   error(domain_error(stream, foo)).

% --- flushing and closing ---

?- flush_output.
   true.

?- flush_output(user_output), flush_output(user_error).
   true.

?- open('_build/char_out_quad.txt', write, _S), put_char(_S, z), flush_output(_S), close(_S, [force(true)]).
   true.

% --- errors ---

?- put_char(_).
   error(instantiation_error).

?- put_char(1).
   error(type_error(character, 1)).

?- put_char(ab).
   error(type_error(character, ab)).

?- put_char(_, a).
   error(instantiation_error).

?- put_char(foo, a).
   error(domain_error(stream_or_alias, foo)).

?- put_char(user_input, a).
   error(permission_error(output, stream, user_input)).

?- put_code(_).
   error(instantiation_error).

?- put_code(a).
   error(type_error(integer, a)).

?- put_code(-1).
   error(representation_error(character_code)).

?- put_code(user_input, 0'a).
   error(permission_error(output, stream, user_input)).

?- flush_output(_).
   error(instantiation_error).

?- flush_output(foo).
   error(domain_error(stream_or_alias, foo)).

?- close(user_output, foo).
   error(type_error(list, foo)).

?- close(user_output, [_]).
   error(instantiation_error).

?- close(user_output, [bad]).
   error(domain_error(close_option, bad)).

?- close(user_output, [force(maybe)]).
   error(domain_error(close_option, force(maybe))).

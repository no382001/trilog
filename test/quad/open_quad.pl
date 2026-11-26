% open/3 errors. Expected answers are Scryer Prolog's.

?- open(_, read, _).
   error(instantiation_error).

?- open(foo, _, _).
   error(instantiation_error).

?- open(foo, 1, _).
   error(type_error(atom, 1)).

?- open(foo, bogus, _).
   error(domain_error(io_mode, bogus)).

?- open(1, read, _).
   error(domain_error(source_sink, 1)).

?- open(f(x), read, _).
   error(domain_error(source_sink, f(x))).

?- open(foo, read, s).
   error(uninstantiation_error(s)).

?- open('/nonexistent/trilog/x', read, _).
   error(existence_error(source_sink, '/nonexistent/trilog/x')).

?- open('/nonexistent/trilog/x', write, _).
   error(existence_error(source_sink, '/nonexistent/trilog/x')).

?- catch(open('/nonexistent/trilog/x', read, _), error(_, C), true).
   C = open/3.

% open/4 options. Expected answers are Scryer Prolog's.

?- open('test/quad/files/chars.txt', read, _, _).
   error(instantiation_error).

?- open('test/quad/files/chars.txt', read, _, foo).
   error(type_error(list, foo)).

?- open('test/quad/files/chars.txt', read, _, [type(text)|foo]).
   error(type_error(list, [type(text)|foo])).

?- open('test/quad/files/chars.txt', read, _, [bogus]).
   error(domain_error(stream_option, bogus)).

?- open('test/quad/files/chars.txt', read, _, [type(foo)]).
   error(domain_error(stream_option, type(foo))).

?- open('test/quad/files/chars.txt', read, _, [alias(1)]).
   error(domain_error(stream_option, alias(1))).

?- open('test/quad/files/chars.txt', read, _, [eof_action(x)]).
   error(domain_error(stream_option, eof_action(x))).

?- open('test/quad/files/chars.txt', read, _, [reposition(x)]).
   error(domain_error(stream_option, reposition(x))).

?- open('test/quad/files/chars.txt', read, _, [alias(user_output)]).
   error(permission_error(open, source_sink, alias(user_output))).

?- open('test/quad/files/chars.txt', read, _S, [type(binary), eof_action(eof_code), reposition(true)]), close(_S).
   true.

?- open('test/quad/files/chars.txt', read, _, [alias(in)]), get_char(in, C), close(in).
   C = a.

?- open('test/quad/files/chars.txt', read, _, [alias(twice)]), open('test/quad/files/chars.txt', read, _, [alias(twice)]).
   error(permission_error(open, source_sink, alias(twice))).

?- open('test/quad/files/chars.txt', read, _, [alias(gone)]), close(gone), get_char(gone, _).
   error(existence_error(stream, gone)).

% eof_action, binary streams and stream_property/2. Expected answers are
% Scryer Prolog's; test/quad/files/chars.txt holds "ab\n".

?- open('test/quad/files/chars.txt', read, S, [eof_action(error)]), get_char(S, _), get_char(S, _), get_char(S, _), get_char(S, C), get_char(S, _).
   error(permission_error(input, past_end_of_stream, _)).

?- open('test/quad/files/chars.txt', read, _S, [eof_action(error)]), get_char(_S, _), get_char(_S, _), get_char(_S, _), peek_char(_S, P), get_char(_S, C), close(_S).
   P = end_of_file, C = end_of_file.

?- open('test/quad/files/chars.txt', read, _S), get_char(_S, _), get_char(_S, _), get_char(_S, _), get_char(_S, C), get_char(_S, D), close(_S).
   C = end_of_file, D = end_of_file.

?- open('test/quad/files/chars.txt', read, _S, [type(binary)]), get_byte(_S, A), peek_byte(_S, B), get_byte(_S, C), close(_S).
   A = 97, B = 98, C = 98.

?- open('test/quad/files/chars.txt', read, S, [type(binary)]), get_char(S, _).
   error(permission_error(input, binary_stream, _)).

?- open('test/quad/files/chars.txt', read, S), get_byte(S, _).
   error(permission_error(input, text_stream, _)).

?- open('test/quad/files/chars.txt', read, S, [type(binary)]), get_byte(S, a).
   error(type_error(in_byte, a)).

?- put_byte(_).
   error(instantiation_error).

?- put_byte(65).
   error(permission_error(output, text_stream, user_output)).

?- open('_build/open_quad.bin', write, S, [type(binary)]), put_byte(S, 256).
   error(type_error(byte, 256)).

?- open('_build/open_quad.bin', write, _W, [type(binary)]), put_byte(_W, 104), put_byte(_W, 105), close(_W), open('_build/open_quad.bin', read, _R, [type(binary)]), get_byte(_R, A), get_byte(_R, B), get_byte(_R, C), close(_R).
   A = 104, B = 105, C = -1.

?- open('_build/open_quad.bin', write, S, [type(binary)]), write(S, a).
   error(permission_error(output, binary_stream, _)).

?- open('test/quad/files/chars.txt', read, _S, [alias(p), type(binary), eof_action(error), reposition(true)]), findall(P, stream_property(_S, P), Ps), close(_S).
   Ps = [input,file_name('test/quad/files/chars.txt'),mode(read),alias(p),end_of_stream(not),eof_action(error),reposition(true),type(binary)].

?- findall(P, stream_property(user_input, P), Ps).
   Ps = [input,mode(read),alias(user_input),end_of_stream(not),eof_action(eof_code),reposition(false),type(text)].

?- stream_property(foo, _).
   error(existence_error(stream, foo)).

?- stream_property(_, bogus).
   error(domain_error(stream_property, bogus)).

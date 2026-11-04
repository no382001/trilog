% read/1,2, read_term/2,3, current_input/1 and set_input/1 (ISO).
% test/quad/files/terms.pl holds one term per test below, in order.

nth_read(N, T) :-
    open('test/quad/files/terms.pl', read, S),
    nth_read(N, S, T),
    close(S).

nth_read(1, S, T) :- !, read_or_error(S, T).
nth_read(N, S, T) :- read_or_error(S, _), N1 is N - 1, nth_read(N1, S, T).

read_or_error(S, T) :- catch(read(S, T), error(E, _), T = error(E)).

% --- reading term by term ---

?- nth_read(1, _T), _T = foo(_X, _Y, _Z), _X == _Z, _X \== _Y.
   true.

?- nth_read(2, T).
   T = 'a.b'.

?- nth_read(3, T).
   T = "x.y".

?- nth_read(4, T).
   T = 46.

?- nth_read(5, T).
   T = bar(1).

?- nth_read(6, _T), _T = [1,2|_V], var(_V).
   true.

?- nth_read(7, T).
   T = f(a,b).

?- nth_read(8, T).
   T = (p:-q).

?- nth_read(9, _T), _T = error(syntax_error(_)).
   true.

?- nth_read(10, T).
   T = baz.

?- nth_read(11, T).
   T = end_of_file.

?- nth_read(12, T).
   T = end_of_file.

% --- what is left after a term stays in the stream ---

?- open('test/quad/files/terms.pl', read, _S), read(_S, _), get_char(_S, C), close(_S).
   C = '\n'.

?- open('test/quad/files/terms.pl', read, _S), read(_S, _), read(_S, _), get_char(_S, C), close(_S).
   C = ' '.

% --- read_term/3 options ---

?- open('test/quad/files/terms.pl', read, _S), read_term(_S, _T, [variable_names(_VN), variables(_Vs), singletons(_Ss)]), close(_S), _T = foo(_X, _Y, _), _VN == ['X'=_X, 'Y'=_Y], _Vs == [_X, _Y], _Ss == ['Y'=_Y].
   true.

?- open('test/quad/files/terms.pl', read, _S), read_term(_S, _T, []), close(_S), _T = foo(_, _, _).
   true.

% --- the current input stream ---

?- current_input(S).
   S = user_input.

?- open('test/quad/files/terms.pl', read, _S), set_input(_S), read(_T), current_input(_C), set_input(user_input), close(_S), _C == _S, _T = foo(_, _, _).
   true.

?- open('test/quad/files/terms.pl', read, _S), set_input(_S), get_char(C), peek_char(P), set_input(user_input), close(_S).
   C = f, P = o.

?- open('test/quad/files/terms.pl', read, _S), set_input(_S), close(_S), current_input(C).
   C = user_input.

% --- errors ---

?- read(_, T).
   error(instantiation_error).

?- read(foo, T).
   error(domain_error(stream_or_alias, foo)).

?- read(user_output, T).
   error(permission_error(input, stream, user_output)).

?- open('_build/read_quad.tmp', write, _S), read(_S, T).
   error(permission_error(input, stream, _)).

?- open('test/quad/files/terms.pl', read, _S), close(_S), read(_S, T).
   error(existence_error(stream, _)).

?- read_term(user_input, T, [foo]).
   error(domain_error(read_option, foo)).

?- read_term(user_input, T, foo).
   error(type_error(list, foo)).

?- read_term(user_input, T, [_]).
   error(instantiation_error).

?- set_input(_).
   error(instantiation_error).

?- set_input(foo).
   error(domain_error(stream_or_alias, foo)).

?- set_input(user_output).
   error(permission_error(input, stream, user_output)).

?- current_input(foo).
   error(domain_error(stream, foo)).

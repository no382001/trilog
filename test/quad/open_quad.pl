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

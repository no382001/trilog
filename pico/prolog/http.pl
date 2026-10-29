:- ensure_loaded(library(dcgs)).

serve(Port) :-
    tcp_listen(Port),
    repeat,
    tcp_accept(Conn),
    open(Conn, read, In),
    open(Conn, write, Out),
    catch(handle(Conn, In, Out), E, (write(E), nl)),
    close(In),
    close(Out),
    fail.

handle(Conn, In, Out) :-
    read_line_to_atom(In, Line),
    skip_headers(In),
    (   atom(Line),
        atom_chars(Line, Cs),
        phrase(request(Path), Cs),
        phrase(route(Page), Path)
    ->  reply(Conn, Out, 200, Page)
    ;   reply(Conn, Out, 404, not_found)
    ).

skip_headers(In) :-
    read_line_to_atom(In, L),
    (   ( L == '' ; L == end_of_file )
    ->  true
    ;   skip_headers(In)
    ).

request(Path) --> "GET ", path(Path), " HTTP/", rest.

path([C|Cs]) --> [C], { C \== ' ' }, path(Cs).
path([]) --> [].

rest --> [].
rest --> [_], rest.

reply(Conn, Out, Status, Page) :-
    emit(Out, head(Status, Page)),
    body(Page, Conn, Out).

emit(Out, Body) :-
    forall(once(phrase(Body, Cs)), write_chars(Out, Cs)).

write_chars(_, []).
write_chars(Out, [C|Cs]) :-
    write(Out, C),
    write_chars(Out, Cs).

head(Status, Page) -->
    "HTTP/1.0 ", status(Status), crlf,
    "Content-Type: ", content_type(Page), "; charset=utf-8", crlf,
    "Connection: close", crlf,
    crlf.

status(200) --> "200 OK".
status(404) --> "404 Not Found".

content_type(Page) --> { html(Page) }, "text/html".
content_type(Page) --> { \+ html(Page) }, "text/plain".

crlf --> "\r\n".

atom(A) --> { atom_chars(A, Cs) }, Cs.

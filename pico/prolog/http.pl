:- ensure_loaded(library(dcgs)).

serve(Port) :-
    tcp_listen(Port),
    send_mail(httpd, listening, ("port ", int(Port), "\n")),
    repeat,
    tcp_accept(Conn),
    open(Conn, read, In),
    open(Conn, write, Out),
    (   catch(handle(Conn, In, Out), E, request_failed(E))
    ->  true
    ;   true
    ),
    close(In),
    close(Out),
    fail.

handle(Conn, In, Out) :-
    get_time_ms(T0),
    read_line_to_atom(In, Line),
    skip_headers(In),
    (   atom(Line),
        atom_chars(Line, Cs),
        phrase(request(Path), Cs),
        phrase(route(Page), Path)
    ->  Status = 200
    ;   Status = 404,
        Page = not_found
    ),
    reply(Conn, Out, Status, Page),
    get_time_ms(T1),
    Ms is T1 - T0,
    log_line(request_line(T0, Line, Status, Ms)).

request_line(T0, Line, Status, Ms) -->
    age(T0), " ", atom(Line), " ", int(Status), " ", int(Ms), "ms\n".

request_failed(E) :-
    mail_new(httpd, 'request failed'),
    open(mail, write, S),
    write(S, E),
    nl(S),
    close(S).

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

int(N) --> { number_chars(N, Cs) }, Cs.

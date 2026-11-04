:- module(http, [serve/1]).

:- use_module(library(dcgs)).
:- use_module(text).
:- use_module(mail).
:- use_module(routes).

serve(Port) :-
    tcp_listen(Port),
    mail:send(httpd, listening, ("port ", text:int(Port), "\n")),
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
    Line \== end_of_file,
    skip_headers(In),
    (   atom(Line),
        atom_chars(Line, Cs),
        phrase(request(Path), Cs),
        phrase(routes:route(Page), Path)
    ->  Status = 200
    ;   Status = 404,
        Page = not_found
    ),
    reply(Conn, Out, Status, Page),
    get_time_ms(T1),
    Ms is T1 - T0,
    mail:log(http:request_line(T0, Line, Status, Ms)).

request_line(T0, Line, Status, Ms) -->
    text:age(T0), " ", text:atom(Line), " ", text:int(Status), " ", text:int(Ms), "ms\n".

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

request(Path) --> "GET ", text:path(Path), " HTTP/", rest.

rest --> [].
rest --> [_], rest.

reply(Conn, Out, Status, Page) :-
    text:emit(Out, head(Status, Page)),
    routes:body(Page, Conn, Out).

head(Status, Page) -->
    "HTTP/1.0 ", status(Status), crlf,
    "Content-Type: ", content_type(Page), "; charset=utf-8", crlf,
    "Connection: close", crlf,
    crlf.

status(200) --> "200 OK".
status(404) --> "404 Not Found".

content_type(Page) --> { routes:html(Page) }, "text/html".
content_type(Page) --> { \+ routes:html(Page) }, "text/plain".

crlf --> "\r\n".

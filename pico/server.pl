:- ensure_loaded(library(dcgs)).
:- ensure_loaded(library(between)).

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

route(home) --> "/".
route(led(on)) --> "/led/on".
route(led(off)) --> "/led/off".
route(stats) --> "/stats".
route(fs) --> "/fs".
route(fs) --> "/fs/".
route(file(I)) --> "/fs/", path(P), { vfs_index(P, 0, I) }.

vfs_index(P, I0, I) :-
    vfs_file(I0, A),
    (   atom_chars(A, P)
    ->  I = I0
    ;   I1 is I0 + 1,
        vfs_index(P, I1, I)
    ).

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

html(home).
html(fs).
html(stats).

crlf --> [CR, '\n'], { char_code(CR, 13) }.

body(home, _, Out) :- !, home(Out).
body(fs, _, Out) :- !, tree(Out).
body(stats, _, Out) :- !, stats(Out).
body(file(I), Conn, _) :- !, vfs_send(Conn, I).
body(Page, _, Out) :- emit(Out, page(Page)).

home(Out) :-
    emit(Out, title),
    emit(Out, "<ul>\n"),
    forall(home_link(Href, Text), emit(Out, link(Href, Text))),
    emit(Out, "</ul>\n").

title -->
    "<h1>trilog ", version, "</h1>\n",
    "<p>running on ", board, "</p>\n".

version --> { trilog_version(V) }, V.

board -->
    { board_info(Board, Chip, MHz, FlashKB),
      atom_chars(Board, Bs),
      atom_chars(Chip, Cs),
      number_chars(MHz, Ms),
      number_chars(FlashKB, Fs) },
    Bs, " (", Cs, ", ", Ms, " MHz, ", Fs, " KB flash)".

home_link("/fs", "files").
home_link("/led/on", "LED on").
home_link("/led/off", "LED off").
home_link("/stats", "stats").

link(Href, Text) --> "<li><a href=\"", Href, "\">", Text, "</a>\n".

page(led(on)) --> { onboard_led(1) }, "LED on\n".
page(led(off)) --> { onboard_led(0) }, "LED off\n".
page(not_found) --> "not found\n".

stats(Out) :-
    emit(Out, title),
    emit(Out, "<table>\n"),
    forall(stat(Name, N, Unit), emit(Out, stat_row(Name, N, Unit))),
    emit(Out, "</table>\n").

stat("uptime", T, "ms") :- get_time_ms(T).
stat("malloc in use", N, "B") :- memory_usage(N, _, _, _, _).
stat("malloc arena", N, "B") :- memory_usage(_, N, _, _, _).
stat("heap region", N, "B") :- memory_usage(_, _, N, _, _).
stat("trilog live", N, "B") :- memory_usage(_, _, _, N, _).
stat("trilog peak", N, "B") :- memory_usage(_, _, _, _, N).
stat("prolog heap", N, "cells") :- prolog_usage(N, _, _, _, _, _).
stat("prolog heap capacity", N, "cells") :- prolog_usage(_, N, _, _, _, _).
stat("prolog heap peak", N, "cells") :- prolog_usage(_, _, N, _, _, _).
stat("atoms", N, "") :- prolog_usage(_, _, _, N, _, _).
stat("clauses", N, "") :- prolog_usage(_, _, _, _, N, _).
stat("arena", N, "B") :- prolog_usage(_, _, _, _, _, N).

stat_row(Name, N, Unit) -->
    { number_chars(N, Cs) },
    "<tr><td>", Name, "</td><td align=right>", Cs, "</td><td>", Unit,
    "</td></tr>\n".

tree(Out) :-
    vfs_count(0, N),
    Last is N - 1,
    findall(Segs-A, (between(0, Last, I), vfs_file(I, A), path_segments(A, Segs)), Es),
    msort(Es, Sorted),
    entries_nodes(Sorted, Nodes),
    emit(Out, title),
    emit(Out, "<pre>.\n"),
    emit_nodes(Out, Nodes, []),
    count(Nodes, 0, Dirs, 0, Files),
    emit(Out, tree_footer(Dirs, Files)).

vfs_count(I, N) :-
    (   vfs_file(I, _)
    ->  I1 is I + 1,
        vfs_count(I1, N)
    ;   N = I
    ).

path_segments(A, Segs) :-
    atom_chars(A, Cs),
    phrase(segments(Parts), Cs),
    maplist(atom_chars, Segs, Parts).

segments([S|Ss]) --> segment(S), "/", !, segments(Ss).
segments([S]) --> segment(S).

segment([C|Cs]) --> [C], { C \== '/' }, segment(Cs).
segment([]) --> [].

entries_nodes([], []).
entries_nodes([[Name]-A|Es], [file(Name, A)|Ns]) :-
    !,
    entries_nodes(Es, Ns).
entries_nodes([[Dir|Segs]-A|Es], [dir(Dir, Kids)|Ns]) :-
    same_dir(Es, Dir, Inside, Others),
    entries_nodes([Segs-A|Inside], Kids),
    entries_nodes(Others, Ns).

same_dir([[D, S|Ss]-A|Es], D, [[S|Ss]-A|In], Out) :-
    !,
    same_dir(Es, D, In, Out).
same_dir(Es, _, [], Es).

emit_nodes(_, [], _).
emit_nodes(Out, [N|Ns], Prefix) :-
    (   Ns == []
    ->  Branch = "└── ", Indent = "    "
    ;   Branch = "├── ", Indent = "│   "
    ),
    emit(Out, (Prefix, Branch, node(N))),
    (   N = dir(_, Kids)
    ->  append(Prefix, Indent, Prefix1),
        emit_nodes(Out, Kids, Prefix1)
    ;   true
    ),
    emit_nodes(Out, Ns, Prefix).

node(dir(Name, _)) --> atom(Name), "\n".
node(file(Name, A)) -->
    "<a href=\"/fs/", atom(A), "\">", atom(Name), "</a>", loaded(A), "\n".

atom(A) --> { atom_chars(A, Cs) }, Cs.

loaded(A) --> { loaded_file(A) }, !, "  (loaded)".
loaded(_) --> [].

loaded_file(A) :-
    atom_concat('embedded:', A, P),
    (   '$boot_file'(P)
    ;   '$consulted'(P, _)
    ),
    !.

count([], D, D, F, F).
count([file(_, _)|Ns], D0, D, F0, F) :-
    F1 is F0 + 1,
    count(Ns, D0, D, F1, F).
count([dir(_, Kids)|Ns], D0, D, F0, F) :-
    D1 is D0 + 1,
    count(Kids, D1, D2, F0, F1),
    count(Ns, D2, D, F1, F).

tree_footer(Dirs, Files) -->
    "\n", amount(Dirs, "directory", "directories"),
    ", ", amount(Files, "file", "files"), "\n</pre>\n".

amount(N, One, Many) -->
    { number_chars(N, Cs) },
    Cs, " ",
    (   { N =:= 1 }
    ->  One
    ;   Many
    ).

% Compiles the DCGs now, so the boot image holds them already compiled.
:- forall(member(G, [request(_), route(_), head(_, _), title, link(_, _),
                     page(_), stat_row(_, _, _), tree_footer(_, _),
                     segments(_), node(_)]),
          \+ catch(phrase(G, []), _, fail)).

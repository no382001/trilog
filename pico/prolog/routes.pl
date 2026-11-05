:- module(routes, [route//1,
                   html/1,
                   body/3
                  ]).

:- use_module(library(dcgs)).
:- use_module(text).
:- use_module(pages).
:- use_module(tree).

route(home) --> "/".
route(led(on)) --> "/led/on".
route(led(off)) --> "/led/off".
route(stats) --> "/stats".
route(mail) --> "/mail".
route(mail(Id)) -->
    "/mail/", text:path(P),
    { catch(number_chars(Id, P), _, fail), mail_info(Id, _, _, _, _) }.
route(log) --> "/log".
route(crash) --> "/crash".
route(fs) --> "/fs".
route(fs) --> "/fs/".
route(file(I)) --> "/fs/", text:path(P), { vfs_index(P, 0, I) }.

vfs_index(P, I0, I) :-
    vfs_file(I0, A),
    (   atom_chars(A, P)
    ->  I = I0
    ;   I1 is I0 + 1,
        vfs_index(P, I1, I)
    ).

html(home).
html(fs).
html(stats).
html(mail).

body(Page, Conn, Out) :-
    html(Page),
    !,
    pages:head(Out, Page),
    content(Page, Conn, Out),
    text:emit(Out, pages:foot).
body(mail(Id), Conn, _) :- !, mail_show(Conn, Id).
body(log, Conn, _) :- !, log_show(Conn).
body(crash, _, Out) :- !, ( last_crash(A) -> write(Out, A) ; write(Out, 'no crash recorded\n') ).
body(file(I), Conn, _) :- !, vfs_send(Conn, I).
body(Page, _, Out) :- text:emit(Out, page(Page)).

content(home, _, Out) :- pages:home(Out).
content(fs, _, Out) :- tree:tree(Out).
content(stats, _, Out) :- pages:stats(Out).
content(mail, Conn, Out) :- pages:mailbox(Conn, Out).

page(led(on)) --> { onboard_led(1) }, "LED on\n".
page(led(off)) --> { onboard_led(0) }, "LED off\n".
page(not_found) --> "not found\n".

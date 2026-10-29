:- ensure_loaded(library(dcgs)).

route(home) --> "/".
route(led(on)) --> "/led/on".
route(led(off)) --> "/led/off".
route(stats) --> "/stats".
route(mail) --> "/mail".
route(mail(Id)) -->
    "/mail/", path(P),
    { catch(number_chars(Id, P), _, fail), mail_info(Id, _, _, _, _) }.
route(log) --> "/log".
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

html(home).
html(fs).
html(stats).
html(mail).

body(home, _, Out) :- !, home(Out).
body(fs, _, Out) :- !, tree(Out).
body(stats, _, Out) :- !, stats(Out).
body(mail, Conn, Out) :- !, mailbox(Conn, Out).
body(mail(Id), Conn, _) :- !, mail_show(Conn, Id).
body(log, Conn, _) :- !, log_show(Conn).
body(file(I), Conn, _) :- !, vfs_send(Conn, I).
body(Page, _, Out) :- emit(Out, page(Page)).

page(led(on)) --> { onboard_led(1) }, "LED on\n".
page(led(off)) --> { onboard_led(0) }, "LED off\n".
page(not_found) --> "not found\n".

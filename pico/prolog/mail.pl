:- ensure_loaded(library(dcgs)).
:- ensure_loaded(library(between)).

send_mail(From, Subject, Body) :-
    mail_new(From, Subject),
    open(mail, write, S),
    emit(S, Body),
    close(S).

log_line(Body) :-
    open(log, append, S),
    emit(S, Body),
    close(S).

mail :-
    mail_ids(First, Last),
    (   Last < First
    ->  write('No mail.'), nl
    ;   forall(between(First, Last, Id), emit(user_output, mail_summary(Id)))
    ).

mail(Id) :-
    flush_output,
    mail_show(user, Id).

log :-
    flush_output,
    log_show(user).

mail_summary(Id) -->
    { mail_info(Id, From, Subject, Ms, New) },
    new_mark(New), " ", int(Id), "  ", atom(From), "  ", atom(Subject),
    "  ", age(Ms), "\n".

new_mark(1) --> "N".
new_mark(0) --> " ".

age(Ms) -->
    { S is Ms // 1000, D is Ms mod 1000 // 100 },
    "+", int(S), ".", int(D), "s".

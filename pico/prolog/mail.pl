:- module(mail, [send/3,
                 log/1,
                 mail/0,
                 mail/1,
                 log/0
                ]).

:- use_module(library(dcgs)).
:- use_module(library(between)).
:- use_module(text).

send(From, Subject, Body) :-
    mail_new(From, Subject),
    open(mail, write, S),
    text:emit(S, Body),
    close(S).

log(Body) :-
    open(log, append, S),
    text:emit(S, Body),
    close(S).

mail :-
    mail_ids(First, Last),
    (   Last < First
    ->  write('No mail.'), nl
    ;   forall(between(First, Last, Id), text:emit(user_output, mail_summary(Id)))
    ).

mail(Id) :-
    flush_output,
    mail_show(user, Id).

log :-
    flush_output,
    log_show(user).

mail_summary(Id) -->
    { mail_info(Id, From, Subject, Ms, New) },
    new_mark(New), " ", text:int(Id), "  ", text:atom(From), "  ", text:atom(Subject),
    "  ", text:age(Ms), "\n".

new_mark(1) --> "N".
new_mark(0) --> " ".

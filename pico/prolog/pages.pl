:- module(pages, [home/1,
                  stats/1,
                  mailbox/2,
                  head/2,
                  foot//0,
                  version//0,
                  board//0
                 ]).


:- use_module(library(dcgs)).
:- use_module(library(between)).
:- use_module(text).

home(Out) :-
    text:emit(Out, "<ul>\n"),
    forall(home_link(Href, Text), text:emit(Out, link(Href, Text))),
    text:emit(Out, "</ul>\n").

% !!! Each piece is emitted alone: one list for the whole head does not fit the heap.
% its too much for the pico apparently :(
head(Out, Page) :-
    text:emit(Out, "<!doctype html>\n<html>\n<head>\n<meta charset=\"UTF-8\" />\n"),
    text:emit(Out, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n"),
    text:emit(Out, ("<title>trilog", page_title(Page), "</title>\n")),
    text:emit(Out, "<style>body{max-width:100ex}</style>\n</head>\n<body>\n"),
    text:emit(Out, "<p><b>trilog</b> [ "),
    forall(nav_link(P, H, T), text:emit(Out, nav_item(P, H, T, Page))),
    text:emit(Out, " ]</p>\n").

page_title(home) --> !.
page_title(Page) --> { nav_link(Page, _, Text) }, !, " ~", Text.
page_title(_) --> [].

nav_item(P, H, T, Current) -->
    (   { P == home } -> [] ; ", " ),
    (   { P == Current } -> T ; "<a href=\"", H, "\">", T, "</a>" ).

nav_link(home, "/", "home").
nav_link(fs, "/fs", "files").
nav_link(stats, "/stats", "stats").
nav_link(mail, "/mail", "mail").
nav_link(log, "/log", "log").
nav_link(conformity, "/conformity", "conformity").

foot -->
    "<hr>\n<p>trilog ", version, " on ", board, "</p>\n</body>\n</html>\n".

version --> { trilog_version(V) }, V.

trilog_version(V) :-
    '$trilog_version'(A),
    atom_chars(A, V).

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
home_link("/mail", Text) :-
    mail_unread(N),
    phrase(("mail (", text:int(N), " new)"), Text).
home_link("/log", "request log").

link(Href, Text) --> "<li><a href=\"", Href, "\">", Text, "</a>\n".

stats(Out) :-
    text:emit(Out, "<pre>\n"),
    forall(chart_line(Line), text:emit(Out, Line)),
    text:emit(Out, "</pre>\n"),
    text:emit(Out, "<table>\n"),
    forall(stat(Name, N, Unit), text:emit(Out, stat_row(Name, N, Unit))),
    text:emit(Out, "</table>\n").

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

chart_line(heap_map).
chart_line(heap_legend).
chart_line("\n").
chart_line(gauge("prolog heap", Used, Cap, "cells")) :-
    prolog_usage(Used, Cap, _, _, _, _).
chart_line(gauge("  peak", Peak, Cap, "cells")) :-
    prolog_usage(_, Cap, Peak, _, _, _).
chart_line(gauge("flash", Used, Total, "KB")) :-
    flash_usage(UsedB, TotalB),
    Used is UsedB // 1024,
    Total is TotalB // 1024.

chart_width(48).

heap_map -->
    { memory_usage(Used, _, Region, Trilog, _),
      chart_width(W),
      T is Trilog * W // Region,
      O is (Used - Trilog) * W // Region,
      F is W - T - O },
    "heap ", kb(Region), "\n",
    "[", rep(T, '#'), rep(O, '+'), rep(F, '.'), "]\n".

heap_legend -->
    { memory_usage(Used, _, Region, Trilog, _),
      Other is Used - Trilog,
      Free is Region - Used },
    " # trilog ", kb(Trilog), "   + other ", kb(Other),
    "   . free ", kb(Free), "\n".

gauge(Label, Part, Whole, Unit) -->
    { chart_width(W),
      N is Part * W // Whole,
      M is W - N },
    pad(Label, 12), "[", rep(N, '#'), rep(M, '.'), "] ",
    text:int(Part), " / ", text:int(Whole), " ", Unit, "\n".

kb(B) -->
    { K is B // 1024, D is B mod 1024 * 10 // 1024 },
    text:int(K), ".", text:int(D), " KB".

pad(Text, Width) -->
    Text,
    { length(Text, L), P is max(0, Width - L) },
    rep(P, ' ').

rep(0, _) --> !.
rep(N, C) --> [C], { N1 is N - 1 }, rep(N1, C).

stat_row(Name, N, Unit) -->
    { number_chars(N, Cs) },
    "<tr><td>", Name, "</td><td align=right>", Cs, "</td><td>", Unit,
    "</td></tr>\n".

mailbox(Conn, Out) :-
    mail_ids(First, Last),
    (   Last < First
    ->  text:emit(Out, "<p>no mail\n")
    ;   forall(between(First, Last, Id), mail_entry(Conn, Out, Id))
    ).

mail_entry(Conn, Out, Id) :-
    text:emit(Out, mail_head(Id)),
    mail_show_html(Conn, Id),
    text:emit(Out, "</pre>\n").

mail_head(Id) -->
    { mail_info(Id, From, Subject, Ms, New) },
    "<hr>\n<p>", text:int(Id), ". ",
    strong(New, ("<a href=\"/mail/", text:int(Id), "\">", text:atom(Subject), "</a>")),
    " from ", text:atom(From), ", ", text:age(Ms), "</p>\n<pre>".

strong(1, Body) --> "<b>", Body, "</b>".
strong(0, Body) --> Body.

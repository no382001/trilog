:- ensure_loaded(library(dcgs)).

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
home_link("/mail", Text) :-
    mail_unread(N),
    phrase(("mail (", int(N), " new)"), Text).
home_link("/log", "request log").

link(Href, Text) --> "<li><a href=\"", Href, "\">", Text, "</a>\n".

stats(Out) :-
    emit(Out, title),
    emit(Out, "<pre>\n"),
    forall(chart_line(Line), emit(Out, Line)),
    emit(Out, "</pre>\n"),
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
    int(Part), " / ", int(Whole), " ", Unit, "\n".

kb(B) -->
    { K is B // 1024, D is B mod 1024 * 10 // 1024 },
    int(K), ".", int(D), " KB".

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
    emit(Out, title),
    mail_ids(First, Last),
    (   Last < First
    ->  emit(Out, "<p>no mail\n")
    ;   forall(between(First, Last, Id), mail_entry(Conn, Out, Id))
    ).

mail_entry(Conn, Out, Id) :-
    emit(Out, mail_head(Id)),
    mail_show_html(Conn, Id),
    emit(Out, "</pre>\n").

mail_head(Id) -->
    { mail_info(Id, From, Subject, Ms, New) },
    "<hr>\n<p>", int(Id), ". ",
    strong(New, ("<a href=\"/mail/", int(Id), "\">", atom(Subject), "</a>")),
    " from ", atom(From), ", ", age(Ms), "</p>\n<pre>".

strong(1, Body) --> "<b>", Body, "</b>".
strong(0, Body) --> Body.

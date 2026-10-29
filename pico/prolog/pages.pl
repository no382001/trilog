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

link(Href, Text) --> "<li><a href=\"", Href, "\">", Text, "</a>\n".

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

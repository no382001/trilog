:- ensure_loaded(library(dcgs)).
:- ensure_loaded(library(apply)).
:- ensure_loaded(library(between)).

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

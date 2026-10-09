%!  consulted(-Files) is det.
consulted(Files) :-
    findall(Path, '$consulted'(Path, _), Files).

%!  unconsult(+File) is semidet.
%   Fails if File is not loaded.
unconsult(File) :-
    ( atom(File), '$$source_path'(File, Path) -> true ; Path = File ),
    '$$retract'('$consulted'(Path, _)),
    '$$unload'(Path).

%!  make is det.
%   Reconsults every loaded file whose modification time changed. Needs the
%   platform's file_mtime/2; raises existence_error without it.
make :-
    forall(( '$consulted'(Path, Time0),
             file_mtime(Path, Time),
             Time \== Time0 ),
           consult(Path)).

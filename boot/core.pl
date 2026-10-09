% mi standard library.
% '$$name' = raw kernel primitive; 
% '$name' = private helper.

% --- dynamic predicate calls ---

% Calls to dynamic predicates iterate a snapshot of their clauses.
'$dyn_call'(G) :-
    '$$clause_candidates'(G, Cands),
    '$$choice_mark'(Mark),
    '$dyn_alts'(Cands, G, Mark).

'$dyn_alts'([H - Body|Cs], G, Mark) :- '$dyn_alt'(Cs, H, Body, G, Mark).

'$dyn_alt'([], H, Body, G, Mark) :- G = H, '$dyn_body'(Body, Mark, B), call(B).
'$dyn_alt'([_|_], H, Body, G, Mark) :- G = H, '$dyn_body'(Body, Mark, B), call(B).
'$dyn_alt'([C|Cs], _, _, G, Mark) :- '$dyn_alts'([C|Cs], G, Mark).

'$dyn_body'(V, _, call(V)) :- var(V), !.
'$dyn_body'(!, Mark, '$$cut_to'(Mark)) :- !.
'$dyn_body'((A, B), Mark, (A1, B1)) :- !, '$dyn_body'(A, Mark, A1), '$dyn_body'(B, Mark, B1).
'$dyn_body'((A ; B), Mark, (A1 ; B1)) :- !, '$dyn_body'(A, Mark, A1), '$dyn_body'(B, Mark, B1).
'$dyn_body'((C -> T), Mark, (C -> T1)) :- !, '$dyn_body'(T, Mark, T1).
'$dyn_body'(G, _, G).

% --- control ---

%!  ;/2, ->/2 is nondet.
%   Disjunction and if-then, including if-then-else.
';'('->'(If, Then), _) :- If, !, Then.
';'('->'(_, _), Else) :- !, Else.
';'(A, _) :- A.
';'(_, B) :- B.

'->'(Cond, Then) :- Cond, !, Then.

%!  call(:Goal), call(:Goal, +A1..+A3) is nondet.
%   call/1: fresh cut scope (native). call/2-4: extend via univ, then call/1.
call(G) :- G.

call(G, A1) :- G =.. L, append(L, [A1], L2), G2 =.. L2, call(G2).
call(G, A1, A2) :- G =.. L, append(L, [A1,A2], L2), G2 =.. L2, call(G2).
call(G, A1, A2, A3) :- G =.. L, append(L, [A1,A2,A3], L2), G2 =.. L2, call(G2).

%!  once(:Goal) is semidet.
once(G) :- call(G), !.

%!  \+(:Goal) is semidet.
'\\+'(G) :- call(G), !, fail.
'\\+'(_).

%!  forall(:Cond, :Action) is semidet.
forall(Cond, Action) :- \+ (Cond, \+ Action).

%!  halt is det.
halt :- halt(0).

:- dynamic('$consulted'/2).

%!  consult(+File) is semidet.
%   Loading a file again replaces the clauses its previous load added.
consult(File) :-
    (   var(File) -> throw(error(instantiation_error, consult/1))
    ;   atom(File) -> true
    ;   throw(error(type_error(atom, File), consult/1))
    ),
    '$$consult'(File, Path),
    '$file_time'(Path, Time),
    ( '$$retract'('$consulted'(Path, _)) -> true ; true ),
    '$$assertz'('$consulted'(Path, Time)).

'$file_time'(Path, Time) :-
    catch(file_mtime(Path, Time0), error(existence_error(procedure, _), _), fail),
    !,
    Time = Time0.
'$file_time'(_, unknown).

% library(Name) resolves next to the core: lib/Name.pl beside boot/.
:- '$$loading_file'(F), '$$assertz'('$boot_file'(F)).

%!  ensure_loaded(+File) is det.
%   File is a file name or library(Name); it is loaded unless already loaded.
ensure_loaded(Spec) :-
    '$with_context'('$ensure_loaded'(Spec), ensure_loaded/1).

%!  use_module(+File) is det.
%   There are no modules, so this is ensure_loaded/1.
use_module(Spec) :-
    '$with_context'('$ensure_loaded'(Spec), use_module/1).

'$ensure_loaded'(Spec) :-
    '$source_file'(Spec, File),
    (   '$$source_path'(File, Path) -> true
    ;   throw(error(existence_error(source_sink, Spec), _))
    ),
    ( '$consulted'(Path, _) -> true ; consult(Path) ).

'$source_file'(Spec, _) :- var(Spec), !, throw(error(instantiation_error, _)).
'$source_file'(library(Name), File) :-
    !,
    '$must_be_atom'(Name),
    '$boot_file'(Boot),
    '$directory'(Boot, Dir),
    atom_concat(Dir, '/../lib/', D1),
    atom_concat(D1, Name, D2),
    atom_concat(D2, '.pl', File).
'$source_file'(File, File) :- atom(File), !.
'$source_file'(Spec, _) :- throw(error(domain_error(source_sink, Spec), _)).

'$directory'(Path, Dir) :-
    (   sub_atom(Path, B, 1, A, '/'), \+ ( sub_atom(Path, _, 1, A1, '/'), A1 < A )
    ->  sub_atom(Path, 0, B, _, Dir)
    ;   Dir = '.'
    ).

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

%!  [], [+File|+Files] is det.
[].
[File|Files] :- consult(File), call(Files).

%!  repeat is nondet.
repeat.
repeat :- repeat.

% --- lists ---

% These load before the op/3 directives below, which need member/2.
:- consult('../lib/lists.pl').

% --- arithmetic ---

%!  between(+Low, +High, ?X) is nondet.
between(L, H, X) :- integer(X), !, X >= L, X =< H.
between(L, H, L) :- L =< H.
between(L, H, X) :- L < H, L1 is L + 1, between(L1, H, X).

%!  succ(?X, ?Y) is det.
succ(X, Y) :- integer(X), !, Y is X + 1.
succ(X, Y) :- integer(Y), X is Y - 1.

%!  plus(?A, ?B, ?C) is det.
plus(A, B, C) :- integer(A), integer(B), !, C is A + B.
plus(A, B, C) :- integer(A), integer(C), !, B is C - A.
plus(A, B, C) :- integer(B), integer(C), A is C - B.

% --- term comparison ---
% ==, \==, @<, @>, @=<, @>=, <, >, =<, >=, =:=, =\= are native

%!  compare(-Order, @A, @B) is det.
compare(O, A, B) :-
    (   var(O) -> true
    ;   atom(O) -> ( memberchk(O, [<, =, >]) -> true ; throw(error(domain_error(order, O), compare/3)) )
    ;   throw(error(type_error(atom, O), compare/3))
    ),
    ( A == B -> O = (=) ; A @< B -> O = (<) ; O = (>) ).

%!  \=(@A, @B) is semidet.
'\\='(X, Y) :- \+ X = Y.

% --- type checks ---
% var/1, atom/1, integer/1, float/1, compound/1 are native.

%!  nonvar(@Term) is semidet.
nonvar(X) :- \+ var(X).

%!  number(@Term) is semidet.
number(X) :- integer(X).
number(X) :- float(X).

%!  atomic(@Term) is semidet.
atomic(X) :- atom(X).
atomic(X) :- number(X).

%!  subsumes_term(@General, @Specific) is semidet.
subsumes_term(General, Specific) :-
    \+ \+ ( term_variables(Specific, SVars1),
            unify_with_occurs_check(General, Specific),
            term_variables(SVars1, SVars2),
            SVars1 == SVars2
          ).

%!  ground(@Term) is semidet.
ground(T) :- term_variables(T, []).

%!  callable(@Term) is semidet.
callable(X) :- atom(X).
callable(X) :- compound(X).

%!  boolean(@Term) is semidet.
boolean(true).
boolean(false).

%!  character(@Term) is semidet.
character(C) :- atom(C), atom_length(C, 1).

%!  must_be(+Type, @Term) is det.
must_be(Type, _) :-
    var(Type),
    !,
    throw(error(instantiation_error, must_be/2)).
must_be(var, Term) :-
    !,
    ( var(Term) -> true ; throw(error(uninstantiation_error(Term), must_be/2)) ).
must_be(list, Term) :- !, '$must_be_list'(Term).
must_be(not_less_than_zero, Term) :-
    !,
    '$must_be_type'(integer, Term),
    ( Term >= 0 -> true ; throw(error(domain_error(not_less_than_zero, Term), must_be/2)) ).
must_be(Type, Term) :- '$must_be_type'(Type, Term).

'$must_be_type'(_, Term) :-
    var(Term),
    !,
    throw(error(instantiation_error, must_be/2)).
'$must_be_type'(Type, Term) :- call(Type, Term), !.
'$must_be_type'(Type, Term) :- throw(error(type_error(Type, Term), must_be/2)).

'$must_be_list'([]) :- !.
'$must_be_list'([_|T]) :- !, '$must_be_list'(T).
'$must_be_list'(Term) :-
    ( var(Term) -> throw(error(instantiation_error, must_be/2))
    ; throw(error(type_error(list, Term), must_be/2))
    ).

%!  can_be(+Type, @Term) is semidet.
%   Like must_be/2, but an unbound Term passes without throwing.
can_be(Type, _) :-
    var(Type),
    !,
    throw(error(instantiation_error, can_be/2)).
can_be(_, Term) :- var(Term), !.
can_be(Type, Term) :- must_be(Type, Term).

% --- errors ---

%!  '$with_context'(:Goal, +PI) is nondet.
%   An error Goal raises without a context gets PI as its context.
'$with_context'(Goal, PI) :-
    catch(Goal, error(Formal, Context), '$rethrow'(Formal, Context, PI)).

'$rethrow'(Formal, Context, PI) :-
    ( var(Context) -> Context = PI ; true ),
    throw(error(Formal, Context)).

% --- sorting ---

%!  msort(+List, -Sorted) is det.
%   Stable merge sort: O(n log n)
msort(L, Sorted) :-
    '$with_context'('$msort'(L, Sorted), msort/2).

'$msort'(L, Sorted) :-
    '$sort_length'(L, L, 0, N),
    '$msort'(N, L, Sorted, _).

% The length of a proper list
'$sort_length'(T, _, _, _) :- var(T), !, throw(error(instantiation_error, _)).
'$sort_length'([], _, N, N) :- !.
'$sort_length'([_|T], L, N0, N) :- !, N1 is N0 + 1, '$sort_length'(T, L, N1, N).
'$sort_length'(_, L, _, _) :- throw(error(type_error(list, L), _)).

% Sorts the first N elements of L into Sorted, leaving the rest in Rest.
'$msort'(0, L, [], L) :- !.
'$msort'(1, [X|L], [X], L) :- !.
'$msort'(N, L, Sorted, Rest) :-
    A is N // 2,
    B is N - A,
    '$msort'(A, L, S1, L1),
    '$msort'(B, L1, S2, Rest),
    '$merge'(S1, S2, Sorted).

'$merge'([], L, L) :- !.
'$merge'(L, [], L) :- !.
'$merge'([X|Xs], [Y|Ys], [Z|Zs]) :-
    ( Y @< X -> Z = Y, '$merge'([X|Xs], Ys, Zs)
    ; Z = X, '$merge'(Xs, [Y|Ys], Zs)
    ).

%!  sort(+List, -Sorted) is det.
sort(L, Sorted) :- '$with_context'('$msort'(L, M), sort/2), '$dedup'(M, Sorted).
'$dedup'([], []).
'$dedup'([X], [X]) :- !.
'$dedup'([X,Y|T], R) :- X == Y, !, '$dedup'([Y|T], R).
'$dedup'([X,Y|T], [X|R]) :- '$dedup'([Y|T], R).

%!  keysort(+Pairs, -Sorted) is det.
keysort(Pairs, Sorted) :-
    '$with_context'('$keysort'(Pairs, Sorted), keysort/2).

'$keysort'(Pairs, Sorted) :-
    '$sort_length'(Pairs, Pairs, 0, _),
    '$keysort_index'(Pairs, 0, Indexed),
    '$can_be_list'(Sorted),
    '$msort'(Indexed, S),
    '$keysort_strip'(S, Sorted0),
    Sorted = Sorted0.

% Key-(Index-Value): the index keeps equal keys in their original order.
'$keysort_index'([], _, []).
'$keysort_index'([P|Ps], I, [K-(I-V)|Is]) :-
    (   var(P) -> throw(error(instantiation_error, _))
    ;   P = K-V -> true
    ;   throw(error(type_error(pair, P), _))
    ),
    I1 is I + 1,
    '$keysort_index'(Ps, I1, Is).

'$keysort_strip'([], []).
'$keysort_strip'([K-(_-V)|Is], [K-V|Ps]) :- '$keysort_strip'(Is, Ps).

'$can_be_list'(L) :-
    '$$skip_list'(L, _, T),
    ( var(T) -> true ; T == [] -> true ; throw(error(type_error(list, L), _)) ).

% --- database ---

%!  assertz/assert/asserta(+Clause), retract(+Clause).
%   Refuses static (consulted) predicates with permission_error unless declared dynamic/1;
%   asserting makes the predicate dynamic, so it still exists (and fails) once
%   its last clause is retracted.
assertz(Clause) :- '$with_context'(('$check_clause'(Clause), '$check_static'(Clause)), assertz/1), '$make_dynamic'(Clause), '$$assertz'(Clause).
assert(Clause) :- '$with_context'(('$check_clause'(Clause), '$check_static'(Clause)), assert/1), '$make_dynamic'(Clause), '$$assert'(Clause).
asserta(Clause) :- '$with_context'(('$check_clause'(Clause), '$check_static'(Clause)), asserta/1), '$make_dynamic'(Clause), '$$asserta'(Clause).
retract(Clause) :- '$with_context'(('$check_head'(Clause), '$check_static'(Clause)), retract/1), '$$retract'(Clause).

'$check_static'(Clause) :-
    '$clause_head'(Clause, Head),
    functor(Head, Name, Arity),
    ( '$$is_static'(Name, Arity)
    -> throw(error(permission_error(modify, static_procedure, Name/Arity), _))
    ;  true
    ).

% check:
% - unbound clause or head
% - non-callable head, or if a
% - body cannot be converted to a goal
'$check_clause'(Clause) :-
    '$check_head'(Clause),
    ( Clause = (_ :- Body), \+ '$body_goal'(Body)
    -> throw(error(type_error(callable, Body), _))
    ;  true
    ).

'$check_head'(Clause) :-
    ( var(Clause) -> throw(error(instantiation_error, _)) ; true ),
    '$clause_head'(Clause, Head),
    ( var(Head) -> throw(error(instantiation_error, _))
    ; callable(Head) -> true
    ; throw(error(type_error(callable, Head), _))
    ).

'$body_goal'(B) :- var(B), !.
'$body_goal'((A, B)) :- !, '$body_goal'(A), '$body_goal'(B).
'$body_goal'((A ; B)) :- !, '$body_goal'(A), '$body_goal'(B).
'$body_goal'((A -> B)) :- !, '$body_goal'(A), '$body_goal'(B).
'$body_goal'(B) :- callable(B).

'$make_dynamic'(Clause) :-
    '$clause_head'(Clause, Head),
    functor(Head, Name, Arity),
    dynamic(Name/Arity).

'$clause_head'((Head :- _), Head) :- !.
'$clause_head'(Head, Head).

%!  findall(+Template, :Goal, -List) is det.
%   FIXME: Goal throwing leaks this call's mark/items as orphaned facts.
findall(Template, Goal, List) :-
    '$next_id'(Id),
    '$$assertz'('$findall_mark'(Id)),
    (call(Goal), '$$assertz'('$findall_item'(Id, Template)), fail ; true),
    '$findall_collect'(Id, List).

'$id_counter'(-1).

'$next_id'(Id) :- '$$retract'('$id_counter'(N0)), Id is N0 + 1, '$$assertz'('$id_counter'(Id)).

'$findall_collect'(Id, List) :-
    '$$retract'('$findall_item'(Id, X)), !,
    List = [X|Rest],
    '$findall_collect'(Id, Rest).
'$findall_collect'(Id, []) :-
    '$$retract'('$findall_mark'(Id)).

%!  clause(?Head, ?Body) is nondet.
clause(Head, Body) :-
    '$$clause_candidates'(Head, Candidates),
    member(Head - Body, Candidates).

%!  term_variables(@Term, -Vars) is det.
%   Vars in first-occurrence order, each exactly once.
term_variables(Term, Vars) :-
    '$term_variables'(Term, [], Vs0),
    reverse(Vs0, Vars).

'$term_variables'(Term, Seen, Vars) :-
    var(Term),
    !,
    ( '$var_memberchk'(Term, Seen) -> Vars = Seen ; Vars = [Term|Seen] ).
'$term_variables'(Term, Seen, Vars) :-
    compound(Term),
    !,
    functor(Term, _, Arity),
    '$term_variables_args'(1, Arity, Term, Seen, Vars).
'$term_variables'(_, Seen, Seen).

'$term_variables_args'(I, N, _, Seen, Seen) :- I > N, !.
'$term_variables_args'(I, N, Term, Seen0, Vars) :-
    arg(I, Term, A),
    '$term_variables'(A, Seen0, Seen1),
    I1 is I + 1,
    '$term_variables_args'(I1, N, Term, Seen1, Vars).

'$var_memberchk'(V, [W|_]) :- V == W, !.
'$var_memberchk'(V, [_|T]) :- '$var_memberchk'(V, T).

%!  bagof(+Template, :Goal, -Bag) is semidet.
%   NOT ISO grouping: always merges into one bag
%   regardless of free vars/^. It's a findall/3 that fails on [].
bagof(Template, Goal0, Bag) :-
    '$bagof_strip'(Goal0, Goal),
    findall(Template, Goal, Bag),
    Bag \= [].

% nonvar first: an unbound Goal0 would otherwise unify with V^G0
% itself (binding fresh vars) and recurse on that fresh var forever.
'$bagof_strip'(Goal0, G) :-
    nonvar(Goal0),
    Goal0 = _ ^ G0,
    !,
    '$bagof_strip'(G0, G).
'$bagof_strip'(G, G).

%!  setof(+Template, :Goal, -Set) is semidet.
setof(Template, Goal, Set) :-
    bagof(Template, Goal, Bag),
    sort(Bag, Set).

% --- I/O ---
% put_code/1, get_code/1 are native.

%!  with_output_to(+Sink, :Goal) is semidet.
%   Sink is atom(-A) or codes(-Cs).
with_output_to(atom(A), Goal) :-
    '$$capture_start',
    % must pop the capture level even if Goal throws, or output stays silently swallowed after.
    ( catch(call(Goal), Ball, ('$$capture_stop'(_), throw(Ball)))
    -> '$$capture_stop'(A)
    ;  '$$capture_stop'(_), fail
    ).
with_output_to(codes(Cs), Goal) :- with_output_to(atom(A), Goal), '$$atom_codes'(A, Cs).
with_output_to(chars(Cs), Goal) :- with_output_to(atom(A), Goal), atom_chars(A, Cs).

'$stream_alias'(user_output, 0).
'$stream_alias'(user_error, 1).
'$resolve_stream'(S, N) :- '$stream_alias'(S, N), !.
'$resolve_stream'('$stream'(Id), '$stream'(Id)) :- !.
'$resolve_stream'(S, _) :- throw(error(domain_error(stream_or_alias, S), _)).

%!  write(@Term), write(+Stream, @Term) is det.
%   TODO: no operator-aware output.
write(T) :- '$$write_raw'(0, T, 2).
write(S, T) :-
    '$with_context'('$resolve_stream'(S, N), write/2),
    ( '$$write_raw'(N, T, 2) -> true ; throw(error(existence_error(stream, S), write/2)) ).

%!  writeq(@Term) is det.
%!  writeq(+Stream, @Term) is det.
writeq(T) :- '$$write_raw'(0, T, 3).
writeq(S, T) :-
    '$with_context'('$resolve_stream'(S, N), writeq/2),
    ( '$$write_raw'(N, T, 3) -> true ; throw(error(existence_error(stream, S), writeq/2)) ).

%!  write_term(@Term, +Options) is det.
%!  write_term(+Stream, @Term, +Options) is det.
%   Options: quoted(Bool), ignore_ops(Bool), numbervars(Bool).
%   TODO: ignore_ops(false) is accepted but not honored.
write_term(T, Opts) :-
    '$with_context'('$write_options'(Opts, Q), write_term/2),
    '$$write_raw'(0, T, Q).
write_term(S, T, Opts) :-
    '$with_context'(('$resolve_stream'(S, N), '$write_options'(Opts, Q)), write_term/3),
    ( '$$write_raw'(N, T, Q) -> true ; throw(error(existence_error(stream, S), write_term/3)) ).

'$write_options'(Opts, Q) :-
    '$options_list'(Opts),
    '$write_options'(Opts, 0, Q).
'$write_options'([], Q, Q).
'$write_options'([O|Os], Q0, Q) :-
    '$write_option'(O, Q0, Q1),
    '$write_options'(Os, Q1, Q).

'$write_option'(O, _, _) :- var(O), !, throw(error(instantiation_error, _)).
'$write_option'(quoted(B), F0, F) :- '$option_bool'(quoted(B), write_option, V), !, F is F0 \/ V.
'$write_option'(ignore_ops(B), F0, F) :- '$option_bool'(ignore_ops(B), write_option, V), !, F is F0 \/ V << 2.
'$write_option'(numbervars(B), F0, F) :- '$option_bool'(numbervars(B), write_option, V), !, F is F0 \/ V << 1.
'$write_option'(O, _, _) :- throw(error(domain_error(write_option, O), _)).

'$option_bool'(O, _, _) :- arg(1, O, B), var(B), !, throw(error(instantiation_error, _)).
'$option_bool'(O, _, 1) :- arg(1, O, true), !.
'$option_bool'(O, _, 0) :- arg(1, O, false), !.
'$option_bool'(O, Domain, _) :- throw(error(domain_error(Domain, O), _)).

'$options_list'(L) :- var(L), !, throw(error(instantiation_error, _)).
'$options_list'([]) :- !.
'$options_list'([_|L]) :- !, '$options_list'(L).
'$options_list'(L) :- throw(error(type_error(list, L), _)).

%!  numbervars(?Term, +Start, -End) is det.
%   Binds each variable of Term to '$VAR'(N), N counting up from Start.
numbervars(T, S, E) :-
    (   var(S) -> throw(error(instantiation_error, numbervars/3))
    ;   integer(S) -> true
    ;   throw(error(type_error(integer, S), numbervars/3))
    ),
    term_variables(T, Vs),
    '$numbervars'(Vs, S, E).
'$numbervars'([], N, N).
'$numbervars'(['$VAR'(N)|Vs], N, E) :-
    N1 is N + 1,
    '$numbervars'(Vs, N1, E).

%!  write_canonical(@Term) is det.
%!  write_canonical(+Stream, @Term) is det.
write_canonical(T) :- write_term(T, [quoted(true), ignore_ops(true)]).
write_canonical(S, T) :- write_term(S, T, [quoted(true), ignore_ops(true)]).

%!  write_term_to_chars(@Term, +Options, -Chars) is det.
write_term_to_chars(T, Opts, Cs) :-
    '$with_context'('$write_options'(Opts, _), write_term_to_chars/3),
    with_output_to(chars(Cs0), write_term(T, Opts)),
    Cs = Cs0.

%!  read_from_chars(+Chars, -Term) is det.
read_from_chars(Cs, T) :-
    '$with_context'('$read_term_from_chars'(Cs, T, []), read_from_chars/2).

%!  read_term_from_chars(+Chars, -Term, +Options) is det.
%   Options: variable_names(-Pairs), variables(-Vars).
%   Blank Chars read as end_of_file.
read_term_from_chars(Cs, T, Opts) :-
    '$with_context'('$read_term_from_chars'(Cs, T, Opts), read_term_from_chars/3).

'$read_term_from_chars'(Cs, T, Opts) :-
    '$options_list'(Opts),
    '$read_options_check'(Opts),
    '$chars_list'(Cs),
    (   '$blank_chars'(Cs)
    ->  T0 = end_of_file, Names = []
    ;   atom_chars(A, Cs),
        catch(atom_to_term(A, T0, Names), error(syntax_error(M), _),
              throw(error(syntax_error(M), _)))
    ),
    term_variables(T0, Vars),
    '$read_options_bind'(Opts, Names, Vars),
    T = T0.

'$read_options_check'([]).
'$read_options_check'([O|Os]) :-
    '$read_option_check'(O),
    '$read_options_check'(Os).
'$read_option_check'(O) :- var(O), !, throw(error(instantiation_error, _)).
'$read_option_check'(variable_names(_)) :- !.
'$read_option_check'(variables(_)) :- !.
'$read_option_check'(O) :- throw(error(domain_error(read_option, O), _)).

'$read_options_bind'([], _, _).
'$read_options_bind'([variable_names(Names)|Os], Names, Vars) :- !, '$read_options_bind'(Os, Names, Vars).
'$read_options_bind'([variables(Vars)|Os], Names, Vars) :- '$read_options_bind'(Os, Names, Vars).

'$chars_list'(L) :- '$text_list'(L, '$check_char').
'$check_char'(C) :- var(C), !, throw(error(instantiation_error, _)).
'$check_char'(C) :- character(C), !.
'$check_char'(C) :- throw(error(type_error(character, C), _)).

'$blank_chars'([]).
'$blank_chars'([C|Cs]) :- memberchk(C, [' ', '\t', '\n', '\r']), '$blank_chars'(Cs).

%!  nl is det.
%!  nl(+Stream) is det.
nl :- write('\n').
nl(S) :- write(S, '\n').

%!  writeln(@Term) is det.
%!  writeln(+Stream, @Term) is det.
writeln(T) :- write(T), nl.
writeln(S, T) :- write(S, T), nl(S).

%!  read_line_to_chars(+Stream, -Chars) is det.
read_line_to_chars(S, Cs) :-
    read_line_to_atom(S, A),
    ( A == end_of_file -> Cs = end_of_file ; atom_chars(A, Cs) ).

%!  put_chars(+Chars) is det.
put_chars(Cs) :- atom_chars(A, Cs), write(A).
put_chars(S, Cs) :- atom_chars(A, Cs), write(S, A).

%!  atom_codes(?Atom, ?Codes) is det.
atom_codes(A, Cs) :-
    '$with_context'('$atom_codes'(A, Cs), atom_codes/2).
'$atom_codes'(A, Cs) :-
    (   nonvar(A)
    ->  '$must_be_atom'(A),
        '$$atom_codes'(A, Cs0),
        Cs = Cs0
    ;   '$codes_list'(Cs),
        '$$atom_codes'(A, Cs)
    ).

%!  char_code(?Char, ?Code) is det.
char_code(Char, Code) :-
    '$with_context'('$char_code'(Char, Code), char_code/2).
'$char_code'(Char, Code) :-
    (   nonvar(Char)
    ->  ( character(Char) -> true ; throw(error(type_error(character, Char), _)) ),
        ( var(Code) -> true ; integer(Code) -> true ; throw(error(type_error(integer, Code), _)) ),
        '$$atom_codes'(Char, [Code])
    ;   var(Code)
    ->  throw(error(instantiation_error, _))
    ;   '$codes_list'([Code]),
        '$$atom_codes'(Char, [Code])
    ).

%!  get_char(-Char) is det.
get_char(Char) :- get_code(C), (C == -1 -> Char = end_of_file ; char_code(Char, C)).

%!  atom_length(+Atom, ?Length) is det.
atom_length(A, L) :-
    '$with_context'('$atom_length'(A, L), atom_length/2).
'$atom_length'(A, L) :-
    '$must_be_atom'(A),
    (   var(L) -> true
    ;   integer(L) -> ( L >= 0 -> true ; throw(error(domain_error(not_less_than_zero, L), _)) )
    ;   throw(error(type_error(integer, L), _))
    ),
    '$$atom_codes'(A, Cs),
    length(Cs, L).

%!  atom_concat(?Atom1, ?Atom2, ?Atom3) is nondet.
%   Nondet split falls out of append/3's own backtracking.
atom_concat(A, B, C) :-
    '$with_context'('$atom_concat_check'(A, B, C), atom_concat/3),
    '$atom_concat'(A, B, C).
'$atom_concat_check'(A, B, C) :-
    '$can_be_atom'(A),
    '$can_be_atom'(B),
    '$can_be_atom'(C),
    (   var(C), ( var(A) ; var(B) )
    ->  throw(error(instantiation_error, _))
    ;   true
    ).
'$atom_concat'(A, B, C) :-
    nonvar(A),
    nonvar(B),
    !,
    '$$atom_codes'(A, CA),
    '$$atom_codes'(B, CB),
    append(CA, CB, CC),
    '$$atom_codes'(C, CC).
'$atom_concat'(A, B, C) :-
    '$$atom_codes'(C, CC),
    append(CA, CB, CC),
    '$$atom_codes'(A, CA),
    '$$atom_codes'(B, CB).

%!  sub_atom(+Atom, ?Before, ?Length, ?After, ?Sub) is nondet.
sub_atom(Atom, Before, Length, After, Sub) :-
    '$with_context'('$sub_atom_check'(Atom, Before, Length, After, Sub), sub_atom/5),
    '$$atom_codes'(Atom, Codes),
    append(BC, RestC, Codes),
    length(BC, Before),
    append(SC, AC, RestC),
    length(SC, Length),
    length(AC, After),
    '$$atom_codes'(Sub, SC).
'$sub_atom_check'(Atom, Before, Length, After, Sub) :-
    '$must_be_atom'(Atom),
    '$can_be_atom'(Sub),
    '$can_be_integer'(Before),
    '$can_be_integer'(Length),
    '$can_be_integer'(After).

%!  atom_chars(?Atom, ?Chars) is det.
atom_chars(A, Chars) :-
    '$with_context'('$atom_chars'(A, Chars), atom_chars/2).
'$atom_chars'(A, Chars) :-
    (   nonvar(A)
    ->  '$must_be_atom'(A),
        '$$atom_codes'(A, Codes),
        '$codes_chars'(Codes, Chars)
    ;   '$chars_list'(Chars),
        '$codes_chars'(Codes, Chars),
        '$$atom_codes'(A, Codes)
    ).

%!  atom_number(?Atom, ?Number) is semidet.
atom_number(A, N) :-
    nonvar(A),
    !,
    '$$atom_codes'(A, C),
    '$$number_codes'(N, C).
atom_number(A, N) :-
    '$$number_codes'(N, C),
    '$$atom_codes'(A, C).

%!  number_codes(?Number, ?Codes) is det.
number_codes(N, Cs) :-
    '$with_context'('$number_codes'(N, Cs), number_codes/2).
'$number_codes'(N, Cs) :-
    (   nonvar(N)
    ->  '$must_be_number'(N),
        '$text_list_bound'(Cs, '$check_code'),
        (   '$complete_list'(Cs)
        ->  '$parse_number'(Cs, N)
        ;   '$$number_codes'(N, Cs0),
            Cs = Cs0
        )
    ;   '$codes_list'(Cs),
        '$parse_number'(Cs, N)
    ).

%!  number_chars(?Number, ?Chars) is det.
number_chars(N, Chars) :-
    '$with_context'('$number_chars'(N, Chars), number_chars/2).
'$number_chars'(N, Chars) :-
    (   nonvar(N)
    ->  '$must_be_number'(N),
        '$text_list_bound'(Chars, '$check_char'),
        (   '$complete_list'(Chars)
        ->  '$codes_chars'(Codes, Chars),
            '$parse_number'(Codes, N)
        ;   '$$number_codes'(N, Codes),
            '$codes_chars'(Codes, Chars)
        )
    ;   '$chars_list'(Chars),
        '$codes_chars'(Codes, Chars),
        '$parse_number'(Codes, N)
    ).

'$parse_number'(Codes, N) :-
    (   '$$number_codes'(N0, Codes)
    ->  N = N0
    ;   throw(error(syntax_error(illegal_number), _))
    ).

'$codes_chars'([], []).
'$codes_chars'([Code|Codes], [Char|Chars]) :-
    '$$atom_codes'(Char, [Code]),
    '$codes_chars'(Codes, Chars).

'$must_be_atom'(A) :- var(A), !, throw(error(instantiation_error, _)).
'$must_be_atom'(A) :- atom(A), !.
'$must_be_atom'(A) :- throw(error(type_error(atom, A), _)).

'$must_be_number'(N) :- number(N), !.
'$must_be_number'(N) :- throw(error(type_error(number, N), _)).

'$can_be_atom'(A) :- ( var(A) ; atom(A) ), !.
'$can_be_atom'(A) :- throw(error(type_error(atom, A), _)).

'$can_be_integer'(I) :- ( var(I) ; integer(I) ), !.
'$can_be_integer'(I) :- throw(error(type_error(integer, I), _)).

'$codes_list'(L) :- '$text_list'(L, '$check_code').
'$check_code'(C) :- var(C), !, throw(error(instantiation_error, _)).
'$check_code'(C) :- integer(C), C >= 0, C =< 1114111, !.
'$check_code'(C) :- throw(error(representation_error(character_code), _)).

% Walks the elements before the tail first, so a bad element in a partial list
% is reported before the missing tail.
'$text_list'(L, Check) :-
    '$$skip_list'(L, _, Tail),
    (   var(Tail) -> true
    ;   Tail == [] -> true
    ;   throw(error(type_error(list, L), _))
    ),
    '$text_elements'(L, Check),
    ( var(Tail) -> throw(error(instantiation_error, _)) ; true ).
'$text_list_bound'(L, Check) :-
    '$$skip_list'(L, _, Tail),
    (   var(Tail) -> true
    ;   Tail == [] -> true
    ;   throw(error(type_error(list, L), _))
    ),
    '$text_elements'(L, '$check_bound'(Check)).
'$complete_list'(L) :- '$$skip_list'(L, _, T), T == [], ground(L).

'$check_bound'(_, C) :- var(C), !.
'$check_bound'(Check, C) :- call(Check, C).

'$text_elements'(L, _) :- var(L), !.
'$text_elements'([], _) :- !.
'$text_elements'([C|L], Check) :-
    call(Check, C),
    '$text_elements'(L, Check).

%!  retractall(+Head) is det.
%   an unknown predicate is created as dynamic.
retractall(Head) :-
    '$with_context'('$check_static'(Head), retractall/1),
    '$make_dynamic'(Head),
    '$retractall'(Head).

'$retractall'(Head) :-
    ( copy_term(Head, Fresh), '$$retract'(Fresh) -> '$retractall'(Head) ; true ).

%!  abolish(+Name/Arity) is det.
%   the predicate stops existing
abolish(PI) :-
    ( var(PI) -> throw(error(instantiation_error, abolish/1)) ; true ),
    ( PI = Name/Arity -> true ; throw(error(type_error(predicate_indicator, PI), abolish/1)) ),
    ( ( var(Name) ; var(Arity) ) -> throw(error(instantiation_error, abolish/1)) ; true ),
    ( atom(Name) -> true ; throw(error(type_error(atom, Name), abolish/1)) ),
    ( integer(Arity) -> true ; throw(error(type_error(integer, Arity), abolish/1)) ),
    ( Arity >= 0 -> true ; throw(error(domain_error(not_less_than_zero, Arity), abolish/1)) ),
    functor(Head, Name, Arity),
    retractall(Head),
    '$$undynamic'(Name, Arity).

% --- operators ---

% Queried before the first op/3 call has asserted anything - without
% this, that first query throws existence_error instead of just failing.
:- dynamic('$$op'/3).

%!  op(+Priority, +Type, +Name) is det.
%   Priority 0 removes Name's operator in Type's class instead of
%   adding one - `-` can be both a 500 yfx and a 200 fy at once.
op(Priority, Type, Name) :-
    ( integer(Priority) -> true
    ; var(Priority) -> throw(error(instantiation_error, op/3))
    ; throw(error(type_error(integer, Priority), op/3))
    ),
    ( Priority >= 0, Priority =< 1200 -> true
    ; throw(error(domain_error(operator_priority, Priority), op/3))
    ),
    ( var(Type) -> throw(error(instantiation_error, op/3)) ; true ),
    '$op_class'(Type, Class),
    '$op_names'(Name, Names),
    forall(member(N, Names), '$op_one'(Priority, Type, Class, N)).

'$op_names'(Name, _) :- var(Name), !, throw(error(instantiation_error, op/3)).
'$op_names'(Name, [Name]) :- atom(Name), !.
'$op_names'(Names, Names) :-
    '$$skip_list'(Names, _, T),
    (   var(T) -> throw(error(instantiation_error, op/3))
    ;   T == [] -> true
    ;   throw(error(type_error(list, Names), op/3))
    ),
    forall(member(N, Names),
           (   var(N) -> throw(error(instantiation_error, op/3))
           ;   atom(N) -> true
           ;   throw(error(type_error(atom, N), op/3))
           )).

'$op_class'(xfx, infix).
'$op_class'(xfy, infix).
'$op_class'(yfx, infix).
'$op_class'(fy, prefix).
'$op_class'(fx, prefix).
'$op_class'(xf, postfix).
'$op_class'(yf, postfix).
'$op_class'(Type, _) :-
    \+ '$op_class_known'(Type),
    throw(error(domain_error(operator_specifier, Type), op/3)).

'$op_class_known'(xfx). '$op_class_known'(xfy). '$op_class_known'(yfx).
'$op_class_known'(fy).  '$op_class_known'(fx).
'$op_class_known'(xf).  '$op_class_known'(yf).

'$op_one'(_, _, _, ',') :-
    !,
    throw(error(permission_error(modify, operator, ','), op/3)).
'$op_one'(_, _, _, Name) :-
    ( Name == [] ; Name == {} ),
    !,
    throw(error(permission_error(create, operator, Name), op/3)).
'$op_one'(Priority, _, Class, '|') :-
    \+ ( Class == infix, ( Priority =:= 0 ; Priority >= 1001 ) ),
    !,
    throw(error(permission_error(create, operator, '|'), op/3)).
'$op_one'(Priority, _, Class, Name) :-
    Priority > 0,
    '$op_clash'(Class, Other),
    '$$op'(_, OldT, Name),
    '$op_class'(OldT, Other),
    !,
    throw(error(permission_error(create, operator, Name), op/3)).
'$op_one'(Priority, Type, Class, Name) :-
    '$op_unset'(Class, Name),
    ( Priority =:= 0 -> true ; '$$assertz'('$$op'(Priority, Type, Name)) ).

% Drop any existing operator sharing Name's class first
'$op_unset'(Class, Name) :-
    ( '$$op'(OldP, OldT, Name), '$op_class'(OldT, Class) ->
        '$$retract'('$$op'(OldP, OldT, Name)),
        '$op_unset'(Class, Name)
    ; true
    ).

% An infix and a postfix operator cannot share a name.
'$op_clash'(infix, postfix).
'$op_clash'(postfix, infix).

%!  current_op(?Priority, ?Type, ?Name) is nondet.
current_op(P, T, N) :- '$$op'(P, T, N).


% --- prolog flags ---

%!  current_prolog_flag(?Flag, ?Value) is nondet.
%   no set_prolog_flag/2 currently
current_prolog_flag(Flag, Value) :-
    '$$prolog_flags'(Flags),
    (   var(Flag)
    ->  member(Flag-Value, Flags)
    ;   memberchk(Flag-V, Flags)
    ->  Value = V
    ;   atom(Flag)
    ->  throw(error(domain_error(prolog_flag, Flag), current_prolog_flag/2))
    ;   throw(error(type_error(atom, Flag), current_prolog_flag/2))
    ).

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
%   The solver runs both natively. These clauses only run for an unbound left
%   side of ;/2, and keep both predicates defined and static.
';'('->'(If, Then), _) :- If, !, Then.
';'('->'(_, _), Else) :- !, Else.
';'(A, _) :- A.
';'(_, B) :- B.

'->'(Cond, Then) :- Cond, !, Then.

%!  call(:Goal), call(:Goal, +A1..+A7) is nondet.
%   call/1: fresh cut scope (native). call/2-8: extend via univ, then call/1.
call(G) :- G.

call(M:G, A1) :- !, '$extend'(G, [A1], G2), call(M:G2).
call(G, A1) :- G =.. L, append(L, [A1], L2), G2 =.. L2, call(G2).
call(M:G, A1, A2) :- !, '$extend'(G, [A1,A2], G2), call(M:G2).
call(G, A1, A2) :- G =.. L, append(L, [A1,A2], L2), G2 =.. L2, call(G2).
call(M:G, A1, A2, A3) :- !, '$extend'(G, [A1,A2,A3], G2), call(M:G2).
call(G, A1, A2, A3) :- G =.. L, append(L, [A1,A2,A3], L2), G2 =.. L2, call(G2).
call(M:G, A1, A2, A3, A4) :- !, '$extend'(G, [A1,A2,A3,A4], G2), call(M:G2).
call(G, A1, A2, A3, A4) :- G =.. L, append(L, [A1,A2,A3,A4], L2), G2 =.. L2, call(G2).
call(M:G, A1, A2, A3, A4, A5) :- !, '$extend'(G, [A1,A2,A3,A4,A5], G2), call(M:G2).
call(G, A1, A2, A3, A4, A5) :- G =.. L, append(L, [A1,A2,A3,A4,A5], L2), G2 =.. L2, call(G2).
call(M:G, A1, A2, A3, A4, A5, A6) :- !, '$extend'(G, [A1,A2,A3,A4,A5,A6], G2), call(M:G2).
call(G, A1, A2, A3, A4, A5, A6) :- G =.. L, append(L, [A1,A2,A3,A4,A5,A6], L2), G2 =.. L2, call(G2).
call(M:G, A1, A2, A3, A4, A5, A6, A7) :- !, '$extend'(G, [A1,A2,A3,A4,A5,A6,A7], G2), call(M:G2).
call(G, A1, A2, A3, A4, A5, A6, A7) :- G =.. L, append(L, [A1,A2,A3,A4,A5,A6,A7], L2), G2 =.. L2, call(G2).

'$extend'(G, As, G2) :- G =.. L, append(L, As, L2), G2 =.. L2.

%!  once(:Goal) is semidet.
once(G) :- call(G), !.

%!  \+(:Goal) is semidet.
'\\+'(G) :- call(G), !, fail.
'\\+'(_).

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
    '$with_extension'(File, File1),
    '$$consult'(File1, Path),
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

%   A file whose first directive is '$builtin_file' holds built-ins:
%   current_predicate/1 will not list them.
'$builtin_file' :- '$$loading_file'(F), '$$assertz'('$builtin_file'(F)).
:- '$builtin_file'.

%!  ensure_loaded(+File) is det.
%   File is a file name or library(Name); it is loaded unless already loaded.
ensure_loaded(Spec) :-
    '$with_context'('$ensure_loaded'(Spec), ensure_loaded/1).

%!  use_module(+File) is det.
%!  use_module(+File, +Imports) is det.
%   Loads File like ensure_loaded/1. A module's exports are visible
%   everywhere, so Imports, a list of Name/Arity and Name//Arity, is only
%   checked for its form.
use_module(Spec) :-
    '$with_context'('$ensure_loaded'(Spec), use_module/1).
use_module(Spec, Imports) :-
    '$with_context'(('$module_pis'(Imports), '$ensure_loaded'(Spec)), use_module/2).

%!  module(+Module, +Exports) is det.
%   As a directive, makes the file being loaded Module. Its predicates not in
%   Exports, a list of Name/Arity and Name//Arity, are private to it.
module(M, Exports) :-
    '$with_context'('$module'(M, Exports), module/2).

'$module'(_, _) :-
    \+ '$$loading_file'(_),
    !,
    throw(error(existence_error(procedure, module/2), module/2)).
'$module'(M, _) :- \+ atom(M), !, throw(error(type_error(atom, M), load/1)).
'$module'(M, Exports) :-
    (   '$is_pi_list'(Exports) -> true
    ;   throw(error(syntax_error(invalid_module_declaration), load/1))
    ),
    '$$module'(M, Exports),
    ( '$known_module'(M) -> true ; '$$assertz'('$known_module'(M)) ).

:- dynamic('$known_module'/1).

'$module_pis'(L) :-
    (   '$is_pi_list'(L) -> true
    ;   throw(error(syntax_error(invalid_module_declaration), _))
    ).

'$is_pi_list'(L) :- var(L), !, fail.
'$is_pi_list'([]).
'$is_pi_list'([PI|PIs]) :- nonvar(PI), '$is_pi'(PI), '$is_pi_list'(PIs).

'$is_pi'(N/A) :- atom(N), integer(A), A >= 0.
'$is_pi'(N//A) :- atom(N), integer(A), A >= 0.

%!  meta_predicate(+Heads) is det.
%   Heads is a head, a list of heads, or a conjunction of them. Each
%   argument is 0..9 (a goal called with that many more arguments), ^ (a
%   goal under V^), // (a DCG body), or one of : ? + - * (not a goal).
%   In a module, such arguments are taken as the module's goals.
%   Like module/2 it is only a directive, and a bad declaration fails the
%   load with syntax_error(invalid_meta_predicate_decl).
meta_predicate(Heads) :-
    (   \+ '$$loading_file'(_)
    ->  throw(error(existence_error(procedure, meta_predicate/1),
                    meta_predicate/1))
    ;   '$meta_decls'(Heads, Decls)
    ->  '$meta_assert'(Decls)
    ;   throw(error(syntax_error(invalid_meta_predicate_decl), load/1))
    ).

'$meta_decls'(Heads, Decls) :- '$meta_decls'(Heads, Decls, []).

'$meta_decls'(V, _, _) :- var(V), !, fail.
'$meta_decls'((A, B), Ds0, Ds) :- !, '$meta_decls'(A, Ds0, Ds1), '$meta_decls'(B, Ds1, Ds).
'$meta_decls'([], Ds, Ds) :- !.
'$meta_decls'([H|T], Ds0, Ds) :- !, '$meta_decls'(H, Ds0, Ds1), '$meta_decls'(T, Ds1, Ds).
'$meta_decls'(_:H, Ds0, Ds) :- !, '$meta_decls'(H, Ds0, Ds).
'$meta_decls'(H, [N/A-Specs|Ds], Ds) :-
    callable(H),
    functor(H, N, A),
    H =.. [_|Specs],
    '$meta_specs'(Specs).

'$meta_specs'([]).
'$meta_specs'([S|Ss]) :-
    nonvar(S),
    (   integer(S) -> S >= 0, S =< 9
    ;   atom(S), '$meta_spec_atom'(S)
    ),
    '$meta_specs'(Ss).

'$meta_spec_atom'(':').
'$meta_spec_atom'('^').
'$meta_spec_atom'('//').
'$meta_spec_atom'('?').
'$meta_spec_atom'('+').
'$meta_spec_atom'('-').
'$meta_spec_atom'('*').

'$meta_assert'([]).
'$meta_assert'([N/A-Specs|Ds]) :-
    ( '$$retract'('$meta_spec'(N, A, _)) -> true ; true ),
    '$$assertz'('$meta_spec'(N, A, Specs)),
    '$meta_assert'(Ds).

:- dynamic('$meta_spec'/3).
'$meta_spec'(',', 2, [0, 0]).
'$meta_spec'(';', 2, [0, 0]).
'$meta_spec'('->', 2, [0, 0]).
'$meta_spec'('*->', 2, [0, 0]).
'$meta_spec'('\\+', 1, [0]).
'$meta_spec'(call, 1, [0]).
'$meta_spec'(call, 2, [1, ?]).
'$meta_spec'(call, 3, [2, ?, ?]).
'$meta_spec'(call, 4, [3, ?, ?, ?]).
'$meta_spec'(call, 5, [4, ?, ?, ?, ?]).
'$meta_spec'(call, 6, [5, ?, ?, ?, ?, ?]).
'$meta_spec'(call, 7, [6, ?, ?, ?, ?, ?, ?]).
'$meta_spec'(call, 8, [7, ?, ?, ?, ?, ?, ?, ?]).
'$meta_spec'(once, 1, [0]).
'$meta_spec'(catch, 3, [0, ?, 0]).
'$meta_spec'(findall, 3, [?, 0, '-']).
'$meta_spec'(bagof, 3, [?, '^', '-']).
'$meta_spec'(setof, 3, [?, '^', '-']).
'$meta_spec'(assert, 1, [:]).
'$meta_spec'(asserta, 1, [:]).
'$meta_spec'(assertz, 1, [:]).
'$meta_spec'(retract, 1, [:]).
'$meta_spec'(retractall, 1, [:]).
'$meta_spec'(clause, 2, [:, ?]).

%!  :(+Module, :Goal) is nondet.
%   Calls Goal, using Module's private predicate of that name if it has one.
M:G :-
    (   var(M) -> throw(error(instantiation_error, (:)/2))
    ;   \+ atom(M) -> throw(error(type_error(atom, M), (:)/2))
    ;   M == user -> call(G)
    ;   '$known_module'(M) -> '$$qualify'(M, G, G1), call(G1)
    ;   callable(G) ->
        functor(G, N, A),
        throw(error(existence_error(procedure, M:N/A), (:)/2))
    ;   call(G)
    ).

'$ensure_loaded'(Spec) :-
    '$source_file'(Spec, File0),
    '$with_extension'(File0, File),
    (   '$$source_path'(File, Path) -> true
    ;   throw(error(existence_error(source_sink, Spec), _))
    ),
    ( '$consulted'(Path, _) -> true ; consult(Path) ).

'$source_file'(Spec, _) :- var(Spec), !, throw(error(instantiation_error, _)).
'$source_file'(library(Name), File) :-
    !,
    must_be(atom, Name),
    '$boot_file'(Boot),
    '$directory'(Boot, Dir),
    atom_concat(Dir, '/../lib/', D1),
    atom_concat(D1, Name, D2),
    atom_concat(D2, '.pl', File).
'$source_file'(File, File) :- atom(File), !.
'$source_file'(Spec, _) :- throw(error(domain_error(source_sink, Spec), _)).

'$with_extension'(File, File) :- '$$source_path'(File, _), !.
'$with_extension'(File, File1) :-
    atom_concat(File, '.pl', File1),
    '$$source_path'(File1, _),
    !.
'$with_extension'(File, File).

'$directory'(Path, Dir) :-
    '$$atom_codes'(Path, Cs),
    reverse(Cs, Rs),
    (   append(_, [0'/|RDs], Rs)
    ->  reverse(RDs, Ds),
        '$$atom_codes'(Dir, Ds)
    ;   Dir = '.'
    ).

%!  [], [+File|+Files] is det.
[].
[File|Files] :- consult(File), call(Files).

%!  repeat is nondet.
repeat.
repeat :- repeat.

% --- arithmetic ---

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
% var/1, nonvar/1, atom/1, number/1, integer/1, float/1, atomic/1,
% compound/1 and callable/1 are native.

%!  subsumes_term(@General, @Specific) is semidet.
subsumes_term(General, Specific) :-
    \+ \+ ( term_variables(Specific, SVars1),
            unify_with_occurs_check(General, Specific),
            term_variables(SVars1, SVars2),
            SVars1 == SVars2
          ).

%!  ground(@Term) is semidet.
ground(T) :- term_variables(T, []).

% --- errors ---

%!  '$with_context'(:Goal, +PI) is nondet.
%   An error Goal raises without a context, or from must_be/2 or can_be/2,
%   gets PI as its context.
'$with_context'(Goal, PI) :-
    catch(Goal, error(Formal, Context), '$rethrow'(Formal, Context, PI)).

'$rethrow'(Formal, Context0, PI) :-
    (   ( var(Context0) ; Context0 == must_be/2 ; Context0 == can_be/2 )
    ->  Context = PI
    ;   Context = Context0
    ),
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
    can_be(list, Sorted),
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


% --- database ---

%!  assertz/assert/asserta(+Clause), retract(+Clause).
%   Refuses static (consulted) predicates with permission_error unless declared dynamic/1;
%   asserting makes the predicate dynamic, so it still exists (and fails) once
%   its last clause is retracted.
assertz(MC) :- nonvar(MC), MC = M:C, !, '$module_clause'(M, C, C1), assertz(C1).
assertz(Clause) :- '$with_context'(('$check_clause'(Clause), '$check_static'(Clause)), assertz/1), '$make_dynamic'(Clause), '$$assertz'(Clause).
assert(MC) :- nonvar(MC), MC = M:C, !, '$module_clause'(M, C, C1), assert(C1).
assert(Clause) :- '$with_context'(('$check_clause'(Clause), '$check_static'(Clause)), assert/1), '$make_dynamic'(Clause), '$$assert'(Clause).
asserta(MC) :- nonvar(MC), MC = M:C, !, '$module_clause'(M, C, C1), asserta(C1).
asserta(Clause) :- '$with_context'(('$check_clause'(Clause), '$check_static'(Clause)), asserta/1), '$make_dynamic'(Clause), '$$asserta'(Clause).
retract(MC) :- nonvar(MC), MC = M:C, !, '$module_clause'(M, C, C1), retract(C1).
retract(Clause) :- '$with_context'(('$check_head'(Clause), '$check_static'(Clause)), retract/1), '$$retract'(Clause).

% Module:Clause is Clause with its head and the goals of its body renamed to
% Module's private predicates, where Module has one of that name.
'$module_clause'(M, _, _) :- var(M), !, throw(error(instantiation_error, _)).
'$module_clause'(M, C, C1) :-
    (   nonvar(C), C = (H :- B)
    ->  '$module_head'(M, H, H1), '$module_body'(M, B, B1), C1 = (H1 :- B1)
    ;   '$module_head'(M, C, C1)
    ).

'$module_body'(M, G, M:G) :- var(G), !.
'$module_body'(M, (A, B), (A1, B1)) :- !, '$module_body'(M, A, A1), '$module_body'(M, B, B1).
'$module_body'(M, (A ; B), (A1 ; B1)) :- !, '$module_body'(M, A, A1), '$module_body'(M, B, B1).
'$module_body'(M, (A -> B), (A1 -> B1)) :- !, '$module_body'(M, A, A1), '$module_body'(M, B, B1).
'$module_body'(M, \+ A, \+ A1) :- !, '$module_body'(M, A, A1).
'$module_body'(M, G, G1) :- '$module_head'(M, G, G1).

'$module_head'(M, H, H1) :-
    (   callable(H), M \== user -> '$$qualify'(M, H, H1) ; H1 = H ).

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
findall(Template, Goal, List) :-
    '$$bag_open'(Bag),
    catch(( call(Goal), '$$bag_add'(Bag, Template), fail ; true ), Error,
          ( '$$bag_drop'(Bag), throw(Error) )),
    '$$bag_collect'(Bag, List).

%!  current_predicate(?PI) is nondet.
%   PI is Name/Arity of a user-defined predicate with at least one clause.
current_predicate(PI) :-
    '$with_context'('$current_predicate'(PI), current_predicate/1).
'$current_predicate'(PI) :-
    (   var(PI) -> true
    ;   PI = N/A, ( var(N) ; atom(N) ), ( var(A) ; integer(A) ) -> true
    ;   throw(error(type_error(predicate_indicator, PI), _))
    ),
    '$$predicates'(Ps),
    member(N/A-F, Ps),
    \+ '$builtin_file'(F),
    \+ atom_concat('$', _, N),
    PI = N/A.

%!  clause(?Head, ?Body) is nondet.
clause(MH, Body) :- nonvar(MH), MH = M:H, !, '$module_head'(M, H, H1), clause(H1, Body).
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

%!  bagof(+Template, :Goal, -Bag) is nondet.
%   One Bag for each binding of Goal's free variables, those not in Template
%   or under V^; with none, the findall/3 of Goal, failing when empty. The
%   bags come in the standard order of their bindings, as in Scryer.
bagof(Template, Goal0, Bag) :-
    '$with_context'(can_be(list, Bag), bagof/3),
    '$bagof_strip'(Goal0, Goal, Ex),
    term_variables(Goal, GVs),
    term_variables(Template-Ex, Bound),
    '$bagof_free'(GVs, Bound, W),
    (   W == []
    ->  findall(Template, Goal, Bag),
        Bag \== []
    ;   findall(W-Template, Goal, Pairs),
        Pairs \== [],
        '$bagof_share'(Pairs, _),
        keysort(Pairs, Sorted),
        '$bagof_pick'(Sorted, W, Bag)
    ).

% nonvar first: an unbound Goal0 would otherwise unify with V^G0
% itself (binding fresh vars) and recurse on that fresh var forever.
'$bagof_strip'(Goal0, G, [V|Ex]) :-
    nonvar(Goal0),
    Goal0 = V ^ G0,
    !,
    '$bagof_strip'(G0, G, Ex).
'$bagof_strip'(G, G, []).

'$bagof_free'([], _, []).
'$bagof_free'([V|Vs], Bound, W) :-
    (   '$bagof_member'(V, Bound) -> W = W1 ; W = [V|W1] ),
    '$bagof_free'(Vs, Bound, W1).

'$bagof_member'(V, [U|Us]) :- ( V == U -> true ; '$bagof_member'(V, Us) ).

% findall/3 copies each solution apart, so a variable shared between them comes
% back as several; the n-th variable of every witness is made one again, as
% in Scryer.
'$bagof_share'([], _).
'$bagof_share'([W-_|Ps], Dict) :-
    term_variables(W, Vs),
    append(Vs, _, Dict),
    '$bagof_share'(Ps, Dict).

% Each run of pairs with identical witnesses is one bag.
'$bagof_pick'([K-T|Ps], W, Bag) :-
    '$bagof_run'(Ps, K, Ts, Rest),
    (   W = K, Bag = [T|Ts]
    ;   Rest \== [], '$bagof_pick'(Rest, W, Bag)
    ).

'$bagof_run'([K1-T|Ps], K, [T|Ts], Rest) :- K1 == K, !, '$bagof_run'(Ps, K, Ts, Rest).
'$bagof_run'(Rest, _, [], Rest).

%!  setof(+Template, :Goal, -Set) is nondet.
setof(Template, Goal, Set) :-
    bagof(Template, Goal, Bag),
    sort(Bag, Set).

% --- I/O ---

'$stream_alias'(user_output, 0).
'$stream_alias'(user_error, 1).
'$resolve_stream'(S, _) :- var(S), !, throw(error(instantiation_error, _)).
'$resolve_stream'(S, N) :- '$stream_alias'(S, N), !.
'$resolve_stream'('$stream'(Id), '$stream'(Id)) :- !.
'$resolve_stream'(A, S) :- atom(A), '$user_alias'(A, S), !.
'$resolve_stream'(user_input, _) :- !,
    throw(error(permission_error(output, stream, user_input), _)).
'$resolve_stream'(S, _) :- atom(S), !, throw(error(existence_error(stream, S), _)).
'$resolve_stream'(S, _) :- throw(error(domain_error(stream_or_alias, S), _)).

% The current output, as the stream's name and as the target the writing
% built-ins take.
:- dynamic('$output'/2).
'$output'(user_output, 0).

%!  current_output(?Stream) is det.
%!  set_output(+Stream) is det.
%   Closing the current output makes user_output current again.
current_output(S) :-
    (   ( var(S) ; S = '$stream'(_) ; atom(S), '$stream_alias'(S, _) )
    ->  '$output'(C, _),
        S = C
    ;   throw(error(domain_error(stream, S), current_output/1))
    ).

set_output(S) :-
    '$with_context'(('$resolve_stream'(S, N), '$output_stream'(S, N)), set_output/1),
    '$set_output'(S, N).

'$output_stream'(_, N) :- integer(N), !.
'$output_stream'(S, N) :-
    (   '$stream_info'(N, _, Mode, _, _, _)
    ->  ( Mode == read -> throw(error(permission_error(output, stream, S), _)) ; true )
    ;   throw(error(existence_error(stream, S), _))
    ).

'$set_output'(S0, N) :-
    '$std_name'(N, S1),
    ( atom(S1), '$stream_alias'(S1, _) -> S = S1 ; '$alias_stream'(S0, S) ),
    ( '$$retract'('$output'(_, _)) -> true ; true ),
    '$$assertz'('$output'(S, N)).

% The current output's target, checked to be a text stream unless it is a
% standard one.
'$out_text'(PI, N) :-
    '$output'(_, N),
    ( integer(N) -> true ; '$with_context'('$want_type'(N, text, output), PI) ).

%!  put_char(+Char), put_char(+Stream, +Char) is det.
%!  put_code(+Code), put_code(+Stream, +Code) is det.
put_char(C) :-
    '$out_text'(put_char/1, N),
    '$with_context'('$check_char'(C), put_char/1),
    '$$write_raw'(N, C, 2).
put_char(S, C) :-
    '$with_context'(('$resolve_stream'(S, N), '$want_type'(N, text, output), '$check_char'(C)), put_char/2),
    '$put'(N, C, S, put_char/2).
put_code(C) :-
    '$out_text'(put_code/1, N),
    '$with_context'('$code_char'(C, Ch), put_code/1),
    '$$write_raw'(N, Ch, 2).
put_code(S, C) :-
    '$with_context'(('$resolve_stream'(S, N), '$want_type'(N, text, output), '$code_char'(C, Ch)), put_code/2),
    '$put'(N, Ch, S, put_code/2).

'$put'(N, C, S, PI) :-
    ( '$$write_raw'(N, C, 2) -> true ; throw(error(existence_error(stream, S), PI)) ).

'$code_char'(C, _) :- var(C), !, throw(error(instantiation_error, _)).
'$code_char'(C, _) :- \+ integer(C), !, throw(error(type_error(integer, C), _)).
'$code_char'(C, Ch) :- '$char_code'(Ch, C).

%!  flush_output, flush_output(+Stream) is det.
flush_output :- '$output'(_, N), '$$flush'(N).
flush_output(S) :-
    '$with_context'('$resolve_stream'(S, N), flush_output/1),
    ( '$$flush'(N) -> true ; throw(error(existence_error(stream, S), flush_output/1)) ).

%!  open(@Source, @Mode, -Stream) is det.
%!  open(@Source, @Mode, -Stream, +Options) is det.
%   A file that cannot be opened raises existence_error, or permission_error
%   when it or its directory is there. Options are type(text|binary),
%   alias(Atom), eof_action(error|eof_code|reset) and reposition(Bool), with
%   Scryer's defaults text, eof_code and false.
open(Source, Mode, Stream) :- '$open'(Source, Mode, Stream, [], open/3).
open(Source, Mode, Stream, Options) :-
    '$open'(Source, Mode, Stream, Options, open/4).

'$open'(Source, Mode, Stream, Options, PI) :-
    O = opts(Alias, Type, Eof, Repos),
    '$with_context'(( '$open_check'(Source, Mode, Stream),
                      '$open_options'(Options, Options, O) ), PI),
    ( var(Type) -> Type = text ; true ),
    ( var(Eof) -> Eof = eof_code ; true ),
    ( var(Repos) -> Repos = false ; true ),
    (   '$with_context'('$$open'(Source, Mode, S), PI)
    ->  ( var(Alias) -> true ; '$$assertz'('$user_alias'(Alias, S)) ),
        '$$assertz'('$stream_info'(S, Source, Mode, Type, Eof, Repos)),
        Stream = S
    ;   '$open_error'(Source, Mode, E),
        throw(error(E, PI))
    ).

'$open_options'(L, _, _) :- var(L), !, throw(error(instantiation_error, _)).
'$open_options'([], _, _) :- !.
'$open_options'([O|Os], L, Opts) :-
    !,
    '$open_option'(O, Opts),
    '$open_options'(Os, L, Opts).
'$open_options'(_, L, _) :- throw(error(type_error(list, L), _)).

'$open_option'(O, _) :- var(O), !, throw(error(instantiation_error, _)).
'$open_option'(O, _) :- compound(O), arg(1, O, V), var(V), !, throw(error(instantiation_error, _)).
'$open_option'(type(T), opts(_, T0, _, _)) :- memberchk(T, [text, binary]), !, '$open_last'(T0, T).
'$open_option'(eof_action(A), opts(_, _, A0, _)) :-
    memberchk(A, [error, eof_code, reset]), !, '$open_last'(A0, A).
'$open_option'(reposition(B), opts(_, _, _, B0)) :- memberchk(B, [true, false]), !, '$open_last'(B0, B).
'$open_option'(alias(A), opts(Alias, _, _, _)) :-
    atom(A),
    !,
    (   ( '$user_alias'(A, _) ; '$stream_alias'(A, _) ; A == user_input )
    ->  throw(error(permission_error(open, source_sink, alias(A)), _))
    ;   '$open_last'(Alias, A)
    ).
'$open_option'(O, _) :- throw(error(domain_error(stream_option, O), _)).

% The first option of a kind counts.
'$open_last'(V, X) :- ( var(V) -> V = X ; true ).

:- dynamic('$user_alias'/2).
:- dynamic('$stream_info'/6).
:- dynamic('$stream_past'/1).

% A stream's alias, from open/4, as the stream itself.
'$alias_stream'(A, S) :- atom(A), '$user_alias'(A, S0), !, S = S0.
'$alias_stream'(S, S).

%!  close(@Stream) is det.
close(S0) :-
    '$alias_stream'(S0, S),
    '$$close'(S),
    (   '$$retract'('$user_alias'(_, S)) -> true ; true ),
    (   '$$retract'('$stream_info'(S, _, _, _, _, _)) -> true ; true ),
    (   '$$retract'('$stream_past'(S)) -> true ; true ),
    (   '$output'(_, S) -> '$set_output'(user_output, 0) ; true ).

%!  stream_property(?Stream, ?Property) is nondet.
stream_property(S, P) :-
    '$with_context'('$stream_property_args'(S, P, S1), stream_property/2),
    (   var(S1)
    ->  ( member(S1, [user_input, user_output, user_error]) ; '$stream_info'(S1, _, _, _, _, _) )
    ;   true
    ),
    '$stream_property'(S1, P),
    ( var(S) -> S = S1 ; true ).

'$stream_property_args'(S, P, S1) :-
    (   nonvar(P), \+ '$stream_property_name'(P)
    ->  throw(error(domain_error(stream_property, P), _))
    ;   var(S) -> true
    ;   memberchk(S, [user_input, user_output, user_error]) -> S1 = S
    ;   '$alias_stream'(S, S1), S1 = '$stream'(_), '$stream_info'(S1, _, _, _, _, _) -> true
    ;   S = '$stream'(_) -> throw(error(existence_error(stream, S), _))
    ;   atom(S) -> throw(error(existence_error(stream, S), _))
    ;   throw(error(domain_error(stream, S), _))
    ).

'$stream_property_name'(P) :-
    memberchk(P, [input, output, file_name(_), mode(_), alias(_), end_of_stream(_),
                  eof_action(_), reposition(_), type(_), position(_)]).

'$stream_property'(user_input, P) :-
    member(P, [input, mode(read), alias(user_input), end_of_stream(not),
               eof_action(eof_code), reposition(false), type(text)]).
'$stream_property'(user_output, P) :-
    member(P, [output, mode(write), alias(user_output), eof_action(eof_code),
               reposition(false), type(text)]).
'$stream_property'(user_error, P) :-
    member(P, [output, mode(write), alias(user_error), eof_action(eof_code),
               reposition(false), type(text)]).
'$stream_property'('$stream'(Id), P) :-
    S = '$stream'(Id),
    '$stream_info'(S, F, M, T, E, R),
    ( M == read -> IO = input ; IO = output ),
    (   P = IO
    ;   P = file_name(F)
    ;   P = mode(M)
    ;   '$user_alias'(A, S), P = alias(A)
    ;   M == read, '$end_of_stream'(S, EOS), P = end_of_stream(EOS)
    ;   P = eof_action(E)
    ;   P = reposition(R)
    ;   P = type(T)
    ).

'$end_of_stream'(S, E) :-
    (   '$stream_past'(S) -> E = past
    ;   '$$get_byte'(S, 1, -1) -> E = at
    ;   E = not
    ).

'$open_check'(Source, Mode, Stream) :-
    (   var(Source) -> throw(error(instantiation_error, _))
    ;   var(Mode) -> throw(error(instantiation_error, _))
    ;   \+ atom(Mode) -> throw(error(type_error(atom, Mode), _))
    ;   nonvar(Stream) -> throw(error(uninstantiation_error(Stream), _))
    ;   \+ atom(Source) -> throw(error(domain_error(source_sink, Source), _))
    ;   memberchk(Mode, [read, write, append]) -> true
    ;   throw(error(domain_error(io_mode, Mode), _))
    ).

'$open_error'(F, Mode, E) :-
    (   '$file_exists'(F)
    ->  E = permission_error(open, source_sink, F)
    ;   Mode \== read, '$directory'(F, Dir), '$file_exists'(Dir)
    ->  E = permission_error(open, source_sink, F)
    ;   E = existence_error(source_sink, F)
    ).

% file_mtime/2 is the platform's; without it nothing is known to exist.
'$file_exists'(F) :-
    catch(file_mtime(F, _), error(existence_error(procedure, _), _), fail).

%!  close(+Stream, +Options) is det.
%   Options: force(Bool), which changes nothing; close/1 never raises.
close(S, Opts) :-
    '$with_context'(('$options_list'(Opts), '$close_options'(Opts)), close/2),
    close(S).

'$close_options'([]).
'$close_options'([O|Os]) :-
    (   var(O) -> throw(error(instantiation_error, _))
    ;   O = force(_) -> '$option_bool'(O, close_option, _)
    ;   throw(error(domain_error(close_option, O), _))
    ),
    '$close_options'(Os).

%!  write(@Term), write(+Stream, @Term) is det.
%   TODO: no operator-aware output.
write(T) :- '$out_text'(write/1, N), '$$write_raw'(N, T, 2).
write(S, T) :-
    '$with_context'(('$resolve_stream'(S, N), '$want_type'(N, text, output)), write/2),
    ( '$$write_raw'(N, T, 2) -> true ; throw(error(existence_error(stream, S), write/2)) ).

%!  writeq(@Term) is det.
%!  writeq(+Stream, @Term) is det.
writeq(T) :- '$out_text'(writeq/1, N), '$$write_raw'(N, T, 3).
writeq(S, T) :-
    '$with_context'(('$resolve_stream'(S, N), '$want_type'(N, text, output)), writeq/2),
    ( '$$write_raw'(N, T, 3) -> true ; throw(error(existence_error(stream, S), writeq/2)) ).

%!  write_term(@Term, +Options) is det.
%!  write_term(+Stream, @Term, +Options) is det.
%   Options: quoted(Bool), ignore_ops(Bool), numbervars(Bool).
%   TODO: ignore_ops(false) is accepted but not honored.
write_term(T, Opts) :-
    '$out_text'(write_term/2, N),
    '$with_context'('$write_options'(Opts, Q, VNs), write_term/2),
    '$write_term'(N, T, Q, VNs).
write_term(S, T, Opts) :-
    '$with_context'(('$resolve_stream'(S, N), '$want_type'(N, text, output), '$write_options'(Opts, Q, VNs)), write_term/3),
    ( '$write_term'(N, T, Q, VNs) -> true ; throw(error(existence_error(stream, S), write_term/3)) ).

'$write_term'(N, T, Q, []) :- !, '$$write_raw'(N, T, Q).
'$write_term'(N, T, Q, VNs) :- '$$write_vars'(N, T, Q, VNs).

'$write_options'(Opts, Q, VNs) :-
    '$options_list'(Opts),
    '$write_options'(Opts, 0, Q, [], VNs).
'$write_options'([], Q, Q, VNs, VNs).
'$write_options'([O|Os], Q0, Q, VNs0, VNs) :-
    '$write_option'(O, Q0, Q1, VNs0, VNs1),
    '$write_options'(Os, Q1, Q, VNs1, VNs).

'$write_option'(O, _, _, _, _) :- var(O), !, throw(error(instantiation_error, _)).
'$write_option'(quoted(B), F0, F, VNs, VNs) :- '$option_bool'(quoted(B), write_option, V), !, F is F0 \/ V.
'$write_option'(ignore_ops(B), F0, F, VNs, VNs) :- '$option_bool'(ignore_ops(B), write_option, V), !, F is F0 \/ V << 2.
'$write_option'(numbervars(B), F0, F, VNs, VNs) :- '$option_bool'(numbervars(B), write_option, V), !, F is F0 \/ V << 1.
'$write_option'(double_quotes(B), F0, F, VNs, VNs) :- '$option_bool'(double_quotes(B), write_option, V), !, F is F0 \/ V << 4.
'$write_option'(variable_names(L), F, F, _, L) :- !, '$variable_names'(L, L).
'$write_option'(O, _, _, _, _) :- throw(error(domain_error(write_option, O), _)).

'$variable_names'(L, _) :- var(L), !, throw(error(instantiation_error, _)).
'$variable_names'([], _) :- !.
'$variable_names'([P|Ps], L) :-
    nonvar(P),
    P = (N = _),
    !,
    (   var(N) -> throw(error(instantiation_error, _))
    ;   atom(N) -> '$variable_names'(Ps, L)
    ;   throw(error(domain_error(write_option, variable_names(L)), _))
    ).
'$variable_names'([P|_], _) :- var(P), !, throw(error(instantiation_error, _)).
'$variable_names'(_, L) :- throw(error(domain_error(write_option, variable_names(L)), _)).

'$option_bool'(O, _, _) :- arg(1, O, B), var(B), !, throw(error(instantiation_error, _)).
'$option_bool'(O, _, 1) :- arg(1, O, true), !.
'$option_bool'(O, _, 0) :- arg(1, O, false), !.
'$option_bool'(O, Domain, _) :- throw(error(domain_error(Domain, O), _)).

'$options_list'(L) :- var(L), !, throw(error(instantiation_error, _)).
'$options_list'([]) :- !.
'$options_list'([_|L]) :- !, '$options_list'(L).
'$options_list'(L) :- throw(error(type_error(list, L), _)).

%!  write_canonical(@Term) is det.
%!  write_canonical(+Stream, @Term) is det.
write_canonical(T) :- write_term(T, [quoted(true), ignore_ops(true)]).
write_canonical(S, T) :- write_term(S, T, [quoted(true), ignore_ops(true)]).

'$chars_list'(L) :- '$text_list'(L, '$check_char').
'$check_char'(C) :- var(C), !, throw(error(instantiation_error, _)).
'$check_char'(C) :- character(C), !.
'$check_char'(C) :- throw(error(type_error(character, C), _)).

%!  nl is det.
%!  nl(+Stream) is det.
nl :- write('\n').
nl(S) :- write(S, '\n').

%!  atom_codes(?Atom, ?Codes) is det.
atom_codes(A, Cs) :-
    '$with_context'('$atom_codes'(A, Cs), atom_codes/2).
'$atom_codes'(A, Cs) :-
    (   nonvar(A)
    ->  must_be(atom, A),
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

%!  get_char(-Char), get_char(+Stream, -Char) is det.
%!  peek_char(-Char), peek_char(+Stream, -Char) is det.
%!  get_code(-Code), get_code(+Stream, -Code) is det.
%!  peek_code(-Code), peek_code(+Stream, -Code) is det.
%   Without a Stream they read the current input. At end of file Char is
%   end_of_file and Code is -1, on every read.
get_char(C) :-
    '$with_context'(('$current_input'(S), '$get_char'(S, 0, C)), get_char/1).
get_char(S, C) :- '$with_context'('$get_char'(S, 0, C), get_char/2).
peek_char(C) :-
    '$with_context'(('$current_input'(S), '$get_char'(S, 1, C)), peek_char/1).
peek_char(S, C) :- '$with_context'('$get_char'(S, 1, C), peek_char/2).
get_code(C) :-
    '$with_context'(('$current_input'(S), '$get_code'(S, 0, C)), get_code/1).

%!  get_byte(?Byte), get_byte(+Stream, ?Byte) is det.
%!  peek_byte(?Byte), peek_byte(+Stream, ?Byte) is det.
%!  put_byte(+Byte), put_byte(+Stream, +Byte) is det.
%   On a binary stream; -1 is the end. A byte of 0 cannot be written: atoms
%   are C strings.
get_byte(B) :- '$with_context'(('$current_input'(S), '$get_byte'(S, 0, B)), get_byte/1).
get_byte(S, B) :- '$with_context'('$get_byte'(S, 0, B), get_byte/2).
peek_byte(B) :- '$with_context'(('$current_input'(S), '$get_byte'(S, 1, B)), peek_byte/1).
peek_byte(S, B) :- '$with_context'('$get_byte'(S, 1, B), peek_byte/2).
put_byte(B) :- '$output'(S, _), '$with_context'('$put_byte'(S, B), put_byte/1).
put_byte(S, B) :- '$with_context'('$put_byte'(S, B), put_byte/2).

'$get_byte'(S0, Peek, B) :-
    '$alias_stream'(S0, S),
    (   var(B) -> true
    ;   integer(B), B >= -1, B =< 255 -> true
    ;   throw(error(type_error(in_byte, B), _))
    ),
    '$want_type'(S, binary, input),
    '$read_byte'(S, Peek, B0),
    B = B0.

'$put_byte'(S, B) :-
    '$resolve_stream'(S, N),
    (   var(B) -> throw(error(instantiation_error, _))
    ;   integer(B), B >= 0, B =< 255 -> true
    ;   throw(error(type_error(byte, B), _))
    ),
    '$want_type'(N, binary, output),
    char_code(C, B),
    '$$write_raw'(N, C, 2).
get_code(S, C) :- '$with_context'('$get_code'(S, 0, C), get_code/2).
peek_code(C) :-
    '$with_context'(('$current_input'(S), '$get_code'(S, 1, C)), peek_code/1).
peek_code(S, C) :- '$with_context'('$get_code'(S, 1, C), peek_code/2).

%!  read(-Term), read(+Stream, -Term) is det.
%!  read_term(-Term, +Options), read_term(+Stream, -Term, +Options) is det.
%   Reads the next term, through its end '.'; Term is end_of_file at the end.
%   Options: variables(-Vars), variable_names(-Pairs), singletons(-Pairs).
read(T) :-
    '$with_context'(('$current_input'(S), '$read_term'(S, T, [])), read/1).
read(S, T) :- '$with_context'('$read_term'(S, T, []), read/2).
read_term(T, Opts) :-
    '$with_context'(('$current_input'(S), '$read_term'(S, T, Opts)),
                    read_term/2).
read_term(S, T, Opts) :-
    '$with_context'('$read_term'(S, T, Opts), read_term/3).

'$read_term'(S0, T, Opts) :-
    '$alias_stream'(S0, S),
    '$want_type'(S, text, input),
    '$options_list'(Opts),
    '$read_options_check'(Opts),
    '$read_byte'(S, 1, _),
    '$$read_term'(S, T0, Names),
    ( T0 == end_of_file -> '$hit_eof'(S, 0) ; true ),
    term_variables(T0, Vars),
    '$read_options_bind'(Opts, T0, Names, Vars),
    T = T0.

'$read_options_check'([]).
'$read_options_check'([O|Os]) :-
    '$read_option_check'(O),
    '$read_options_check'(Os).
'$read_option_check'(O) :- var(O), !, throw(error(instantiation_error, _)).
'$read_option_check'(variable_names(_)) :- !.
'$read_option_check'(variables(_)) :- !.
'$read_option_check'(singletons(_)) :- !.
'$read_option_check'(O) :- throw(error(domain_error(read_option, O), _)).

'$read_options_bind'([], _, _, _).
'$read_options_bind'([O|Os], T, Names, Vars) :-
    '$read_option_bind'(O, T, Names, Vars),
    '$read_options_bind'(Os, T, Names, Vars).

'$read_option_bind'(variable_names(Names), _, Names, _).
'$read_option_bind'(variables(Vars), _, _, Vars).
'$read_option_bind'(singletons(Ss), T, Names, _) :- '$singletons'(Names, T, Ss).

'$singletons'([], _, []).
'$singletons'([N=V|NVs], T, Ss) :-
    '$occurrences'(T, V, 0, K),
    ( K =:= 1 -> Ss = [N=V|Ss1] ; Ss = Ss1 ),
    '$singletons'(NVs, T, Ss1).

'$occurrences'(X, V, K0, K) :- var(X), !, ( X == V -> K is K0 + 1 ; K = K0 ).
'$occurrences'(X, V, K0, K) :-
    compound(X), !,
    X =.. [_|As],
    '$occurrences_list'(As, V, K0, K).
'$occurrences'(_, _, K, K).

'$occurrences_list'([], _, K, K).
'$occurrences_list'([A|As], V, K0, K) :-
    '$occurrences'(A, V, K0, K1),
    '$occurrences_list'(As, V, K1, K).

:- dynamic('$input'/1).
'$input'(user_input).

%!  current_input(?Stream) is det.
%!  set_input(+Stream) is det.
%   Closing the current input makes user_input current again.
current_input(S) :-
    (   ( var(S) ; S = '$stream'(_) ; S == user_input )
    ->  '$current_input'(C),
        S = C
    ;   throw(error(domain_error(stream, S), current_input/1))
    ).

'$current_input'(S) :-
    '$input'(S0),
    (   S0 = '$stream'(_), '$$get_byte'(S0, 1, B), B =:= -2
    ->  S = user_input
    ;   S = S0
    ).

set_input(S) :- '$with_context'('$set_input'(S), set_input/1).

'$set_input'(S0) :-
    ( var(S0) -> throw(error(instantiation_error, _)) ; true ),
    '$alias_stream'(S0, S),
    '$input_stream'(S),
    ( S == user_input -> true ; '$read_byte'(S, 1, _) ),
    ( '$$retract'('$input'(_)) -> true ; true ),
    '$$assertz'('$input'(S)).

'$get_char'(S0, Peek, C) :-
    '$alias_stream'(S0, S),
    '$check_in_char'(C),
    '$want_type'(S, text, input),
    '$read_byte'(S, Peek, B),
    (   B =:= -1
    ->  C = end_of_file
    ;   char_code(C0, B),
        C = C0
    ).

'$get_code'(S0, Peek, C) :-
    '$alias_stream'(S0, S),
    '$check_in_code'(C),
    '$want_type'(S, text, input),
    '$read_byte'(S, Peek, B),
    C = B.

'$read_byte'(S, _, _) :- var(S), !, throw(error(instantiation_error, _)).
'$read_byte'(S, Peek, B) :-
    '$input_stream'(S),
    '$$get_byte'(S, Peek, B0),
    (   B0 =:= -2 -> throw(error(existence_error(stream, S), _))
    ;   B0 =:= -3 -> throw(error(permission_error(input, stream, S), _))
    ;   B0 =:= -1 -> '$hit_eof'(S, Peek), B = -1
    ;   B = B0
    ).

% A read that hits the end puts the stream past it; one more read then does
% what its eof_action says. A peek moves nothing.
'$hit_eof'(S, Peek) :-
    (   '$stream_past'(S)
    ->  (   '$stream_info'(S, _, _, _, error, _)
        ->  throw(error(permission_error(input, past_end_of_stream, S), _))
        ;   true
        )
    ;   Peek =:= 1
    ->  true
    ;   S = '$stream'(_)
    ->  '$$assertz'('$stream_past'(S))
    ;   true
    ).

% Text predicates want a text stream, byte predicates a binary one; the
% standard streams are text.
'$want_type'(S, _, _) :- var(S), !.
'$want_type'(S0, Want, Dir) :-
    '$std_name'(S0, S),
    (   '$stream_info'(S, _, Mode, Type, _, _) -> true ; Mode = none, Type = text ),
    (   Dir == input, Mode \== read, Mode \== none
    ->  throw(error(permission_error(input, stream, S), _))
    ;   Dir == output, Mode == read
    ->  throw(error(permission_error(output, stream, S), _))
    ;   Type == Want
    ->  true
    ;   Type == binary
    ->  throw(error(permission_error(Dir, binary_stream, S), _))
    ;   throw(error(permission_error(Dir, text_stream, S), _))
    ).

'$std_name'(N, S) :- ( integer(N), '$stream_alias'(S0, N) -> S = S0 ; S = N ).

'$input_stream'(user_input) :- !.
'$input_stream'('$stream'(_)) :- !.
'$input_stream'(S) :-
    '$stream_alias'(S, _), !,
    throw(error(permission_error(input, stream, S), _)).
'$input_stream'(S) :- atom(S), !, throw(error(existence_error(stream, S), _)).
'$input_stream'(S) :- throw(error(domain_error(stream_or_alias, S), _)).

'$check_in_char'(C) :- var(C), !.
'$check_in_char'(end_of_file) :- !.
'$check_in_char'(C) :- character(C), !.
'$check_in_char'(C) :- throw(error(type_error(in_character, C), _)).

'$check_in_code'(C) :- var(C), !.
'$check_in_code'(C) :- \+ integer(C), !, throw(error(type_error(integer, C), _)).
'$check_in_code'(C) :- C >= -1, !.
'$check_in_code'(_) :- throw(error(representation_error(in_character_code), _)).

%!  atom_length(+Atom, ?Length) is det.
atom_length(A, L) :-
    '$with_context'('$atom_length'(A, L), atom_length/2).
'$atom_length'(A, L) :-
    must_be(atom, A),
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
    can_be(atom, A),
    can_be(atom, B),
    can_be(atom, C),
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
    '$$atom_codes'(Atom, Cs),
    length(Cs, N),
    (   atom(Sub) -> '$$atom_codes'(Sub, SC), length(SC, L0), Length = L0
    ;   true
    ),
    '$sub_atom'(Cs, N, Before, Length, After, SC),
    ( var(Sub) -> '$$atom_codes'(Sub, SC) ; true ).
'$sub_atom'(Cs, N, B, L, A, SC) :-
    (   integer(B) -> B >= 0, length(BC, B), append(BC, Rest, Cs)
    ;   integer(L), integer(A) ->
        B is N - L - A, B >= 0, length(BC, B), append(BC, Rest, Cs)
    ;   '$sub_suffix'(Cs, 0, B, Rest)
    ),
    M is N - B,
    (   nonvar(SC) -> append(SC, _, Rest), A is M - L
    ;   integer(L) -> L >= 0, L =< M, length(SC, L), append(SC, _, Rest), A is M - L
    ;   integer(A) -> A >= 0, L is M - A, L >= 0, length(SC, L), append(SC, _, Rest)
    ;   '$sub_prefix'(Rest, 0, L, SC), A is M - L
    ).
'$sub_suffix'(Cs, B, B, Cs).
'$sub_suffix'([_|Cs], B0, B, R) :- B1 is B0 + 1, '$sub_suffix'(Cs, B1, B, R).
'$sub_prefix'(_, L, L, []).
'$sub_prefix'([C|Cs], L0, L, [C|P]) :- L1 is L0 + 1, '$sub_prefix'(Cs, L1, L, P).
'$sub_atom_check'(Atom, Before, Length, After, Sub) :-
    must_be(atom, Atom),
    can_be(atom, Sub),
    can_be(integer, Before),
    can_be(integer, Length),
    can_be(integer, After).

%!  atom_chars(?Atom, ?Chars) is det.
atom_chars(A, Chars) :-
    '$with_context'('$atom_chars'(A, Chars), atom_chars/2).
'$atom_chars'(A, Chars) :-
    (   nonvar(A)
    ->  must_be(atom, A),
        '$$atom_codes'(A, Codes),
        '$codes_chars'(Codes, Chars)
    ;   '$chars_list'(Chars),
        '$codes_chars'(Codes, Chars),
        '$$atom_codes'(A, Codes)
    ).

%!  number_codes(?Number, ?Codes) is det.
number_codes(N, Cs) :-
    '$with_context'('$number_codes'(N, Cs), number_codes/2).
'$number_codes'(N, Cs) :-
    (   nonvar(N)
    ->  must_be(number, N),
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
    ->  must_be(number, N),
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





'$codes_list'(L) :- '$text_list'(L, '$check_code').
'$check_code'(C) :- var(C), !, throw(error(instantiation_error, _)).
'$check_code'(C) :- integer(C), C >= 1, C =< 1114111, !.
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
retractall(MH) :- nonvar(MH), MH = M:H, !, '$module_clause'(M, H, H1), retractall(H1).
retractall(Head) :-
    '$with_context'('$check_static'(Head), retractall/1),
    '$make_dynamic'(Head),
    '$retractall'(Head).

'$retractall'(Head) :-
    ( copy_term(Head, Fresh), '$$retract'((Fresh :- _)) -> '$retractall'(Head) ; true ).

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

% The core's own dependencies.
:- consult('../lib/error.pl').
:- consult('../lib/lists.pl').
:- consult('../lib/misc.pl').

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

%!  [], [+File|+Files] is det.
[].
[File|Files] :- consult(File), call(Files).

%!  repeat is nondet.
repeat.
repeat :- repeat.

% --- lists, apply ---

% These load before the op/3 directives below, which need member/2.
:- consult('../lib/lists.pl').
:- consult('../lib/apply.pl').

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
    ;   atom(O) -> ( memberchk(O, [<, =, >]) -> true ; throw(error(domain_error(order, O), _)) )
    ;   throw(error(type_error(atom, O), _))
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

% --- sorting ---

%!  msort(+List, -Sorted) is det.
%   Stable merge sort: O(n log n)
msort(L, Sorted) :-
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
sort(L, Sorted) :- msort(L, M), '$dedup'(M, Sorted).
'$dedup'([], []).
'$dedup'([X], [X]) :- !.
'$dedup'([X,Y|T], R) :- X == Y, !, '$dedup'([Y|T], R).
'$dedup'([X,Y|T], [X|R]) :- '$dedup'([Y|T], R).

% --- database ---

%!  assertz/assert/asserta(+Clause), retract(+Clause).
%   Refuses static (consulted) predicates with permission_error unless declared dynamic/1;
%   asserting makes the predicate dynamic, so it still exists (and fails) once
%   its last clause is retracted.
assertz(Clause) :- '$check_clause'(Clause), '$check_static'(Clause), '$make_dynamic'(Clause), '$$assertz'(Clause).
assert(Clause) :- '$check_clause'(Clause), '$check_static'(Clause), '$make_dynamic'(Clause), '$$assert'(Clause).
asserta(Clause) :- '$check_clause'(Clause), '$check_static'(Clause), '$make_dynamic'(Clause), '$$asserta'(Clause).
retract(Clause) :- '$check_head'(Clause), '$check_static'(Clause), '$$retract'(Clause).

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

'$next_id'(Id) :- '$$retract'('$id_counter'(N0)), !, Id is N0 + 1, '$$assertz'('$id_counter'(Id)).
'$next_id'(0) :- '$$assertz'('$id_counter'(0)).

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
with_output_to(codes(Cs), Goal) :- with_output_to(atom(A), Goal), atom_codes(A, Cs).

'$stream_alias'(user_output, 0).
'$stream_alias'(user_error, 1).
'$resolve_stream'(S, N) :- '$stream_alias'(S, N), !.
'$resolve_stream'('$stream'(Id), '$stream'(Id)) :- !.
'$resolve_stream'(S, _) :- throw(error(domain_error(stream_or_alias, S), _)).

%!  write(@Term), write(+Stream, @Term) is det.
%   TODO: no operator-aware output.
write(T) :- '$$write_raw'(0, T, 0).
write(S, T) :-
    '$resolve_stream'(S, N),
    ( '$$write_raw'(N, T, 0) -> true ; throw(error(existence_error(stream, S), write/2)) ).

%!  writeq(@Term) is det.
%!  writeq(+Stream, @Term) is det.
writeq(T) :- '$$write_raw'(0, T, 1).
writeq(S, T) :-
    '$resolve_stream'(S, N),
    ( '$$write_raw'(N, T, 1) -> true ; throw(error(existence_error(stream, S), writeq/2)) ).

%!  nl is det.
%!  nl(+Stream) is det.
nl :- write('\n').
nl(S) :- write(S, '\n').

%!  writeln(@Term) is det.
%!  writeln(+Stream, @Term) is det.
writeln(T) :- write(T), nl.
writeln(S, T) :- write(S, T), nl(S).

%!  char_code(?Char, ?Code) is det.
char_code(Char, Code) :- atom_codes(Char, [Code]).

%!  get_char(-Char) is det.
get_char(Char) :- get_code(C), (C == -1 -> Char = end_of_file ; char_code(Char, C)).

%!  atom_length(+Atom, -Length) is det.
atom_length(A, L) :- atom_codes(A, C), length(C, L).

%!  atom_concat(?Atom1, ?Atom2, ?Atom3) is nondet.
%   Nondet split falls out of append/3's own backtracking.
atom_concat(A, B, C) :-
    nonvar(A),
    nonvar(B),
    !,
    atom_codes(A, CA),
    atom_codes(B, CB),
    append(CA, CB, CC),
    atom_codes(C, CC).
atom_concat(A, B, C) :-
    atom_codes(C, CC),
    append(CA, CB, CC),
    atom_codes(A, CA),
    atom_codes(B, CB).

%!  sub_atom(+Atom, ?Before, ?Length, ?After, ?Sub) is nondet.
sub_atom(Atom, Before, Length, After, Sub) :-
    atom_codes(Atom, Codes),
    append(BC, RestC, Codes),
    length(BC, Before),
    append(SC, AC, RestC),
    length(SC, Length),
    length(AC, After),
    atom_codes(Sub, SC).

%!  atom_chars(?Atom, ?Chars) is det.
atom_chars(A, Chars) :-
    nonvar(A),
    !,
    atom_codes(A, Codes),
    maplist(char_code, Chars, Codes).
atom_chars(A, Chars) :-
    maplist(char_code, Chars, Codes),
    atom_codes(A, Codes).

%!  atom_number(?Atom, ?Number) is semidet.
atom_number(A, N) :-
    nonvar(A),
    !,
    atom_codes(A, C),
    number_codes(N, C).
atom_number(A, N) :-
    number_codes(N, C),
    atom_codes(A, C).

%!  number_chars(?Number, ?Chars) is det.
number_chars(N, Chars) :-
    nonvar(N),
    !,
    number_codes(N, Codes),
    maplist(char_code, Chars, Codes).
number_chars(N, Chars) :-
    maplist(char_code, Chars, Codes),
    number_codes(N, Codes).

%!  retractall(+Head) is det.
%   an unknown predicate is created as dynamic.
retractall(Head) :-
    '$check_static'(Head),
    '$make_dynamic'(Head),
    '$retractall'(Head).

'$retractall'(Head) :-
    ( copy_term(Head, Fresh), '$$retract'(Fresh) -> '$retractall'(Head) ; true ).

%!  abolish(+Name/Arity) is det.
%   the predicate stops existing
abolish(PI) :-
    ( var(PI) -> throw(error(instantiation_error, _)) ; true ),
    ( PI = Name/Arity -> true ; throw(error(type_error(predicate_indicator, PI), _)) ),
    ( ( var(Name) ; var(Arity) ) -> throw(error(instantiation_error, _)) ; true ),
    ( atom(Name) -> true ; throw(error(type_error(atom, Name), _)) ),
    ( integer(Arity) -> true ; throw(error(type_error(integer, Arity), _)) ),
    ( Arity >= 0 -> true ; throw(error(domain_error(not_less_than_zero, Arity), _)) ),
    current_prolog_flag(max_arity, MaxArity),
    ( Arity =< MaxArity -> true ; throw(error(representation_error(max_arity), _)) ),
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
    ; var(Priority) -> throw(error(instantiation_error, _))
    ; throw(error(type_error(integer, Priority), _))
    ),
    ( Priority >= 0, Priority =< 1200 -> true
    ; throw(error(domain_error(operator_priority, Priority), _))
    ),
    '$op_class'(Type, Class),
    ( Name = [_|_] -> Names = Name ; Names = [Name] ),
    forall(member(N, Names), '$op_one'(Priority, Type, Class, N)).

'$op_class'(xfx, infix).
'$op_class'(xfy, infix).
'$op_class'(yfx, infix).
'$op_class'(fy, prefix).
'$op_class'(fx, prefix).
'$op_class'(xf, postfix).
'$op_class'(yf, postfix).
'$op_class'(Type, _) :-
    \+ '$op_class_known'(Type),
    throw(error(domain_error(operator_specifier, Type), _)).

'$op_class_known'(xfx). '$op_class_known'(xfy). '$op_class_known'(yfx).
'$op_class_known'(fy).  '$op_class_known'(fx).
'$op_class_known'(xf).  '$op_class_known'(yf).

'$op_one'(_, _, _, Name) :-
    ( Name == [] ; Name == {} ),
    !,
    throw(error(permission_error(create, operator, Name), _)).
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

%!  current_op(?Priority, ?Type, ?Name) is nondet.
current_op(P, T, N) :- '$$op'(P, T, N).

% Seeds '$$op'/3 with the parser's own hardcoded table
:- op(1200, xfx, :-).
:- op(1200, fx, :-).
:- op(1200, fx, ?-).
:- op(1100, xfy, ;).
:- op(1050, xfy, ->).
:- op(1000, xfy, ',').
:- op(900, fy, \+).
:- op(700, xfx, =).
:- op(700, xfx, \=).
:- op(700, xfx, ==).
:- op(700, xfx, \==).
:- op(700, xfx, is).
:- op(700, xfx, <).
:- op(700, xfx, >).
:- op(700, xfx, =<).
:- op(700, xfx, >=).
:- op(700, xfx, =:=).
:- op(700, xfx, =\=).
:- op(700, xfx, =..).
:- op(700, xfx, @<).
:- op(700, xfx, @>).
:- op(700, xfx, @=<).
:- op(700, xfx, @>=).
:- op(500, yfx, +).
:- op(500, yfx, -).
:- op(400, yfx, *).
:- op(400, yfx, /).
:- op(400, yfx, mod).
:- op(400, yfx, //).
:- op(200, fy, -).
:- op(200, fy, +).
:- op(500, yfx, \/).
:- op(400, yfx, xor).
:- op(400, yfx, <<).
:- op(400, yfx, >>).
:- op(400, yfx, /\).
:- op(200, fy, \).
:- op(200, xfy, ^).

% --- prolog flags ---

%!  current_prolog_flag(?Flag, ?Value) is nondet.
%   no set_prolog_flag/2 currently
current_prolog_flag(Flag, Value) :-
    '$prolog_flag_name'(Flag),
    '$$prolog_flag_value'(Flag, Value).
current_prolog_flag(Flag, _) :-
    nonvar(Flag),
    \+ '$prolog_flag_name'(Flag),
    throw(error(domain_error(prolog_flag, Flag), _)).

'$prolog_flag_name'(bounded).
'$prolog_flag_name'(max_integer).
'$prolog_flag_name'(min_integer).
'$prolog_flag_name'(integer_rounding_function).
'$prolog_flag_name'(max_arity).
'$prolog_flag_name'(double_quotes).

% --- DCG ---

:- consult('../lib/dcg.pl').

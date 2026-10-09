% dynamic declaration, static protection, consulted/unconsult tests

% --- dynamic declaration allows assert/retract ---

:- dynamic(dyn_val/1).

?- assertz(dyn_val(1)).
   true.

?- dyn_val(X).
   X = 1.

?- retract(dyn_val(1)).
   true.

?- dyn_val(_).
   false.

% comma form: dynamic((f/1, g/2))

:- dynamic((dyn_a/1, dyn_b/2)).

?- assertz(dyn_a(hello)).
   true.

?- assertz(dyn_b(1, 2)).
   true.

?- dyn_a(X).
   X = hello.

?- dyn_b(A, B).
   A = 1, B = 2.

?- retractall(dyn_a(_)).
   true.

?- dyn_a(_).
   false.

% --- assert/retract on pure dynamic predicate (no file clauses) ---

:- dynamic(scratch/1).

?- assertz(scratch(x)), assertz(scratch(y)), assertz(scratch(z)).
   true.

?- findall(V, scratch(V), L).
   L = "xyz".

?- retract(scratch(y)).
   true.

?- findall(V, scratch(V), L).
   L = "xz".

?- retractall(scratch(_)).
   true.

?- scratch(_).
   false.

% --- static procedure protection uses core.pl predicates (file-tracked) ---
% append/3 and member/2 are loaded from core.pl with source_file != -1

?- catch(assertz(append(a, b, c)), error(permission_error(modify, static_procedure, _), _), true).
   true.

?- catch(asserta(append(a, b, c)), error(permission_error(modify, static_procedure, _), _), true).
   true.

?- catch(retract(append(_, _, _)), error(permission_error(modify, static_procedure, _), _), true).
   true.

?- catch(retractall(append(_, _, _)), error(permission_error(modify, static_procedure, _), _), true).
   true.

% core.pl predicate still intact after failed modifies
?- append([1], [2], L).
   L = [1, 2].

% member/2 also protected
?- catch(assertz(member(x, y)), error(permission_error(modify, static_procedure, _), _), true).
   true.

% --- declaring dynamic lifts the restriction on a file-loaded predicate ---
% (use a fresh predicate to avoid affecting core.pl tests)

:- dynamic(dyn_lifted/1).

?- assertz(dyn_lifted(a)).
   true.

?- assertz(dyn_lifted(b)).
   true.

?- findall(X, dyn_lifted(X), L).
   L = "ab".

?- retract(dyn_lifted(a)).
   true.

?- findall(X, dyn_lifted(X), L).
   L = "b".

?- retractall(dyn_lifted(_)).
   true.

% --- unconsult: fails for unknown file ---

?- unconsult(no_such_file).
   false.

% --- consulted: returns a list including core.pl ---

?- \+ consulted([]).
   true.

% --- compaction: assert/retract cycle stays correct ---

:- dynamic(cycle_val/1).

?- assertz(cycle_val(1)), assertz(cycle_val(2)), assertz(cycle_val(3)),
   retract(cycle_val(2)),
   assertz(cycle_val(4)),
   retract(cycle_val(1)), retract(cycle_val(3)).
   true.

?- findall(V, cycle_val(V), L).
   L = [4].

?- retractall(cycle_val(_)).
   true.

% stress test: many assert/retract cycles don't corrupt state

:- dynamic(loop_val/1).

loop_n(0) :- !.
loop_n(N) :-
  N > 0,
  assertz(loop_val(N)),
  retract(loop_val(N)),
  N1 is N - 1,
  loop_n(N1).

?- loop_n(30).
   true.

?- loop_val(_).
   false.

% verify core.pl predicates still work after compaction stress
?- append([a, b], [c], L).
   L = "abc".

?- member(2, [1, 2, 3]).
   true.

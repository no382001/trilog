% ledit_quad.pl -- Tests for ledit.pl line editor
%
% Tests pure-logic and state-management predicates.
% I/O-dependent predicates (add, get, save, main loop) are not tested here.
%
% NOTE: State mutations (l_set, assert, retract) must be in directives
% because the quad runner's solve_all tries multiple solutions and
% assert/retract side-effects are not rolled back on backtrack.
% Queries that call l_set (retract+assert) after a user-defined predicate
% like l_reverse will generate spurious extra solutions from the mutated state.
% So we do state mutations in directives and only query the resulting state.

:- consult('ledit.pl').

% ===== Pure utilities =====

% --- reverse/3 (from core.pl) ---

?- reverse([], [], L).
   L = [].

?- reverse([1, 2, 3], [], L).
   L = [3, 2, 1].

?- reverse([a, b], [c, d], L).
   L = [b, a, c, d].

?- reverse([x], [], L).
   L = [x].

% --- member/2 (from core.pl) ---

?- member(a, [a, b, c]).
   true.

?- member(b, [a, b, c]).
   true.

?- member(c, [a, b, c]).
   true.

?- member(d, [a, b, c]).
   false.

?- member(x, []).
   false.

% --- l_skip_spaces/2 ---

?- l_skip_spaces([' ', ' ', a, b], R).
   R = [a, b].

?- l_skip_spaces([a, b], R).
   R = [a, b].

?- l_skip_spaces([], R).
   R = [].

?- l_skip_spaces([' '], R).
   R = [].

% --- l_number/2 ---

?- l_number([], N).
   N = 1.

?- l_number(['3'], N).
   N = 3.

?- l_number(['1', '2'], N).
   N = 12.

?- l_number(['0'], N).
   N = 0.

?- l_number(['9', '9', '9'], N).
   N = 999.

% --- l_collect_to/4 ---

?- l_collect_to([a, b, c], c, Acc, Tail).
   Acc = [a, b], Tail = [].

?- l_collect_to([a, b, c, d, e], c, Acc, Tail).
   Acc = [a, b], Tail = [d, e].

?- l_collect_to([c, d], c, Acc, Tail).
   Acc = [], Tail = [d].

?- l_collect_to([], c, Acc, Tail).
   Acc = [], Tail = [].

% --- l_replace_all/4 ---

?- l_replace_all(hello, x, y, R).
   R = hello.

?- l_replace_all(abcabc, abc, x, R).
   R = xx.

?- l_replace_all('hello world', ' ', '-', R).
   R = hello-world.

?- l_replace_all(aaa, a, bb, R).
   R = bbbbbb.

% --- l_for/2 ---

?- l_for(0, fail).
   true.

?- X = 0, l_for(3, (X = 0)).
   X = 0.

% ===== State management =====

% --- l_set/2 and l_value ---

:- l_set(test_key, 42).

?- l_value(test_key, V).
   V = 42.

:- l_set(test_key, hello).

?- l_value(test_key, V).
   V = hello.

% --- l_set/3 (pattern-matching update) ---

:- l_set(test_s3, start).
:- l_set(test_s3, start, finish).

?- l_value(test_s3, V).
   V = finish.

% l_set/3 fails on mismatch
:- l_set(test_s3b, aaa).

?- l_set(test_s3b, bbb, ccc).
   false.

?- l_value(test_s3b, V).
   V = aaa.

% ===== Initialization =====

:- (retract(l_value(line, _)) -> true ; true).
:- (retract(l_value(delete, _)) -> true ; true).
:- l_initialize.

?- l_value(line, L).
   L = ['*** top_of_file ***'],[].

?- l_value(delete, D).
   D = [].

% ===== Navigation =====

% --- l_backward ---

:- l_set(line, (['line two', 'line one', '*** top_of_file ***'], ['line three'])).

?- l_backward, l_value(line, L).
   L = ['line one', '*** top_of_file ***'],['line two', 'line three'].

% backward at top fails
:- l_set(line, (['*** top_of_file ***'], ['line one', 'line two', 'line three'])).

?- l_backward.
   false.

% --- l_forward ---

:- l_set(line, (['line one', '*** top_of_file ***'], ['line two', 'line three'])).

?- l_forward, l_value(line, L).
   L = ['line two', 'line one', '*** top_of_file ***'],['line three'].

% forward at end fails
:- l_set(line, (['line three', 'line two', 'line one', '*** top_of_file ***'], [])).

?- l_forward.
   false.

% --- l_do backward with count ---

:- l_set(line, (['line three', 'line two', 'line one', '*** top_of_file ***'], [])).

?- l_do([b, ' ', '2']), l_value(line, L).
   L = ['line one', '*** top_of_file ***'],['line two', 'line three'].

% --- l_do forward with count ---

:- l_set(line, (['*** top_of_file ***'], ['line one', 'line two', 'line three'])).

?- l_do([f, ' ', '2']), l_value(line, L).
   L = ['line two', 'line one', '*** top_of_file ***'],['line three'].

% --- rewind ---

:- l_set(line, (['line three', 'line two', 'line one', '*** top_of_file ***'], [])).
:- l_do([r]).

?- l_value(line, L).
   L = ['*** top_of_file ***'],['line one', 'line two', 'line three'].

% rewind from middle
:- l_set(line, (['line two', 'line one', '*** top_of_file ***'], ['line three'])).
:- l_do([r]).

?- l_value(line, L).
   L = ['*** top_of_file ***'],['line one', 'line two', 'line three'].

% --- wind ---

:- l_set(line, (['*** top_of_file ***'], ['line one', 'line two', 'line three'])).
:- l_do([w]).

?- l_value(line, L).
   L = ['line three', 'line two', 'line one', '*** top_of_file ***'],[].

% wind from middle
:- l_set(line, (['line one', '*** top_of_file ***'], ['line two', 'line three'])).
:- l_do([w]).

?- l_value(line, L).
   L = ['line three', 'line two', 'line one', '*** top_of_file ***'],[].

% ===== Delete =====

% Single delete from current position (Below is non-empty)
:- l_set(line, (['line two', 'line one', '*** top_of_file ***'], ['line three'])).
:- l_set(delete, []).

?- l_deletebuf, l_delete, l_value(line, L), l_value(delete, D).
   L = ['line three', 'line one', '*** top_of_file ***'],[], D = ['line two'].

% Delete at end (Below=[]) -- l_delete succeeds in modifying state then fails
% to advance, so we catch it with -> to still verify state
:- l_set(line, (['line three', 'line two', 'line one', '*** top_of_file ***'], [])).
:- l_set(delete, []).
:- l_deletebuf.
:- (l_delete -> true ; true).

?- l_value(line, L).
   L = ['line two', 'line one', '*** top_of_file ***'],[].

?- l_value(delete, D).
   D = ['line three'].

% Delete via l_do (with count, from position with Below)
:- l_set(line, (['line two', 'line one', '*** top_of_file ***'], ['line three'])).
:- l_set(delete, []).
:- l_do([d, ' ', '2']).

?- l_value(line, L).
   L = ['line one', '*** top_of_file ***'],[].

% Delete at top-of-file (via l_do, succeeds but does nothing)
:- l_set(line, (['*** top_of_file ***'], [])).

?- l_do([d]).
   true.

% --- Delete all ---

:- l_set(line, (['line three', 'line two', 'line one', '*** top_of_file ***'], [])).
:- l_set(delete, []).
:- l_do(['D']).

?- l_value(line, L).
   L = ['*** top_of_file ***'],[].

% ===== Yank =====

% Yank from empty delete buffer prints ? (succeeds but does nothing)
:- l_set(delete, []).

?- l_do([y]).
   true.

% Yank restores deleted lines
:- l_set(line, (['line two', 'line one', '*** top_of_file ***'], ['line three'])).
:- l_set(delete, []).
:- l_deletebuf.

?- l_delete, l_value(delete, D).
   D = ['line two'].

% Now yank it back
:- l_do([y]).

?- l_value(line, L).
   L = ['line two', 'line three', 'line one', '*** top_of_file ***'],[].

% ===== Change =====

:- l_set(line, (['hello world', '*** top_of_file ***'], [])).

% l_change_once replaces first occurrence
?- l_change_once(hello, goodbye), l_value(line, ([T|_], _)).
   T = 'goodbye world'.

% l_changes replaces all occurrences
:- l_set(line, (['aaa bbb aaa', '*** top_of_file ***'], [])).

?- l_changes(aaa, zzz), l_value(line, ([T|_], _)).
   T = 'zzz bbb zzz'.

% change with no match leaves line unchanged
:- l_set(line, ([hello, '*** top_of_file ***'], [])).

?- l_change_once(xyz, abc), l_value(line, ([T|_], _)).
   T = hello.

% ===== l_continuation =====

% With prior command stored, empty input repeats it
:- l_set(command, [f]).

?- l_continuation([], X).
   X = [f].

% Non-empty input stores new command
?- l_continuation([b], X).
   X = [b].

?- l_value(command, C).
   C = [b].

% ===== l_listing (line ordering assembly) =====

?- reverse([b, a, top], [c], [_|L3]), !.
   L3 = [a, b, c].

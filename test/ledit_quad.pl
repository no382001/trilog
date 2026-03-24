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
:- (retract(l_value(newnum, _)) -> true ; true).
:- (retract(l_value(delete, _)) -> true ; true).
:- (retract(l_line(0, _)) -> true ; true).
:- l_initialize.

?- l_value(line, L).
   L = [0],[].

?- l_value(newnum, N).
   N = 1.

?- l_value(delete, D).
   D = [].

?- l_line(0, T).
   T = '*** top_of_file ***'.

% ===== Line numbering =====

:- l_set(newnum, 100).

?- l_newnum(N).
   N = 100.

?- l_value(newnum, N2).
   N2 = 101.

% ===== Navigation =====

% Set up a buffer: lines 1,2,3 with current at line 2
:- (retract(l_line(1, _)) -> true ; true), assert(l_line(1, 'line one')).
:- (retract(l_line(2, _)) -> true ; true), assert(l_line(2, 'line two')).
:- (retract(l_line(3, _)) -> true ; true), assert(l_line(3, 'line three')).

% --- l_backward ---

:- l_set(line, ([2, 1, 0], [3])).

?- l_backward, l_value(line, L).
   L = [1, 0],[2, 3].

% backward at top fails (only line 0)
:- l_set(line, ([0], [1, 2, 3])).

?- l_backward.
   false.

% --- l_forward ---

:- l_set(line, ([1, 0], [2, 3])).

?- l_forward, l_value(line, L).
   L = [2, 1, 0],[3].

% forward at end fails
:- l_set(line, ([3, 2, 1, 0], [])).

?- l_forward.
   false.

% --- l_do backward with count ---

:- l_set(line, ([3, 2, 1, 0], [])).

?- l_do([b, ' ', '2']), l_value(line, L).
   L = [1, 0],[2, 3].

% --- l_do forward with count ---

:- l_set(line, ([0], [1, 2, 3])).

?- l_do([f, ' ', '2']), l_value(line, L).
   L = [2, 1, 0],[3].

% --- rewind (uses l_reverse internally) ---
% Test via directive since l_do([r]) does retract+assert after l_reverse

:- l_set(line, ([3, 2, 1, 0], [])).
:- l_do([r]).

?- l_value(line, L).
   L = [0],[1, 2, 3].

% rewind from middle
:- l_set(line, ([2, 1, 0], [3])).
:- l_do([r]).

?- l_value(line, L).
   L = [0],[1, 2, 3].

% --- wind (uses l_reverse internally) ---

:- l_set(line, ([0], [1, 2, 3])).
:- l_do([w]).

?- l_value(line, L).
   L = [3, 2, 1, 0],[].

% wind from middle
:- l_set(line, ([1, 0], [2, 3])).
:- l_do([w]).

?- l_value(line, L).
   L = [3, 2, 1, 0],[].

% ===== Delete =====

% Single delete from current position (Below is non-empty)
:- l_set(line, ([2, 1, 0], [3])).
:- l_set(delete, []).

?- l_deletebuf, l_delete, l_value(line, L), l_value(delete, D).
   L = [3, 1, 0],[], D = [2].

% Delete at end (Below=[]) -- l_delete succeeds in modifying state then fails
% to advance, so we catch it with -> to still verify state
:- l_set(line, ([3, 2, 1, 0], [])).
:- l_set(delete, []).
:- l_deletebuf.
:- (l_delete -> true ; true).

?- l_value(line, L).
   L = [2, 1, 0],[].

?- l_value(delete, D).
   D = [3].

% Delete via l_do (with count, from position with Below)
:- l_set(line, ([2, 1, 0], [3])).
:- l_set(delete, []).
:- l_do([d, ' ', '2']).

?- l_value(line, L).
   L = [1, 0],[].

% Delete at line 0 prints ? (via l_do, succeeds but does nothing)
:- l_set(line, ([0], [])).

?- l_do([d]).
   true.

% --- Delete all (via directive since it uses l_reverse internally) ---

:- l_set(line, ([3, 2, 1, 0], [])).
:- l_set(delete, []).
:- l_do(['D']).

?- l_value(line, L).
   L = [0],[].

% ===== Yank =====

% Yank from empty delete buffer prints ? (succeeds but does nothing)
:- l_set(delete, []).

?- l_do([y]).
   true.

% Yank restores deleted lines
:- l_set(line, ([2, 1, 0], [3])).
:- l_set(delete, []).
:- l_set(newnum, 200).
:- l_deletebuf.

?- l_delete, l_value(delete, D).
   D = [2].

% Now yank it back (via directive since yank uses l_reverse-like patterns)
:- l_do([y]).

?- l_value(line, ([N, 3, 1, 0], [])), l_line(N, T).
   N = 200, T = 'line two'.

% ===== Change =====

:- (retract(l_line(10, _)) -> true ; true), assert(l_line(10, 'hello world')).
:- l_set(line, ([10, 0], [])).

% l_change_once replaces first occurrence
?- l_change_once(hello, goodbye), l_line(10, T).
   T = 'goodbye world'.

% l_changes replaces all occurrences
:- (retract(l_line(10, _)) -> true ; true), assert(l_line(10, 'aaa bbb aaa')).
:- l_set(line, ([10, 0], [])).

?- l_changes(aaa, zzz), l_line(10, T).
   T = 'zzz bbb zzz'.

% change with no match leaves line unchanged
:- (retract(l_line(10, _)) -> true ; true), assert(l_line(10, hello)).
:- l_set(line, ([10, 0], [])).

?- l_change_once(xyz, abc), l_line(10, T).
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

?- reverse([2, 1, 0], [3], [_|L3]), !.
   L3 = [1, 2, 3].

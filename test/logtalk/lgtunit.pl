% The lgtunit predicates that Logtalk's Prolog tests call, as plain ISO
% Prolog for the quad files in test/logtalk/.
%
% lgt_run(Goal): runs Goal once without binding its variables, then restores
% the current input and output and closes the streams the helpers opened.
% It succeeds, fails or throws as Goal does.

:- dynamic(lgt_stream/1).

lgt_run(Goal) :-
    current_input(In),
    current_output(Out),
    catch(( \+ \+ call(Goal) -> Result = true ; Result = false ), Ball, Result = ball(Ball)),
    lgt_restore(In, Out),
    lgt_result(Result).

lgt_result(true).
lgt_result(ball(Ball)) :- throw(Ball).

lgt_restore(In, Out) :-
    catch(set_input(In), _, set_input(user_input)),
    catch(set_output(Out), _, set_output(user_output)),
    lgt_close_tracked.

lgt_close_tracked :-
    retract(lgt_stream(S)),
    catch(close(S), _, true),
    fail.
lgt_close_tracked.

lgt_track(S) :- assertz(lgt_stream(S)).

:- dynamic(lgt_dir/1).

lgt_dir('_build/logtalk/').

% lgt_files(Name): the test files this suite reads are in _build/logtalk/Name/.
lgt_files(Name) :-
    retract(lgt_dir(_)),
    atom_concat('_build/logtalk/', Name, D0),
    atom_concat(D0, '/', D),
    assertz(lgt_dir(D)).

:- op(700, xfx, =~=).

'=~='(X, _) :- var(X), !, throw(error(instantiation_error, (=~=)/2)).
'=~='(_, Y) :- var(Y), !, throw(error(instantiation_error, (=~=)/2)).
'=~='([], []) :- !.
'=~='([X|Xs], [Y|Ys]) :- !, X =~= Y, Xs =~= Ys.
'=~='(X, Y) :-
    (   abs(X - Y) < 100 * 0.000000000001
    ->  true
    ;   abs(X - Y) < 0.00001 * max(abs(X), abs(Y))
    ).

file_path(File, Path) :-
    lgt_dir(Dir),
    (   ( sub_atom(File, 0, 1, _, '/') ; atom_concat(Dir, _, File) )
    ->  Path = File
    ;   atom_concat(Dir, File, Path)
    ).

clean_file(File) :- clean_file(File, _).

clean_file(File, Path) :-
    file_path(File, Path),
    lgt_close_file(Path).

clean_file(Alias, File, Path) :-
    (   catch(stream_property(S, alias(Alias)), _, fail)
    ->  close(S)
    ;   true
    ),
    clean_file(File, Path).

lgt_close_file(Path) :-
    catch(stream_property(S, file_name(Path)), _, fail),
    catch(close(S), _, true),
    fail.
lgt_close_file(_).

suppress_text_output :-
    open('/dev/null', write, S, [type(text)]),
    lgt_track(S),
    set_output(S).

suppress_binary_output :-
    open('/dev/null', write, S, [type(binary)]),
    lgt_track(S),
    set_output(S).

set_text_input(Alias, Contents, Options) :-
    clean_file(Alias, 'test_input.text', Path),
    open(Path, write, W, [type(text)|Options]),
    write_text_contents(W, Contents),
    close(W),
    open(Path, read, R, [type(text), alias(Alias)|Options]),
    lgt_track(R).

set_text_input(Alias, Contents) :- set_text_input(Alias, Contents, []).

set_text_input(Contents) :-
    clean_file('test_input.text', Path),
    open(Path, write, W, [type(text)]),
    write_text_contents(W, Contents),
    close(W),
    open(Path, read, R, [type(text)]),
    lgt_track(R),
    set_input(R).

check_text_input(Alias, Expected) :-
    get_text_contents(Alias, Expected, Contents),
    clean_text_input,
    Expected == Contents.

check_text_input(Expected) :-
    current_input(S),
    get_text_contents(S, Expected, Contents),
    clean_text_input,
    Expected == Contents.

text_input_assertion(Alias, Expected, Expected == Contents) :-
    get_text_contents(Alias, Expected, Contents),
    clean_text_input.

text_input_assertion(Expected, Expected == Contents) :-
    current_input(S),
    get_text_contents(S, Expected, Contents),
    clean_text_input.

clean_text_input :- clean_file('test_input.text', _).

set_binary_input(Alias, Bytes, Options) :-
    clean_file(Alias, 'test_input.binary', Path),
    open(Path, write, W, [type(binary)|Options]),
    write_binary_contents(Bytes, W),
    close(W),
    open(Path, read, R, [type(binary), alias(Alias)|Options]),
    lgt_track(R).

set_binary_input(Alias, Bytes) :- set_binary_input(Alias, Bytes, []).

set_binary_input(Bytes) :-
    clean_file('test_input.binary', Path),
    open(Path, write, W, [type(binary)]),
    write_binary_contents(Bytes, W),
    close(W),
    open(Path, read, R, [type(binary)]),
    lgt_track(R),
    set_input(R).

check_binary_input(Alias, Expected) :-
    get_binary_contents(Alias, Expected, Contents),
    clean_binary_input,
    Expected == Contents.

check_binary_input(Expected) :-
    current_input(S),
    get_binary_contents(S, Expected, Contents),
    clean_binary_input,
    Expected == Contents.

binary_input_assertion(Alias, Expected, Expected == Contents) :-
    get_binary_contents(Alias, Expected, Contents),
    clean_binary_input.

binary_input_assertion(Expected, Expected == Contents) :-
    current_input(S),
    get_binary_contents(S, Expected, Contents),
    clean_binary_input.

clean_binary_input :- clean_file('test_input.binary', _).

set_text_output(Alias, Contents, Options) :-
    clean_file(Alias, 'test_output.text', Path),
    open(Path, write, S, [type(text), alias(Alias)|Options]),
    lgt_track(S),
    write_text_contents(S, Contents).

set_text_output(Alias, Contents) :- set_text_output(Alias, Contents, []).

set_text_output(Contents) :-
    clean_file('test_output.text', Path),
    open(Path, write, S, [type(text)]),
    lgt_track(S),
    write_text_contents(S, Contents),
    set_output(S).

check_text_output(Alias, Expected, Options) :-
    text_output_assertion(Alias, Expected, Options, Assertion),
    call(Assertion).

check_text_output(Alias, Expected) :- check_text_output(Alias, Expected, []).

check_text_output(Expected) :-
    text_output_assertion(Expected, Assertion),
    call(Assertion).

text_output_assertion(Alias, Expected, Options, Expected == Contents) :-
    close(Alias),
    file_path('test_output.text', Path),
    open(Path, read, In, Options),
    get_text_contents(In, Expected, Contents),
    clean_text_output.

text_output_assertion(Alias, Expected, Assertion) :-
    text_output_assertion(Alias, Expected, [], Assertion).

text_output_assertion(Expected, Expected == Contents) :-
    current_output(Out),
    close(Out),
    file_path('test_output.text', Path),
    open(Path, read, In),
    get_text_contents(In, Expected, Contents),
    clean_text_output.

text_output_contents(Alias, Contents, Options) :-
    close(Alias),
    file_path('test_output.text', Path),
    open(Path, read, In, Options),
    get_text_contents(In, Contents),
    clean_text_output.

text_output_contents(Alias, Contents) :- text_output_contents(Alias, Contents, []).

text_output_contents(Contents) :-
    current_output(Out),
    close(Out),
    file_path('test_output.text', Path),
    open(Path, read, In),
    get_text_contents(In, Contents),
    clean_text_output.

clean_text_output :- clean_file('test_output.text', _).

set_binary_output(Alias, Bytes, Options) :-
    clean_file(Alias, 'test_output.binary', Path),
    open(Path, write, S, [type(binary), alias(Alias)|Options]),
    lgt_track(S),
    write_binary_contents(Bytes, S).

set_binary_output(Alias, Bytes) :- set_binary_output(Alias, Bytes, []).

set_binary_output(Bytes) :-
    clean_file('test_output.binary', Path),
    open(Path, write, S, [type(binary)]),
    lgt_track(S),
    write_binary_contents(Bytes, S),
    set_output(S).

check_binary_output(Alias, Expected) :-
    binary_output_assertion(Alias, Expected, Assertion),
    call(Assertion).

check_binary_output(Expected) :-
    binary_output_assertion(Expected, Assertion),
    call(Assertion).

binary_output_assertion(Alias, Expected, Expected == Contents) :-
    close(Alias),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Expected, Contents),
    clean_binary_output.

binary_output_assertion(Expected, Expected == Contents) :-
    current_output(Out),
    close(Out),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Expected, Contents),
    clean_binary_output.

binary_output_contents(Alias, Contents) :-
    close(Alias),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Contents),
    clean_binary_output.

binary_output_contents(Contents) :-
    current_output(Out),
    close(Out),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Contents),
    clean_binary_output.

clean_binary_output :- clean_file('test_output.binary', _).

create_text_file(File, Contents, Options) :-
    file_path(File, Path),
    open(Path, write, S, Options),
    write_text_contents(S, Contents),
    close(S).

create_text_file(File, Contents) :- create_text_file(File, Contents, []).

create_binary_file(File, Bytes) :-
    file_path(File, Path),
    open(Path, write, S, [type(binary)]),
    write_binary_contents(Bytes, S),
    close(S).

check_text_file(File, Expected, Options) :-
    text_file_assertion(File, Expected, Options, Assertion),
    call(Assertion).

check_text_file(File, Expected) :- check_text_file(File, Expected, []).

text_file_assertion(File, Expected, Options, Expected == Contents) :-
    file_path(File, Path),
    open(Path, read, S, Options),
    get_text_contents(S, Expected, Contents).

text_file_assertion(File, Expected, Assertion) :-
    text_file_assertion(File, Expected, [], Assertion).

closed_input_stream(R, Options) :-
    file_path(temporary_file, Path),
    open(Path, write, W),
    close(W),
    open(Path, read, R, Options),
    close(R).

closed_output_stream(W, Options) :-
    file_path(temporary_file, Path),
    open(Path, write, W, Options),
    close(W).

stream_position(Position) :-
    file_path(temporary_file, Path),
    open(Path, write, S),
    stream_property(S, position(Position)),
    close(S).

assertion(Goal) :- assertion(Goal, Goal).

assertion(Assertion, Goal) :-
    (   \+ \+ catch(Goal, Error, throw(assertion_error(Assertion, Error)))
    ->  true
    ;   throw(assertion_failure(Assertion))
    ).

variant(T1, T2) :-
    \+ \+ ( subsumes_term(T1, T2), subsumes_term(T2, T1) ).

write_text_contents(S, Contents) :-
    (   atom(Contents)
    ->  write(S, Contents)
    ;   write_text_list(Contents, S)
    ).

write_text_list([], _).
write_text_list([A|As], S) :- write(S, A), write_text_list(As, S).

get_text_contents(S, Expected, Contents) :-
    atom_length(Expected, Length),
    Limit is Length + 1,
    get_chars(S, Chars, Limit),
    atom_chars(Contents, Chars).

get_chars(S, Chars, Countdown) :-
    get_char(S, C),
    (   C == end_of_file
    ->  Chars = [],
        close(S)
    ;   Countdown =< 0
    ->  Chars = []
    ;   Chars = [C|Rest],
        Next is Countdown - 1,
        get_chars(S, Rest, Next)
    ).

get_text_contents(S, Chars) :-
    get_char(S, C),
    (   C == end_of_file
    ->  Chars = [],
        close(S)
    ;   Chars = [C|Rest],
        get_text_contents(S, Rest)
    ).

write_binary_contents([], _).
write_binary_contents([B|Bs], S) :- put_byte(S, B), write_binary_contents(Bs, S).

get_binary_contents(S, Expected, Bytes) :-
    length(Expected, Length),
    Limit is Length + 1,
    get_bytes(S, Bytes, Limit).

get_bytes(S, Bytes, Countdown) :-
    get_byte(S, B),
    (   B == -1
    ->  close(S),
        Bytes = []
    ;   Countdown =< 0
    ->  Bytes = []
    ;   Bytes = [B|Rest],
        Next is Countdown - 1,
        get_bytes(S, Rest, Next)
    ).

get_binary_contents(S, Bytes) :-
    get_byte(S, B),
    (   B == -1
    ->  close(S),
        Bytes = []
    ;   Bytes = [B|Rest],
        get_binary_contents(S, Rest)
    ).

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

max_min_integer_as_atom(Flag, Value, Atom) :- (current_prolog_flag(bounded, true) -> current_prolog_flag(Flag, Value), number_codes(Value, Codes), atom_codes(Atom, Codes) ; Value = 0, Atom = '0').

% iso_read_term_3_01
?- once((set_text_input('term1. term2. ...'), read(T), T == term1, text_input_assertion(' term2. ...', Assertion))), Assertion.
   true.

% iso_read_term_3_02
?- once((set_text_input(in, 'term1. term2. ...'), read(in, term1), text_input_assertion(in, ' term2. ...', Assertion))), Assertion.
   true.

% iso_read_term_3_03
?- set_text_input(in, ['foo(A+Roger,A+_). ','term2. ...']), read_term(in, T, [variables(VL),variable_names(VN),singletons(VS)]), text_input_assertion(in, ' term2. ...', Assertion), assertion(variant(T, foo(X1+X2,X1+X3))), T = foo(X1+X2,X1+X3), assertion(VL == [X1,X2,X3]), assertion(VN == ['A'=X1,'Roger'=X2]), assertion(VS == ['Roger'=X2]), assertion(Assertion).
   true.

% iso_read_term_3_04
?- once((set_text_input('3.1.  term2. ...'), \+ read(4.1), text_input_assertion('  term2. ...', Assertion))), Assertion.
   true.

% iso_read_term_3_05
?- once((set_text_input('foo 123. term2. ...'), catch(read(_T),error(syntax_error(_),_),true), text_input_assertion(' term2. ...', Assertion))), Assertion.
   true.

% iso_read_term_3_06
?- set_text_input('3.1'), catch(read(_T),error(syntax_error(_),_),true).
   true.

% sics_read_term_3_07
?- set_text_input('foo( bar). '), read_term(T, [singletons(S)]), assertion(T == foo(bar)), assertion(S == []).
   true.

% sics_read_term_3_08
?- read(_, _).
   error(instantiation_error).

% sics_read_term_3_09
?- read_term(user_input, _, _).
   error(instantiation_error).

% sics_read_term_3_10
?- set_text_input('a. '), current_input(S), read_term(S, _, [variables(_)|_]).
   error(instantiation_error).

% sics_read_term_3_11
?- read_term(user_input,_,[variables(_),_]).
   error(instantiation_error).

% sics_read_term_3_12
?- read(foo, _).
   error(domain_error(stream_or_alias,foo))
|  error(existence_error(stream,foo)).

% sics_read_term_3_13
?- read_term(user_input, _, bar).
   error(type_error(list,bar)).

% sics_read_term_3_14
?- set_text_input('a. '), current_input(S), read_term(S, _, [bar]).
   error(domain_error(read_option,bar)).

% sics_read_term_3_15
?- read_term(user_output, _, []).
   error(permission_error(input,stream,user_output)).

% sics_read_term_3_16
?- once((set_text_input(''), read(T), assertion(T == end_of_file), current_input(Stream), stream_property(Stream, end_of_stream(Value)))), Value == past.
   true.

% sics_read_term_3_17
?- closed_input_stream(S, []), read_term(S, _, []).
   error(existence_error(stream,S)).

% sics_read_term_3_18
?- closed_output_stream(S, []), read_term(S, _, []).
   error(existence_error(stream,S)).

% sics_read_term_3_19
?- set_binary_input([]), current_input(S), read_term(_, []).
   error(permission_error(input,binary_stream,S)).

% sics_read_term_3_20
?- set_binary_input([]), current_input(S), read(_).
   error(permission_error(input,binary_stream,S)).

% sics_read_term_3_21
?- once((set_text_input(in, '', [eof_action(error)]), get_code(in, _), catch(read_term(in, _, []),error(permission_error(input,past_end_of_stream,_),_),true), stream_property(Stream, alias(in)), stream_property(Stream, end_of_stream(Value)))), Value == past.
   true.

% sics_read_term_3_22
?- once((set_text_input('\'a.'), catch(read_term(_,[]),error(syntax_error(_),_),true), text_input_assertion('', Assertion))), Assertion.
   true.

% sics_read_term_3_23
?- once((max_min_integer_as_atom(max_integer, Integer, Atom), set_text_input([Atom, '. ']), read(X))), X == Integer.
   true.

% sics_read_term_3_24
?- once((max_min_integer_as_atom(min_integer, Integer, Atom), set_text_input([Atom, '. ']), read(X))), X == Integer.
   true.

:- clean_text_input, clean_binary_input, clean_text_output.

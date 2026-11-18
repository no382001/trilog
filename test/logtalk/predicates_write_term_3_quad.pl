% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- multifile(portray/1).
:- dynamic(portray/1).

portray(Atom) :- atom(Atom), write(Atom), write(Atom).
portray(Float) :- float(Float), Integer is truncate(Float), write(Integer).
max_depth_option_supported :- current_logtalk_flag(prolog_dialect, Dialect), Dialect \== b, Dialect \== cx, Dialect \== ji.
portrayed_option_supported :- current_logtalk_flag(prolog_dialect, Dialect), Dialect \== b, Dialect \== cx, Dialect \== ji, Dialect \== tau, Dialect \== yap.

% iso_write_term_3_001
?- once((set_text_output(out, ''), write_term(out, [1,2,3], []), text_output_assertion(out, '[1,2,3]', Assertion))), Assertion.
   true.

% iso_write_term_3_002
?- once((set_text_output(out, ''), write_canonical(out, [1,2,3]), text_output_assertion(out, '\'.\'(1,\'.\'(2,\'.\'(3,[])))', Assertion))), Assertion.
   true.

% iso_write_term_3_003
?- once((set_text_output(out, ''), write_term(out, '1<2', []), text_output_assertion(out, '1<2', Assertion))), Assertion.
   true.

% iso_write_term_3_004
?- once((set_text_output(out, ''), writeq(out, '1<2'), text_output_assertion(out, '\'1<2\'', Assertion))), Assertion.
   true.

% iso_write_term_3_005
?- once((set_text_output(out, ''), writeq(out, '$VAR'(0)), text_output_assertion(out, 'A', Assertion))), Assertion.
   true.

% iso_write_term_3_006
?- once((set_text_output(out, ''), write_term(out, '$VAR'(1), [numbervars(false)]), text_output_assertion(out, '$VAR(1)', Assertion))), Assertion.
   true.

% iso_write_term_3_007
?- once((set_text_output(out, ''), write_term(out, '$VAR'(51), [numbervars(true)]), text_output_assertion(out, 'Z1', Assertion))), Assertion.
   true.

% sics_write_term_3_008
?- write(_S, foo).
   error(instantiation_error).

% sics_write_term_3_009
?- write_term(foo, _Opts).
   error(instantiation_error).

% sics_write_term_3_010
?- write_term(user_output, foo, _Opts).
   error(instantiation_error).

% sics_write_term_3_011
?- write_term(foo, [quoted(true)|_Opts]).
   error(instantiation_error).

% sics_write_term_3_012
?- write_term(user_output, foo, [quoted(true)|_Opts]).
   error(instantiation_error).

% sics_write_term_3_013
?- write_term(foo, [quoted(true),_Opts]).
   error(instantiation_error).

% sics_write_term_3_014
?- write_term(user_output, foo, [quoted(true),_Opts]).
   error(instantiation_error).

% sics_write_term_3_015
?- write_term(user_output, 1, 2).
   error(type_error(list,2)).

% sics_write_term_3_016
?- write_term('', [quoted(true)|foo]).
   error(type_error(list,[quoted(true)|foo]))
|  error(type_error(list,foo)).

% sics_write_term_3_017
?- write(foo, 1).
   error(domain_error(stream_or_alias,foo))
|  error(existence_error(stream,foo)).

% sics_write_term_3_018
?- write_term(1, [quoted(true),foo]).
   error(domain_error(write_option,foo)).

% sics_write_term_3_019
?- closed_input_stream(S, []), write(S, a).
   error(existence_error(stream,S)).

% sics_write_term_3_020
?- closed_output_stream(S, []), write(S, a).
   error(existence_error(stream,S)).

% sics_write_term_3_021
?- current_input(S), write(S, a).
   error(permission_error(output,stream,S)).

% sics_write_term_3_022
?- set_binary_output([]), current_output(S), write(a).
   error(permission_error(output,binary_stream,S)).

% sics_write_term_3_103
?- suppress_text_output, write_term(1, [quoted(_)]).
   error(instantiation_error).

% sics_write_term_3_104
?- suppress_text_output, write_term(1, [quoted(fail)]).
   error(domain_error(write_option,quoted(fail))).

% sics_write_term_3_105
?- suppress_text_output, write_term(1, [ignore_ops(_)]).
   error(instantiation_error).

% sics_write_term_3_106
?- suppress_text_output, write_term(1, [ignore_ops(fail)]).
   error(domain_error(write_option,ignore_ops(fail))).

% sics_write_term_3_107
?- suppress_text_output, write_term(1, [numbervars(_)]).
   error(instantiation_error).

% sics_write_term_3_108
?- suppress_text_output, write_term(1, [numbervars(fail)]).
   error(domain_error(write_option,numbervars(fail))).

% sics_write_term_3_109
?- suppress_text_output, write_term(1, [variable_names(_)]).
   error(instantiation_error).

% sics_write_term_3_110
?- suppress_text_output, write_term(1, [variable_names(a)]).
   error(domain_error(write_option,variable_names(a))).

% sics_write_term_3_111
?- suppress_text_output, write_term(1, [variable_names([_='A'])]).
   error(instantiation_error).

% sics_write_term_3_112
?- suppress_text_output, write_term(1, [variable_names(['A'=_|_])]).
   error(instantiation_error).

:- clean_binary_output, clean_text_output, clean_text_input.

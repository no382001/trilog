% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_set_prolog_flag_2_01
?- lgt_run((set_prolog_flag(unknown, fail), current_prolog_flag(unknown, fail))).
   true.

% iso_set_prolog_flag_2_02
?- lgt_run(set_prolog_flag(_X, off)).
   error(instantiation_error).

% iso_set_prolog_flag_2_03
?- lgt_run(set_prolog_flag(5, decimals)).
   error(type_error(atom,5)).

% iso_set_prolog_flag_2_04
?- lgt_run(set_prolog_flag(date, 'July 1999')).
   error(domain_error(prolog_flag,date)).

% iso_set_prolog_flag_2_05
?- lgt_run(set_prolog_flag(debug, trace)).
   error(domain_error(flag_value,debug+trace)).

% eddbali_set_prolog_flag_2_06
?- lgt_run(set_prolog_flag(max_arity, 40)).
   error(permission_error(modify,flag,max_arity)).

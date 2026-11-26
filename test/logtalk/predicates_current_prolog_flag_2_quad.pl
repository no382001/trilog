% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').
:- discontiguous([ succeeds/1, fails/1, throws/2 ]).

% iso_current_prolog_flag_2_01
?- current_prolog_flag(debug, off).
   true.

% iso_current_prolog_flag_2_02
?- once(current_prolog_flag(bounded, Bounded)), (Bounded == true ; Bounded == false).
   true.

% iso_current_prolog_flag_2_03
?- current_prolog_flag(bounded, true) -> current_prolog_flag(max_integer, MaxInteger), integer(MaxInteger) ; true.
   true.

% iso_current_prolog_flag_2_04
?- current_prolog_flag(bounded, true) -> current_prolog_flag(min_integer, MinInteger), integer(MinInteger) ; true.
   true.

% iso_current_prolog_flag_2_05
?- once(current_prolog_flag(integer_rounding_function, IntegerRoundingFunction)), (IntegerRoundingFunction == down ; IntegerRoundingFunction == toward_zero).
   true.

% iso_current_prolog_flag_2_06
?- once(current_prolog_flag(char_conversion, CharConversion)), (CharConversion == on ; CharConversion == off).
   true.

% iso_current_prolog_flag_2_07
?- once(current_prolog_flag(debug, Debug)), (Debug == on ; Debug == off).
   true.

% iso_current_prolog_flag_2_08
?- current_prolog_flag(max_arity, MaxArity), (MaxArity == unbounded -> true ; integer(MaxArity), MaxArity > 0).
   true.

% iso_current_prolog_flag_2_09
?- once(current_prolog_flag(unknown, Unknown)), (Unknown == error ; Unknown == fail ; Unknown == warning).
   true.

% iso_current_prolog_flag_2_10
?- once(current_prolog_flag(double_quotes, DoubleQuotes)), (DoubleQuotes == chars ; DoubleQuotes == codes ; DoubleQuotes == atom).
   true.

% iso_current_prolog_flag_2_11
?- current_prolog_flag(5, _V).
   error(type_error(atom,5)).

% eddbali_current_prolog_flag_2_12
?- set_prolog_flag(unknown, warning), current_prolog_flag(unknown, warning).
   true.

% eddbali_current_prolog_flag_2_13
?- set_prolog_flag(unknown, warning), current_prolog_flag(unknown,error).
   false.

% eddbali_current_prolog_flag_2_14
?- current_prolog_flag(warning,_).
   error(domain_error(prolog_flag,warning)).

% eddbali_current_prolog_flag_2_15
?- current_prolog_flag(1+2, flag).
   error(type_error(atom,1+2)).

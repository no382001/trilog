% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

twice(!) :- write('C ').
twice(true) :- write('Moss ').
goal((twice(_), !)).
goal(write('Three ')).

% iso_cut_0_01
?- lgt_run(!).
   true.

% iso_cut_0_02
?- lgt_run((!,fail;true)).
   false.

% iso_cut_0_03
?- lgt_run((call(!),fail;true)).
   true.

% iso_cut_0_04
?- lgt_run((once((set_text_output(''), \+ (twice(_), !, write('Forwards '), fail), text_output_assertion('C Forwards ', Assertion))), Assertion)).
   true.

% iso_cut_0_05
?- lgt_run((once((set_text_output(''), \+ ((!; write('No ')), write('Cut disjunction '), fail), text_output_assertion('Cut disjunction ', Assertion))), Assertion)).
   true.

% iso_cut_0_06
?- lgt_run((once((set_text_output(''), \+ (twice(_), (write('No '); !), write('Cut '), fail), text_output_assertion('C No Cut Cut ', Assertion))), Assertion)).
   true.

% iso_cut_0_07
?- lgt_run((once((set_text_output(''), \+ (twice(_), (!, fail; write('No '))), text_output_assertion('C ', Assertion))), Assertion)).
   true.

% iso_cut_0_08
?- lgt_run((once((set_text_output(''), \+ (twice(X), call(X), write('Forwards '), fail), text_output_assertion('C Forwards Moss Forwards ', Assertion))), Assertion)).
   true.

% iso_cut_0_09
?- lgt_run((once((set_text_output(''), \+ (goal(X), call(X), write('Forwards '), fail), text_output_assertion('C Forwards Three Forwards ', Assertion))), Assertion)).
   true.

% iso_cut_0_10
?- lgt_run((once((set_text_output(''), \+ (twice(_), \+(\+(!)), write('Forwards '), fail), text_output_assertion('C Forwards Moss Forwards ', Assertion))), Assertion)).
   true.

% iso_cut_0_11
?- lgt_run((once((set_text_output(''), \+ (twice(_), once(!), write('Forwards '), fail), text_output_assertion('C Forwards Moss Forwards ', Assertion))), Assertion)).
   true.

% iso_cut_0_12
?- lgt_run((once((set_text_output(''), \+ (twice(_), call(!), write('Forwards '), fail), text_output_assertion('C Forwards Moss Forwards ', Assertion))), Assertion)).
   true.

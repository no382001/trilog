% set_prolog_flag/2 and current_prolog_flag/2 (ISO 8.17).

:- consult('test/quad/files/dq_flag.pl').

?- dq_codes(C), dq_atom(A), dq_chars(Cs).
   C = [97,98], A = ab, Cs = [a,b].

?- current_prolog_flag(double_quotes, V).
   V = chars.

?- set_prolog_flag(double_quotes, codes), atom_to_term('"ab"', T, _), current_prolog_flag(double_quotes, V), set_prolog_flag(double_quotes, chars).
   T = [97,98], V = codes.

?- set_prolog_flag(double_quotes, atom), atom_to_term('"ab"', T, _), set_prolog_flag(double_quotes, chars).
   T = ab.

?- set_prolog_flag(unknown, fail), ( no_such_predicate_q -> R = yes ; R = no ), current_prolog_flag(unknown, V), set_prolog_flag(unknown, error).
   R = no, V = fail.

?- set_prolog_flag(unknown, warning), ( no_such_predicate_q -> R = yes ; R = no ), set_prolog_flag(unknown, error).
   R = no.

?- catch(no_such_predicate_q, error(E, _), true).
   E = existence_error(procedure, no_such_predicate_q/0).

?- set_prolog_flag(debug, on), current_prolog_flag(debug, V), set_prolog_flag(debug, off).
   V = on.

?- set_prolog_flag(char_conversion, on), current_prolog_flag(char_conversion, V), set_prolog_flag(char_conversion, off).
   V = on.

?- set_prolog_flag(_, chars).
   error(instantiation_error).

?- set_prolog_flag(double_quotes, _).
   error(instantiation_error).

?- set_prolog_flag(1, chars).
   error(type_error(atom, 1)).

?- set_prolog_flag(no_such_flag, on).
   error(domain_error(prolog_flag, no_such_flag)).

?- set_prolog_flag(double_quotes, bytes).
   error(domain_error(flag_value, double_quotes+bytes)).

?- set_prolog_flag(unknown, 1).
   error(domain_error(flag_value, unknown+1)).

?- set_prolog_flag(bounded, false).
   error(permission_error(modify, flag, bounded)).

?- catch(set_prolog_flag(bounded, false), error(_, C), true).
   C = set_prolog_flag/2.

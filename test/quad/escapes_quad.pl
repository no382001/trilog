% Escape sequences in quoted text: octal \NNN\, hex \xHH\, the control and
% meta escapes; anything else after a backslash is a syntax error.

?- atom_codes('\141\', Cs).
   Cs = [97].

?- atom_codes('\x61\', Cs).
   Cs = [97].

?- atom_codes('\x61\\x62\', Cs).
   Cs = [97,98].

?- atom_codes('a\x41\b', Cs).
   Cs = [97,65,98].

?- atom_codes('\101\\102\', Cs).
   Cs = [65,66].

?- atom_codes('\\', Cs).
   Cs = [92].

?- atom_codes('\'', Cs).
   Cs = [39].

?- atom_codes('\"', Cs).
   Cs = [34].

?- atom_codes('\`', Cs).
   Cs = [96].

?- atom_codes('\a\b\f\n\r\t\v', Cs).
   Cs = [7,8,12,10,13,9,11].

?- atom_codes('\7\', Cs).
   Cs = [7].

?- atom_codes('\33\', Cs).
   Cs = [27].

?- atom_codes('\177\', Cs).
   Cs = [127].

?- atom_codes('\x1f\', Cs).
   Cs = [31].

?- atom_codes('\x7A\', Cs).
   Cs = [122].

?- X = 0'\x41\.
   X = 65.

?- X = 0'\101\.
   X = 65.

?- X = 0'\\.
   X = 92.

?- X = 0'\'.
   X = 39.

?- X = 0'''.
   X = 39.

?- X = 0'\n.
   X = 10.

?- "\x61\b" = Cs.
   Cs = [a,b].

% --- anything else is a syntax error ---

?- catch(term_to_atom(_, '\'\\d\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\e\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\z\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\N\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\9\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\u1\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\^J\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\ \''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\141\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\x61\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '\'\\xg\\\''), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '0\'\\d'), error(syntax_error(_), _), true).
   true.

?- catch(term_to_atom(_, '"\\z"'), error(syntax_error(_), _), true).
   true.

% --- writeq/1 writes control characters as escapes ---

?- with_output_to(chars(Cs), writeq('\7\')).
   Cs = "'\\a'".

?- with_output_to(chars(Cs), writeq('\33\')).
   Cs = "'\\33\\'".

?- with_output_to(chars(Cs), writeq('\177\')).
   Cs = "'\\177\\'".

?- with_output_to(chars(Cs), writeq('a\1\b')).
   Cs = "'a\\1\\b'".

?- with_output_to(chars(Cs), writeq('\t')).
   Cs = "'\\t'".

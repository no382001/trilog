% writeq/1 with operators expected output from Scryer Prolog.

?- with_output_to(chars(Cs), writeq(a=b)).
   Cs = "a=b".

?- with_output_to(chars(Cs), writeq(a+b*c)).
   Cs = "a+b*c".

?- with_output_to(chars(Cs), writeq((a+b)*c)).
   Cs = "(a+b)*c".

?- with_output_to(chars(Cs), writeq(a-(b-c))).
   Cs = "a-(b-c)".

?- with_output_to(chars(Cs), writeq((a-b)-c)).
   Cs = "a-b-c".

?- with_output_to(chars(Cs), writeq(a^b^c)).
   Cs = "a^b^c".

?- with_output_to(chars(Cs), writeq((a^b)^c)).
   Cs = "(a^b)^c".

?- with_output_to(chars(Cs), writeq(-a)).
   Cs = "-a".

?- with_output_to(chars(Cs), writeq(-(-a))).
   Cs = "- -a".

?- with_output_to(chars(Cs), writeq(-(1))).
   Cs = "- (1)".

?- with_output_to(chars(Cs), writeq(-(-1))).
   Cs = "- -1".

?- with_output_to(chars(Cs), writeq(-(-(1)))).
   Cs = "- - (1)".

?- with_output_to(chars(Cs), writeq(- (1.5))).
   Cs = "- (1.5)".

?- with_output_to(chars(Cs), writeq(-(1^2))).
   Cs = "- (1^2)".

?- with_output_to(chars(Cs), writeq(-(a^b))).
   Cs = "- (a^b)".

?- with_output_to(chars(Cs), writeq(1 - -1)).
   Cs = "1- -1".

?- with_output_to(chars(Cs), writeq(a-(-1))).
   Cs = "a- -1".

?- with_output_to(chars(Cs), writeq(a-(-(1)))).
   Cs = "a- - (1)".

?- with_output_to(chars(Cs), writeq(1+2 mod 3)).
   Cs = "1+2 mod 3".

?- with_output_to(chars(Cs), writeq((1+2) mod 3)).
   Cs = "(1+2)mod 3".

?- with_output_to(chars(Cs), writeq(a mod b)).
   Cs = "a mod b".

?- with_output_to(chars(Cs), writeq(f((a,b)))).
   Cs = "f((a,b))".

?- with_output_to(chars(Cs), writeq([(a,b)])).
   Cs = "[(a,b)]".

?- with_output_to(chars(Cs), writeq(f(a,b))).
   Cs = "f(a,b)".

?- with_output_to(chars(Cs), writeq([a,b,c])).
   Cs = "[a,b,c]".

?- with_output_to(chars(Cs), writeq([a|b])).
   Cs = "[a|b]".

?- with_output_to(chars(Cs), writeq('[]')).
   Cs = "[]".

?- with_output_to(chars(Cs), writeq(f(;,'|','[]'))).
   Cs = "f(;,'|',[])".

?- with_output_to(chars(Cs), writeq(-(-))).
   Cs = "- (-)".

?- with_output_to(chars(Cs), writeq((-)-(-))).
   Cs = "(-)-(-)".

?- with_output_to(chars(Cs), writeq(f(-))).
   Cs = "f(-)".

?- with_output_to(chars(Cs), writeq([-])).
   Cs = "[-]".

?- with_output_to(chars(Cs), writeq(\+a)).
   Cs = "\\+a".

?- with_output_to(chars(Cs), writeq(\+ (a,b))).
   Cs = "\\+ (a,b)".

?- with_output_to(chars(Cs), writeq(\+ \+a)).
   Cs = "\\+ \\+a".

?- with_output_to(chars(Cs), writeq((a:-b,c;d->e))).
   Cs = "a:-b,c;d->e".

?- with_output_to(chars(Cs), writeq({a,b})).
   Cs = "{a,b}".

?- with_output_to(chars(Cs), writeq('{}'(x))).
   Cs = "{x}".

?- with_output_to(chars(Cs), writeq(1 = -1)).
   Cs = "1= -1".

?- with_output_to(chars(Cs), writeq(2* -1)).
   Cs = "2* -1".

?- with_output_to(chars(Cs), writeq(- - a)).
   Cs = "- -a".

?- with_output_to(chars(Cs), writeq(f(-1))).
   Cs = "f(-1)".

?- with_output_to(chars(Cs), writeq(1-2-3)).
   Cs = "1-2-3".

?- with_output_to(chars(Cs), writeq(1-(2-3))).
   Cs = "1-(2-3)".

?- with_output_to(chars(Cs), writeq((a,b))).
   Cs = "a,b".

?- with_output_to(chars(Cs), writeq((a:-b))).
   Cs = "a:-b".

?- with_output_to(chars(Cs), writeq(f(:-))).
   Cs = "f(:-)".

?- with_output_to(chars(Cs), writeq((a=b)=c)).
   Cs = "(a=b)=c".

?- with_output_to(chars(Cs), writeq(a=(b=c))).
   Cs = "a=(b=c)".

?- with_output_to(chars(Cs), writeq(- (- (a)))).
   Cs = "- -a".

?- with_output_to(chars(Cs), writeq(\ (a*b))).
   Cs = "\\ (a*b)".

?- with_output_to(chars(Cs), writeq(-{a})).
   Cs = "-{a}".

?- with_output_to(chars(Cs), writeq(- (a*b))).
   Cs = "- (a*b)".

?- with_output_to(chars(Cs), writeq(-((a,b)))).
   Cs = "- (a,b)".

?- with_output_to(chars(Cs), writeq('hello world'=x)).
   Cs = "'hello world'=x".

?- with_output_to(chars(Cs), writeq(- 'a b')).
   Cs = "-'a b'".

?- with_output_to(chars(Cs), writeq(f(a=b))).
   Cs = "f(a=b)".

?- with_output_to(chars(Cs), writeq([a=b])).
   Cs = "[a=b]".

?- with_output_to(chars(Cs), writeq('$VAR'(1)+'$VAR'(27))).
   Cs = "B+B1".

?- with_output_to(chars(Cs), writeq(a- - - b)).
   Cs = "a- - -b".

?- with_output_to(chars(Cs), writeq(x is -1)).
   Cs = "x is-1".

?- with_output_to(chars(Cs), writeq(f(:-(a,b)))).
   Cs = "f((a:-b))".

?- with_output_to(chars(Cs), writeq([:-(a,b)])).
   Cs = "[(a:-b)]".

?- with_output_to(chars(Cs), writeq(=(a, \+(b)))).
   Cs = "a=(\\+b)".

?- with_output_to(chars(Cs), writeq(:-(a, :-(b, c)))).
   Cs = "a:-(b:-c)".

?- with_output_to(chars(Cs), writeq(-(-(-(1))))).
   Cs = "- - - (1)".

?- with_output_to(chars(Cs), writeq(+(1))).
   Cs = "+1".

?- with_output_to(chars(Cs), writeq(-(a)-b)).
   Cs = "-a-b".

?- with_output_to(chars(Cs), writeq(1-(-(a)))).
   Cs = "1- -a".

?- with_output_to(chars(Cs), writeq((a,b,c))).
   Cs = "a,b,c".

?- with_output_to(chars(Cs), writeq({(:-)})).
   Cs = "{:-}".

?- with_output_to(chars(Cs), writeq(- (1)+2)).
   Cs = "- (1)+2".

?- with_output_to(chars(Cs), writeq((- (1))^2)).
   Cs = "(- (1))^2".

?- with_output_to(chars(Cs), writeq(+(1^2))).
   Cs = "+1^2".

?- with_output_to(chars(Cs), writeq(+(a^b))).
   Cs = "+a^b".

?- with_output_to(chars(Cs), writeq(\(a^b))).
   Cs = "\\a^b".

?- with_output_to(chars(Cs), writeq(-(a**b))).
   Cs = "- (a**b)".

?- with_output_to(chars(Cs), writeq(-(-(a)^b))).
   Cs = "- ((-a)^b)".

% --- write_canonical/1 ignores operators ---

?- with_output_to(chars(Cs), write_canonical(a+b*c)).
   Cs = "+(a,*(b,c))".

?- with_output_to(chars(Cs), write_canonical(- (1))).
   Cs = "-(1)".

?- with_output_to(chars(Cs), write_canonical([a,b])).
   Cs = "'.'(a,'.'(b,[]))".

% --- write/1 leaves atoms unquoted ---

?- with_output_to(chars(Cs), write('hello world'=x)).
   Cs = "hello world=x".

?- with_output_to(chars(Cs), write(f(a,'B'))).
   Cs = "f(a,B)".

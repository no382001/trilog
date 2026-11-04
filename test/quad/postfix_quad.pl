% Postfix operators (xf, yf): reading, write_canonical and writeq; expected
% output from Scryer Prolog.

:- op(200, xf, @@).
:- op(200, yf, +++).
:- op(9, fy, fy).
:- op(9, yf, yf).
:- op(9, xf, xf).
:- op(9, xfy, xfy).
:- op(700, xf, done).

?- term_to_atom(_T, 'a @@'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "@@(a)", W = "a@@".

?- term_to_atom(_T, 'a +++ +++'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "+++(+++(a))", W = "a+++ +++".

?- catch(term_to_atom(_, 'a @@ @@'), error(syntax_error(_), _), true).
   true.

?- term_to_atom(_T, '1 + 2 @@'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "+(1,@@(2))", W = "1+2@@".

?- term_to_atom(_T, '(1+2) @@'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "@@(+(1,2))", W = "(1+2)@@".

?- term_to_atom(_T, '- a +++'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "-(+++(a))", W = "- (a+++)".

?- term_to_atom(_T, 'fy 1 yf'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "fy(yf(1))", W = "fy 1 yf".

?- term_to_atom(_T, '1 yf yf'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "yf(yf(1))", W = "1 yf yf".

?- catch(term_to_atom(_, '1 xf xf'), error(syntax_error(_), _), true).
   true.

?- term_to_atom(_T, '(1 xf) xf'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "xf(xf(1))", W = "(1 xf)xf".

?- term_to_atom(_T, '1 xfy 2 yf'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "xfy(1,yf(2))", W = "1 xfy 2 yf".

?- term_to_atom(_T, 'xfy(1, yf(2))'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "xfy(1,yf(2))", W = "1 xfy 2 yf".

?- term_to_atom(_T, 'yf(xfy(1, 2))'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "yf(xfy(1,2))", W = "(1 xfy 2)yf".

?- term_to_atom(_T, 'f(a +++)'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "f(+++(a))", W = "f(a+++)".

?- term_to_atom(_T, '[a @@, b]'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "'.'(@@(a),'.'(b,[]))", W = "[a@@,b]".

?- term_to_atom(_T, 'a done'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "done(a)", W = "a done".

?- catch(term_to_atom(_, 'a = b done'), error(syntax_error(_), _), true).
   true.

?- term_to_atom(_T, '(a = b) done'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "done(=(a,b))", W = "(a=b)done".

?- term_to_atom(_T, '- (1) +++'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "-(+++(1))", W = "- (1+++)".

?- term_to_atom(_T, '1 +++ + 2'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "+(+++(1),2)", W = "1+++ +2".

?- term_to_atom(_T, '\'@@\'(a)'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "@@(a)", W = "a@@".

?- term_to_atom(_T, '\'@@\'(1+2)'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "@@(+(1,2))", W = "(1+2)@@".

?- term_to_atom(_T, '\'@@\'(-(1))'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "@@(-(1))", W = "(- (1))@@".

?- term_to_atom(_T, '\'+++\'(\'+++\'(a))'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "+++(+++(a))", W = "a+++ +++".

?- term_to_atom(_T, '\'@@\'(\'@@\'(a))'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "@@(@@(a))", W = "(a@@)@@".

?- term_to_atom(_T, '\'@@\'(@@)'), with_output_to(chars(C), write_canonical(_T)), with_output_to(chars(W), writeq(_T)).
   C = "@@(@@)", W = "(@@)@@".

?- catch(term_to_atom(_, 'a = b = c'), error(syntax_error(_), _), true).
   true.

?- with_output_to(chars(W), writeq(yf(fy(1)))).
   W = "(fy 1)yf".

?- with_output_to(chars(W), writeq(fy(yf(1)))).
   W = "fy 1 yf".

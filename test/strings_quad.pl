% string tests (double_quotes = chars)
% "abc" parses as [a,b,c] — a list of single-character atoms

% --- simple strings ---

sstr("hello").

?- sstr("hello").
   true.

sstr2("").

?- sstr2([]).
   true.

sstr3("hello world").

?- sstr3("hello world").
   true.

sstr4("test123").

?- sstr4("test123").
   true.

sstr5("hello!@#").

?- sstr5("hello!@#").
   true.

% --- escape sequences ---

sstr6("hello\nworld").

?- sstr6("hello\nworld").
   true.

sstr7("hello\tworld").

?- sstr7("hello\tworld").
   true.

sstr8("hello\\world").

?- sstr8("hello\\world").
   true.

?- X = "\"".
   X = "\"".

% \\ produces a backslash char atom
?- X = "\\".
   X = "\\".

?- length("\n", N).
   N = 1.

?- length("\\", N).
   N = 1.

% --- string unification with variables ---

sstr9("hello").

?- sstr9(X).
   X = "hello".

sstr10(X) :- X = "test".

?- sstr10(Y).
   Y = "test".

spair("foo", "bar").

?- spair(X, Y).
   X = "foo", Y = "bar".

% --- string comparison ---

stest1 :- "hello" = "hello".

?- stest1.
   true.

stest2 :- "hello" = "world".

?- stest2.
   false.

stest3 :- "Hello" = "hello".

?- stest3.
   false.

% --- strings in complex terms ---

sperson("Alice", 30).

?- sperson("Alice", 30).
   true.

?- sperson(X, 30).
   X = "Alice".

sgreeting("hello", "world").

?- sgreeting(X, Y).
   X = "hello", Y = "world".

sdata(user("Bob")).

?- sdata(user(X)).
   X = "Bob".

% --- strings in lists ---

slist(["a", "b", "c"]).

?- slist(["a", "b", "c"]).
   true.

slist2(["foo", "bar"]).

?- slist2(X).
   X = ["foo", "bar"].

slist3(["first", "second"]).

?- slist3([X, Y]).
   X = "first", Y = "second".

% --- mixed types ---

smtest1 :- "atom" = atom.

?- smtest1.
   false.

smtest2 :- "42" = 42.

?- smtest2.
   false.

smdata("text", 42, atom).

?- smdata(X, Y, Z).
   X = "text", Y = 42, Z = atom.

% --- edge cases ---

sstr11("x").

?- sstr11("x").
   true.

sstr12("(test)").

?- sstr12("(test)").
   true.

sstr13("[test]").

?- sstr13("[test]").
   true.

sstr14("a,b,c").

?- sstr14("a,b,c").
   true.

% --- multiple solutions with strings ---

scolor("red").
scolor("green").
scolor("blue").

?- once(scolor(X)).
   X = "red".

smsg("hello").
smsg("goodbye").

?- once(smsg(X)).
   X = "hello".

% --- strings are char lists ---

?- [L|Ls] = "abc".
   L = a, Ls = "bc".

?- "abc" = [a, b, c].
   true.

?- [H|_] = "hello".
   H = h.

?- [_|T] = "hello".
   T = "ello".

?- "" = [].
   true.

?- "a" = [].
   false.

?- [L|Ls] = "x".
   L = x, Ls = [].

?- "abc" = [a, b, d].
   false.

?- [A, B, C|Rest] = "prolog".
   A = p, B = r, C = o, Rest = "log".

?- [h, e, l, l, o] = "hello".
   true.

?- once(member(X, "abc")).
   X = a.

?- findall(X, member(X, "abc"), Cs).
   Cs = "abc".

?- length("hello", N).
   N = 5.

?- length("", N).
   N = 0.

?- reverse("abc", X).
   X = "cba".

?- last(X, "hello").
   X = o.

?- member(h, "hello").
   true.

?- member(z, "hello").
   false.

% string tests (double_quotes = codes)
% "abc" parses as [97, 98, 99] — a list of character codes

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
   X = [34].

% --- escape encoding/decoding ---

?- X = "\n".
   X = [10].

?- X = "\t".
   X = [9].

?- X = "\r".
   X = [13].

?- X = "\\".
   X = [92].

?- length("\n", N).
   N = 1.

?- length("\\", N).
   N = 1.

?- X = "a\nb".
   X = [97, 10, 98].

?- [_|T] = "\n".
   T = [].

% --- string unification with variables ---

sstr9("hello").

?- sstr9(X).
   X = [104, 101, 108, 108, 111].

sstr10(X) :- X = "test".

?- sstr10(Y).
   Y = [116, 101, 115, 116].

spair("foo", "bar").

?- spair(X, Y).
   X = [102, 111, 111], Y = [98, 97, 114].

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
   X = [65, 108, 105, 99, 101].

sgreeting("hello", "world").

?- sgreeting(X, Y).
   X = [104, 101, 108, 108, 111], Y = [119, 111, 114, 108, 100].

sdata(user("Bob")).

?- sdata(user(X)).
   X = [66, 111, 98].

% --- strings in lists ---

slist(["a", "b", "c"]).

?- slist(["a", "b", "c"]).
   true.

slist2(["foo", "bar"]).

?- slist2(X).
   X = [[102, 111, 111], [98, 97, 114]].

slist3(["first", "second"]).

?- slist3([X, Y]).
   X = [102, 105, 114, 115, 116], Y = [115, 101, 99, 111, 110, 100].

% --- mixed types ---

smtest1 :- "atom" = atom.

?- smtest1.
   false.

smtest2 :- "42" = 42.

?- smtest2.
   false.

smdata("text", 42, atom).

?- smdata(X, Y, Z).
   X = [116, 101, 120, 116], Y = 42, Z = atom.

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
   X = [114, 101, 100].

smsg("hello").
smsg("goodbye").

?- once(smsg(X)).
   X = [104, 101, 108, 108, 111].

% --- strings are char code lists ---

?- [L|Ls] = "abc".
   L = 97, Ls = [98, 99].

?- "abc" = [97, 98, 99].
   true.

?- [H|_] = "hello".
   H = 104.

?- [_|T] = "hello".
   T = [101, 108, 108, 111].

?- "" = [].
   true.

?- "a" = [].
   false.

?- [L|Ls] = "x".
   L = 120, Ls = [].

?- "abc" = [97, 98, 100].
   false.

?- [A, B, C|Rest] = "prolog".
   A = 112, B = 114, C = 111, Rest = [108, 111, 103].

?- [104, 101, 108, 108, 111] = "hello".
   true.

?- once(member(X, "abc")).
   X = 97.

?- findall(X, member(X, "abc"), Cs).
   Cs = [97, 98, 99].

?- length("hello", N).
   N = 5.

?- length("", N).
   N = 0.

?- reverse("abc", X).
   X = [99, 98, 97].

?- last(X, "hello").
   X = 111.

?- member(104, "hello").
   true.

?- member(122, "hello").
   false.

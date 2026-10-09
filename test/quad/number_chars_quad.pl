% Ported from https://git.liminal.cafe/byakuren/flowlog.git
% tests/ulrich/number_chars_quad.pl

% ISO Prolog number_chars/2 Tests
% Based on https://www.complang.tuwien.ac.at/ulrich/iso-prolog/number_chars
% and https://www.complang.tuwien.ac.at/ulrich/iso-prolog/number_chars_cont
%
% Tests for ISO/IEC 13211-1:1995 number_chars/2 conformance.
% Including tests from Cor.2:2012.
%
% SOURCE PAGE INSTRUCTIONS:
% -------------------------
% The original comparison (number_chars) was used in preparation of Cor.2:2012.
% The newer comparison (number_chars_cont) includes further systems and progress.
%
% The number_chars_cont comparison requires the directive:
%   set_prolog_flag(double_quotes, chars).
%
% Results marked "OK" indicate conforming behavior. Other results indicate
% actual output when systems deviate from expected ISO standard behavior.
%
% Test cases 1..53 are from the origional comparison

:- set_prolog_flag(double_quotes, chars).

% Test: 1
?- number_chars(1.2,"1.2").
   true.

% Test: 55
?- number_chars(1.2,"1.20").
   true.

% Test: 2
?- number_chars(1.0e9,"1.0E9").
   true.

% Test: 56
?- number_chars(1.0e9,"1.0e9").
   true.

% Test: 64
?- number_chars(0.0,"-0.0").
   true.

% Test: 3
?- number_chars(1,"01").
   true.

% Test: 65
?- number_chars(10,"010").
   true.

% Test: 66
?- number_chars(N,"010").
   N = 10.

% Test: 67
?- number_chars(N,"08").
   N = 8.

% Test: 68
?- number_chars(N,"0b11").
   N = 3.

% Test: 69
?- number_chars(N,"0o11").
   N = 9.

% Test: 70
?- number_chars(N,"0x11"). 
   N = 17.

% Test: 4
?- number_chars(1,"a").
   syntax_error(...).

% Test: 5
?- number_chars(1,[]).
   syntax_error(...).

% Test: 6
?- number_chars(1,[[]]).
   type_error(character,[]).

% Test: 7
?- number_chars(1,[' ',[]]).
   type_error(character,[]). 

% Test: 8
?- number_chars(1,[0]).
   type_error(character,0).

% Test: 9
?- number_chars(1,[_,[]]).
   type_error(character,[]). 

% Test: 10
?- number_chars(N,[X]). 
   instantiation_error.

% Test: 11
?- number_chars(N,['0'|_]).
   instantiation_error.

% Test: 12
?- number_chars(N,'1').
   type_error(list,'1').

% Test: 13
?- number_chars(N,[a|a]).
   type_error(list,[a|a]).

% Test: 14
?- number_chars(N,[49]).
   type_error(character,49).

% Test: 15
?- number_chars(N,[]).
   syntax_error(...).

% Test: 16
?- number_chars(N,"3 ").
   syntax_error(...).

% Test: 17
?- number_chars(N,"3.").
   syntax_error(...).

% Test: 18
?- number_chars(N," 1").
   N = 1.

% Test: 19
?- number_chars(N,"\n1").
   N = 1.

% Test: 20
?- number_chars(N," 0'a").
   N = 0'a.
   N = 97.

% Test: 58
?- number_chars(N,"0'").
   syntax_error(...).

% Test: 59
?- number_chars(N,"0'\n").
   syntax_error(...).

% Test: 60
?- number_chars(N,"0'\\n"). 
   N = 0'\n.
   N = 10.

% Test: 61
?- number_chars(N,"0'\\7\\"). 
   N = 7.

% Test: 71
?- number_chars(N,"0'\\7").
   syntax_error(...).

% Test: 62
?- number_chars(N,"0'.").
   N = 0'..
   N = 46.

% Test: 21
?- number_chars(N,"- 1"). 
   N = -1.

% Test: 54
?- number_chars(N,"'-'1"). 
   N = -1.

% Test: 22
?- number_chars(N,"/**/1").
   N = 1.

% Test: 23
?- number_chars(N,"%\n1").
   N = 1.

% Test: 57
?- number_chars(N,"- /**/1").
   N = -1.

% Test: 24
?- number_chars(N,"-/**/1"). 
   syntax_error(...).

% Test: 63
?- number_chars(N,"'\\\n-' 3"). 
   N = -3.

% Test: 25
?- number_chars(N,"1e1"). 
   syntax_error(...).

% Test: 26
?- number_chars(N,"1.0e"). 
   syntax_error(...).

% Test: 27
?- number_chars(N,"1.0ee"). 
   syntax_error(...).

% Test: 28
?- number_chars(N,"0x1"). 
   N = 1.

% Test: 29
?- number_chars(N,"0X1"). 
   syntax_error(...).

% Test: 30
?- number_chars(N,"1E1"). 
   syntax_error(...).

% Test: 47
?- number_chars(1,['.'|_]). 
   false.

% Test: 48
?- number_chars(N,"+1"). 
   syntax_error(...).

% Test: 49
?- number_chars(N,"+ 1"). 
   syntax_error(...).

% Test: 50
?- number_chars(N,"'+'1"). 
   syntax_error(...).

% Test: 51
?- number_chars(N,['11']).
   type_error(character,'11').

% Test: 52
?- number_chars(N,['1.1']).
   type_error(character,'1.1').

% Test: 53
?- number_chars(1+1,"2"). 
   type_error(number,1+1).

% Test: 31
?- number_chars(1,[C]). 
   C = '1'.

% Test: 32
?- number_chars(1,[C,D]). 
   false.

% Test: 33
?- number_chars(1,[C,C]). 
   false.

% Test: 34
?- number_chars(0,[C,C]). 
   false.

% Test: 35
?- number_chars(10,[C,D]). 
   C = '1', D = '0'.

% Test: 36
?- number_chars(100,[C,D]). 
   false.

% Test: 37
?- number_chars(N,[X|2]). 
   type_error(list,[_|2])
   | instantiation_error. 

% Test: 38
?- number_chars(N,[1|_]). 
   instantiation_error
   | type_error(character,1). 

% Test: 39
?- number_chars(V,[1|2]). 
   type_error(list,[1|2])
   | type_error(character,1).

% Test: 40
?- number_chars([],1). 
   type_error(number,[])
   | type_error(list,1). 

% Test: 41
?- number_chars(1,1). 
   type_error(list,1).

% Test: 42
?- number_chars(1,[a|2]). 
   type_error(list,[a|2]).

% Test: 43
?- number_chars(1,[_|2]). 
   type_error(list,[_|2]).

% Test: 44
?- number_chars(1,[[]|_]). 
   type_error(character,[]).

% Test: 45
?- number_chars(1,[[]|2]). 
   type_error(character,[])
   | type_error(list,[[]|2]). 

% Test: 46
?- L=['1'|L], number_chars(N,L). % * is default
   sto,
   ( type_error(list,['1'|...]) % rational trees
   | false % occurs-check
   | representation_error(term)
   | instantiation_error % literal substitutions
   | resource_error(...)
   | loops
   ).

% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% not converted (Logtalk ::): create_no_read_permission_file
% not converted (Logtalk ::): create_no_write_permission_file
% not converted (Logtalk ::): create_no_append_permission_file
% not converted (Logtalk ::): not_running_as_root

% iso_open_4_01
?- lgt_run((file_path('roger_data', Path), create_binary_file(Path, []), (open(Path, read, D, [type(binary)]), at_end_of_stream(D)))).
   true.

% iso_open_4_02
?- lgt_run((file_path('scowen', Path), (open(Path, write, D, [alias(editor)]), stream_property(D, alias(editor))))).
   true.

% iso_open_4_03
?- lgt_run((file_path('dave', Path), create_text_file(Path, 'foo.'), (open(Path, read, DD, []), read(DD, foo), at_end_of_stream(DD)))).
   true.

% sics_open_4_04
?- lgt_run(open(_, read, _)).
   error(instantiation_error).

% sics_open_4_05
?- lgt_run(open(f, _, _)).
   error(instantiation_error).

% sics_open_4_06
?- lgt_run(open(f, write, _, _)).
   error(instantiation_error).

% sics_open_4_07
?- lgt_run(open(f, write, _, [type(text)|_])).
   error(instantiation_error).

% sics_open_4_08
?- lgt_run(open(f, write, _, [type(text),_])).
   error(instantiation_error).

% sics_open_4_09
?- lgt_run(open(f, 1, _)).
   error(type_error(atom,1)).

% sics_open_4_10
?- lgt_run(open(f, write, _, type(text))).
   error(type_error(list,type(text))).

% sics_open_4_11
?- lgt_run(open(f, write, bar)).
   error(uninstantiation_error(bar)).

% sics_open_4_12
?- lgt_run(open(foo(1,2), write, _)).
   error(domain_error(source_sink,foo(1,2))).

% sics_open_4_13
?- lgt_run(open('foo', red, _)).
   error(domain_error(io_mode,red)).

% sics_open_4_14
?- lgt_run(open(foo, write, _, [bar])).
   error(domain_error(stream_option,bar)).

% sics_open_4_15
?- lgt_run((file_path('nonexistent', Path), open(Path, read, _))).
   error(existence_error(source_sink,Path)).

% sics_open_4_16
?- lgt_run((file_path(foo, Path), (open(Path, write, _, [alias(a)]), open(bar, write, _, [alias(a)])))).
   error(permission_error(open,source_sink,alias(a))).

:- clean_file(roger_data), clean_file(scowen), clean_file(dave), clean_file(foo), clean_file(bar), clean_file(f), clean_file(no_read_permission), clean_file(no_write_permission), clean_file(no_append_permission), clean_file(d1), clean_file(d2), clean_file(tt), clean_file(tb), clean_file(rt), clean_file(rf).

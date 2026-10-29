:- ensure_loaded(library(dcgs)).
:- ensure_loaded(library(between)).
:- ensure_loaded('http.pl').
:- ensure_loaded('routes.pl').
:- ensure_loaded('pages.pl').
:- ensure_loaded('tree.pl').

main :-
    tri_led_flash,
    (   wifi_connect_saved
    ->  serve(80)
    ;   write('wifi: not connected; use wifi_save/2, or wifi_connect/2 and serve(80)'), nl
    ).

tri_led_flash :-
    forall(between(1, 3, _),
           ( onboard_led(1), sleep_ms(150), onboard_led(0), sleep_ms(150) )).

trilog_version(V) :-
    '$trilog_version'(A),
    atom_chars(A, V).

% Compiles the DCGs now, so the boot image holds them already compiled.
:- forall(member(N/A, [request/1, route/1, head/2, title/0, link/2, page/1,
                       stat_row/3, tree_footer/2, segments/1, node/1]),
          '$dcg_ensure'(N, A)).

:- ensure_loaded(library(dcgs)).
:- ensure_loaded(library(between)).
:- ensure_loaded('http.pl').
:- ensure_loaded('routes.pl').
:- ensure_loaded('pages.pl').
:- ensure_loaded('tree.pl').
:- ensure_loaded('mail.pl').

main :-
    tri_led_flash,
    send_mail(trilog, booted, ("trilog ", version, " on ", board, "\n")),
    (   join_wifi
    ->  serve(80)
    ;   write('wifi: not connected; use wifi_save/2, or wifi_connect/2 and serve(80)'), nl
    ).

join_wifi :-
    (   wifi_saved(Ssid)
    ->  (   wifi_connect_saved
        ->  wifi_ip(Ip),
            send_mail(wifi, connected,
                      ("Loaded the saved password for ", atom(Ssid), ".\n",
                       "Connected to ", atom(Ssid), ", ip ", atom(Ip), ".\n"))
        ;   wifi_status(Why),
            send_mail(wifi, 'not connected',
                      ("Loaded the saved password for ", atom(Ssid), ".\n",
                       "Could not connect to ", atom(Ssid), ": ", atom(Why), ".\n")),
            fail
        )
    ;   send_mail(wifi, 'not connected', "No network is saved. Use wifi_save/2.\n"),
        fail
    ).

tri_led_flash :-
    forall(between(1, 3, _),
           ( onboard_led(1), sleep_ms(150), onboard_led(0), sleep_ms(150) )).

trilog_version(V) :-
    '$trilog_version'(A),
    atom_chars(A, V).

% Compiles the DCGs now, so the boot image holds them already compiled.
:- forall(member(N/A, [request/1, route/1, head/2, title/0, link/2, page/1,
                       stat_row/3, tree_footer/2, segments/1, node/1,
                       request_line/4, mail_summary/1, mail_head/1,
                       heap_map/0, heap_legend/0, gauge/4]),
          '$dcg_ensure'(N, A)).

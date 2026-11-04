:- module(main, [main/0]).

:- use_module(library(dcgs)).
:- use_module(library(between)).
:- use_module(text).
:- use_module(mail).
:- use_module(pages).
:- use_module(http).

main :-
    tri_led_flash,
    mail:send(trilog, booted, ("trilog ", pages:version, " on ", pages:board, "\n")),
    (   join_wifi
    ->  http:serve(80)
    ;   write('wifi: not connected; use wifi_save/2, or wifi_connect/2 and serve(80)'), nl
    ).

join_wifi :-
    (   wifi_saved(Ssid)
    ->  (   wifi_connect_saved
        ->  wifi_ip(Ip),
            mail:send(wifi, connected,
                      ("Loaded the saved password for ", text:atom(Ssid), ".\n",
                       "Connected to ", text:atom(Ssid), ", ip ", text:atom(Ip), ".\n"))
        ;   wifi_status(Why),
            mail:send(wifi, 'not connected',
                      ("Loaded the saved password for ", text:atom(Ssid), ".\n",
                       "Could not connect to ", text:atom(Ssid), ": ", text:atom(Why), ".\n")),
            fail
        )
    ;   mail:send(wifi, 'not connected', "No network is saved. Use wifi_save/2.\n"),
        fail
    ).

tri_led_flash :-
    forall(between(1, 3, _),
           ( onboard_led(1), sleep_ms(150), onboard_led(0), sleep_ms(150) )).

% Compiles the DCGs now, so the boot image holds them already compiled.
:- '$dcg_compile_all'.

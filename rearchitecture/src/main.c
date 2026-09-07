#include "heap.h"
#include "parse.h"
#include "solve.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    heap_init();
    solve_init();

    if (!consult_file("boot/core.pl")) return 1;

    const char *query = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-e") && i + 1 < argc) {
            query = argv[++i];
        } else {
            if (!consult_file(argv[i])) return 1;
        }
    }

    if (query) {
        tterm_t **goals;
        int32_t ngoals, nvars;
        const char **names;
        if (!parse_query(query, &goals, &ngoals, &nvars, &names)) return 1;
        run_query(goals, ngoals, nvars, names);
    }

    return 0;
}

CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -O2
SRCS = src/heap.c src/unify.c src/term.c src/solve.c src/parse.c src/arena.c src/gc.c src/main.c

trilog: $(SRCS) src/*.h
	$(CC) $(CFLAGS) -o trilog $(SRCS)

.PHONY: test clean
test: trilog
	bats test/

clean:
	rm -f trilog

CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -O2 -Isrc/kernel -Isrc/io
KERNEL_SRCS = src/kernel/heap.c src/kernel/unify.c src/kernel/term.c src/kernel/solve.c \
              src/kernel/parse.c src/kernel/arena.c src/kernel/gc.c
IO_SRCS = src/io/io.c src/io/streams.c
SRCS = $(KERNEL_SRCS) $(IO_SRCS) src/main.c
HDRS = $(wildcard src/kernel/*.h) $(wildcard src/io/*.h)

trilog: $(SRCS) src/kernel/*.h src/io/*.h
	$(CC) $(CFLAGS) -o trilog $(SRCS)

.PHONY: test clean format format-check
test: trilog
	bats test/

clean:
	rm -f trilog

format:
	clang-format -i $(SRCS) $(HDRS)

format-check:
	clang-format --dry-run --Werror $(SRCS) $(HDRS)

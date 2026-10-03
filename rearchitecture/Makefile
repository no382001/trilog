CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -O2 -Iinclude -Isrc/kernel -Isrc/io -Isrc/platform

PLATFORM ?= posix
PLATFORM_SRC = src/platform/$(PLATFORM).c
KERNEL_SRCS = src/kernel/heap.c src/kernel/unify.c src/kernel/term.c src/kernel/solve.c \
              src/kernel/parse.c src/kernel/arena.c src/kernel/gc.c
IO_SRCS = src/io/io.c src/io/streams.c
LIB_SRCS = $(KERNEL_SRCS) $(IO_SRCS) src/trilog.c
SRCS = $(LIB_SRCS) src/main.c
HDRS = include/trilog.h $(wildcard src/kernel/*.h) $(wildcard src/io/*.h) $(wildcard src/platform/*.h)

trilog: format $(SRCS) $(PLATFORM_SRC) src/kernel/embedded_none.c $(HDRS)
	$(CC) $(CFLAGS) -o trilog $(SRCS) $(PLATFORM_SRC) src/kernel/embedded_none.c -lm

# The release build bakes boot/core.pl and lib/*.pl into the binary, so it
# runs from anywhere without the library files next to it.
EMBED_FILES = boot/core.pl $(sort $(wildcard lib/*.pl))

_build/embedded.c: $(EMBED_FILES) tools/embed_libs.sh
	@mkdir -p _build
	sh tools/embed_libs.sh $(EMBED_FILES) > $@

.PHONY: release
release: format $(SRCS) $(PLATFORM_SRC) _build/embedded.c $(HDRS)
	$(CC) $(CFLAGS) -flto=auto -DTRILOG_EMBEDDED -o _build/trilog $(SRCS) $(PLATFORM_SRC) _build/embedded.c -lm

_build/api_test: test/api_test.c $(LIB_SRCS) $(PLATFORM_SRC) src/kernel/embedded_none.c $(HDRS)
	@mkdir -p _build
	$(CC) $(CFLAGS) -o $@ test/api_test.c $(LIB_SRCS) $(PLATFORM_SRC) src/kernel/embedded_none.c -lm

_build/api_threads_test: test/api_threads_test.c $(LIB_SRCS) src/platform/posix.c src/kernel/embedded_none.c $(HDRS)
	@mkdir -p _build
	$(CC) $(CFLAGS) -pthread -o $@ test/api_threads_test.c $(LIB_SRCS) src/platform/posix.c src/kernel/embedded_none.c -lm

.PHONY: test test-api test-upstream clean format format-check
test: trilog test-api
	bats test/

test-api: _build/api_test _build/api_threads_test
	_build/api_test
	_build/api_threads_test

test-upstream: trilog
	@tmp=$$(mktemp); \
	sed 's|TRILOG="./trilog"|TRILOG="$(CURDIR)/trilog"|' ../test/system.bats > $$tmp; \
	bats $$tmp; status=$$?; rm -f $$tmp; exit $$status

QUAD_TIMEOUT := 60

# Hard cap in KB (1GB) via `ulimit -v` - a runaway allocation then fails
# just that process instead of the kernel OOM-killing the whole machine.
QUAD_MEM_LIMIT_KB := 1048576

.PHONY: quad
quad: trilog
	@for f in test/*_quad.pl; do \
		[ -f "$$f" ] || continue; \
		( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) ./trilog -e "consult('lib/quad.pl'), quad_cli('$$f')" ) || true; \
	done

QUAD_MAX_RESUME_ATTEMPTS := 20

# Crash-resume: relaunches with an incremented Skip after every crash, reusing the same checkpoint files.
.PHONY: quad-junit
quad-junit: trilog
	@mkdir -p _build/test-results
	@for f in test/*_quad.pl; do \
		[ -f "$$f" ] || continue; \
		suite=$$(basename "$$f" .pl); \
		skip=0; \
		attempt=0; \
		while :; do \
			attempt=$$((attempt + 1)); \
			( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) ./trilog -e "consult('lib/quad.pl'), quad_cli_junit('$$f', '_build/test-results', $$skip)" ) || true; \
			[ -f "_build/test-results/$$suite.xml" ] && break; \
			if [ ! -s "_build/test-results/$$suite.xml.partial" ] && [ ! -s "_build/test-results/$$suite.progress" ]; then \
				echo "# $$f: trilog crashed with no checkpoint to recover from"; \
				break; \
			fi; \
			if [ $$attempt -ge $(QUAD_MAX_RESUME_ATTEMPTS) ]; then \
				echo "# $$f: gave up after $(QUAD_MAX_RESUME_ATTEMPTS) crashes, finalizing what ran"; \
				( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) ./trilog -e "consult('lib/quad.pl'), quad_mark_crash('$$suite', '_build/test-results'), quad_finalize_junit('$$f', '$$suite', '_build/test-results')" ) || true; \
				break; \
			fi; \
			skip=$$( ( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) ./trilog -e "consult('lib/quad.pl'), quad_mark_crash('$$suite', '_build/test-results'), quad_resolved_count('$$suite', '_build/test-results', N), write(N), halt." ) 2>/dev/null); \
			echo "# $$f: trilog crashed mid-run (attempt $$attempt), resuming after test $$skip"; \
		done; \
	done
	@echo "JUnit reports written to _build/test-results/"

clean:
	rm -f trilog _build/trilog _build/embedded.c _build/api_test _build/api_threads_test

format:
	clang-format -i $(SRCS) test/api_test.c test/api_threads_test.c src/kernel/embedded_none.c src/platform/*.c $(HDRS)

format-check:
	clang-format --dry-run --Werror $(SRCS) test/api_test.c test/api_threads_test.c src/kernel/embedded_none.c src/platform/*.c $(HDRS)

CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -O2 -Isrc/kernel -Isrc/io
KERNEL_SRCS = src/kernel/heap.c src/kernel/unify.c src/kernel/term.c src/kernel/solve.c \
              src/kernel/parse.c src/kernel/arena.c src/kernel/gc.c
IO_SRCS = src/io/io.c src/io/streams.c
SRCS = $(KERNEL_SRCS) $(IO_SRCS) src/main.c
HDRS = $(wildcard src/kernel/*.h) $(wildcard src/io/*.h)

trilog: format $(SRCS) src/kernel/*.h src/io/*.h
	$(CC) $(CFLAGS) -o trilog $(SRCS) -lm

.PHONY: test test-upstream clean format format-check
test: trilog
	bats test/

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
		( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) ./trilog -e "consult('test/quad.pl'), quad_cli('$$f')" ) || true; \
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
			( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) ./trilog -e "consult('test/quad.pl'), quad_cli_junit('$$f', '_build/test-results', $$skip)" ) || true; \
			[ -f "_build/test-results/$$suite.xml" ] && break; \
			if [ ! -s "_build/test-results/$$suite.xml.partial" ] && [ ! -s "_build/test-results/$$suite.progress" ]; then \
				echo "# $$f: trilog crashed with no checkpoint to recover from"; \
				break; \
			fi; \
			if [ $$attempt -ge $(QUAD_MAX_RESUME_ATTEMPTS) ]; then \
				echo "# $$f: gave up after $(QUAD_MAX_RESUME_ATTEMPTS) crashes, finalizing what ran"; \
				( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) ./trilog -e "consult('test/quad.pl'), quad_mark_crash('$$suite', '_build/test-results'), quad_finalize_junit('$$f', '$$suite', '_build/test-results')" ) || true; \
				break; \
			fi; \
			skip=$$( ( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) ./trilog -e "consult('test/quad.pl'), quad_mark_crash('$$suite', '_build/test-results'), quad_resolved_count('$$suite', '_build/test-results', N), write(N), halt." ) 2>/dev/null); \
			echo "# $$f: trilog crashed mid-run (attempt $$attempt), resuming after test $$skip"; \
		done; \
	done
	@echo "JUnit reports written to _build/test-results/"

clean:
	rm -f trilog

format:
	clang-format -i $(SRCS) $(HDRS)

format-check:
	clang-format --dry-run --Werror $(SRCS) $(HDRS)

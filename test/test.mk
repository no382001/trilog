# Test rules; included by the top-level Makefile, run from the repo root.
# make TRILOG=./trilog-hostile RESULTS=_build/test-results-freestanding quad-junit tests the hostile build.
TRILOG ?= ./trilog
RESULTS ?= _build/test-results

API_TESTS = api_test api_threads_test api_oom_test api_namespace_test
API_TEST_SRCS = $(API_TESTS:%=test/api/%.c)
API_TEST_BINS = $(API_TESTS:%=_build/%)

-include $(API_TESTS:%=$(DEV)/test/api/%.d)

$(API_TEST_BINS): _build/%: $(DEV)/test/api/%.o $(DEV)/libtrilog.a
	$(CC) $(CFLAGS) $(if $(findstring threads,$*),-pthread) -o $@ $^ -lm

.PHONY: test test-api api-junit quad quad-junit syscheck-junit conformity conformity-junit
test: trilog test-api
	bats test/e2e/

syscheck-junit: trilog
	@mkdir -p $(RESULTS)
	TRILOG=$(TRILOG) bats --report-formatter junit --output $(RESULTS) test/e2e/

test-api: $(API_TEST_BINS) examples/embed
	examples/embed
	_build/api_namespace_test
	_build/api_test
	_build/api_threads_test
	_build/api_oom_test 2>/dev/null

api-junit: $(API_TEST_BINS) examples/embed
	@mkdir -p $(RESULTS)
	test/api/tap.sh examples/embed $(API_TEST_BINS) | awk -v suite=api -v file=test/api -f test/tap2junit.awk >$(RESULTS)/api.xml

conformity: trilog
	test/conformity/conformity.sh

conformity-junit: trilog
	@mkdir -p $(RESULTS)
	TRILOG=$(TRILOG) test/conformity/conformity.sh -v | awk -v suite=conformity -v file=test/conformity/conformity.txt -f test/tap2junit.awk >$(RESULTS)/conformity.xml

QUAD_TIMEOUT := 60

# Hard cap in KB (1GB) via `ulimit -v`
QUAD_MEM_LIMIT_KB := 1048576

quad: trilog
	@for f in test/quad/*_quad.pl; do \
		[ -f "$$f" ] || continue; \
		( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) $(TRILOG) -e "consult('lib/quad.pl'), quad_cli('$$f')" ) || true; \
	done

QUAD_MAX_RESUME_ATTEMPTS := 20

# Crash-resume: relaunches with an incremented Skip after every crash, reusing the same checkpoint files.
quad-junit: trilog
	@mkdir -p $(RESULTS)
	@for f in test/quad/*_quad.pl; do \
		[ -f "$$f" ] || continue; \
		suite=$$(basename "$$f" .pl); \
		skip=0; \
		attempt=0; \
		while :; do \
			attempt=$$((attempt + 1)); \
			( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) $(TRILOG) -e "consult('lib/quad.pl'), quad_cli_junit('$$f', '$(RESULTS)', $$skip)" ) || true; \
			[ -f "$(RESULTS)/$$suite.xml" ] && break; \
			if [ ! -s "$(RESULTS)/$$suite.xml.partial" ] && [ ! -s "$(RESULTS)/$$suite.progress" ]; then \
				echo "# $$f: trilog crashed with no checkpoint to recover from"; \
				break; \
			fi; \
			if [ $$attempt -ge $(QUAD_MAX_RESUME_ATTEMPTS) ]; then \
				echo "# $$f: gave up after $(QUAD_MAX_RESUME_ATTEMPTS) crashes, finalizing what ran"; \
				( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) $(TRILOG) -e "consult('lib/quad.pl'), quad_mark_crash('$$suite', '$(RESULTS)'), quad_finalize_junit('$$f', '$$suite', '$(RESULTS)')" ) || true; \
				break; \
			fi; \
			skip=$$( ( ulimit -v $(QUAD_MEM_LIMIT_KB); timeout $(QUAD_TIMEOUT) $(TRILOG) -e "consult('lib/quad.pl'), quad_mark_crash('$$suite', '$(RESULTS)'), quad_resolved_count('$$suite', '$(RESULTS)', N), write(N), halt." ) 2>/dev/null); \
			echo "# $$f: trilog crashed mid-run (attempt $$attempt), resuming after test $$skip"; \
		done; \
	done
	@echo "JUnit reports written to $(RESULTS)/"

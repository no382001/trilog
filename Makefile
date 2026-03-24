CC := gcc
CFLAGS := \
    -std=c11 \
    -Wall \
    -Wextra \
    -Wpedantic \
	-Werror \
    -g
CFLAGS += -fsanitize=address -fno-omit-frame-pointer
LDFLAGS += -fsanitize=address

TARGET := trilog
BUILD_DIR := _build
EXAMPLES_DIR := examples

SRCS := $(wildcard src/*.c)
HDRS := $(wildcard src/*.h)
OBJS := $(SRCS:src/%.c=$(BUILD_DIR)/%.o)

LIB_OBJS := $(filter-out $(BUILD_DIR)/main.o,$(OBJS))

EXAMPLE_SRCS := $(wildcard $(EXAMPLES_DIR)/*.c)
EXAMPLE_BINS := $(filter-out $(BUILD_DIR)/freestanding,$(EXAMPLE_SRCS:$(EXAMPLES_DIR)/%.c=$(BUILD_DIR)/%))

all: format $(TARGET) $(EXAMPLE_BINS)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) -o $@

$(BUILD_DIR)/%.o: src/%.c $(HDRS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%: $(EXAMPLES_DIR)/%.c $(LIB_OBJS) $(HDRS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $< $(LIB_OBJS) $(LDFLAGS) -o $@

$(BUILD_DIR):
	mkdir -p $@

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) $(TARGET) $(WEB_DIR)/trilog.js $(WEB_DIR)/trilog.wasm

.PHONY: examples
examples: $(EXAMPLE_BINS)

.PHONY: format
format:
	clang-format -i $(SRCS) $(HDRS)

.PHONY: format-check
format-check:
	clang-format --dry-run --Werror $(SRCS) $(HDRS)

.PHONY: run
run: $(TARGET)
	./$(TARGET)

.PHONY: debug
debug: $(TARGET)
	./$(TARGET) -d

.PHONY: quad
quad: $(TARGET)
	@for f in test/*_quad.pl; do \
		[ -f "$$f" ] || continue; \
		if [ "$$f" = "test/iso_quad.pl" ]; then \
			./$(TARGET) -q "$$f" || true; \
		else \
			./$(TARGET) -q "$$f" || exit 1; \
		fi \
	done

.PHONY: quad-junit
quad-junit: $(TARGET)
	@mkdir -p _build/test-results
	@for f in test/*_quad.pl; do \
		[ -f "$$f" ] || continue; \
		if [ "$$f" = "test/iso_quad.pl" ]; then \
			./$(TARGET) -q "$$f" -j _build/test-results || true; \
		else \
			./$(TARGET) -q "$$f" -j _build/test-results || exit 1; \
		fi \
	done
	@echo "JUnit reports written to _build/test-results/"

WEB_DIR := web
WEB_LIB_SRCS := $(filter-out src/main.c, $(SRCS))
WEB_ENTRY := $(WEB_DIR)/main_web.c

# arm cortex-m0+ constraints (rp2040, 264kb sram)
WEB_M0_FLAGS := \
    -DMAX_NAME=32 \
    -DMAX_LIST_LIT=128 \
    -DMAX_CLAUSES=256 \
    -DMAX_BINDINGS=1024 \
    -DMAX_GOALS=64 \
    -DMAX_STACK=128 \
    -DMAX_ERROR_MSG=128 \
    -DMAX_CUSTOM_BUILTINS=8 \
    -DMAX_STRING_POOL=8192 \
    -DMAX_FILE_PATH=128 \
    -DMAX_MAKE_FILES=4 \
    -DMAX_OPEN_STREAMS=4 \
    -DMAX_CLAUSE_VARS=32 \
    -DTERM_POOL_BYTES=196608

.PHONY: web
web: $(WEB_DIR)/trilog.js

$(WEB_DIR)/trilog.js: $(WEB_LIB_SRCS) $(WEB_ENTRY) $(HDRS) core.pl ledit.pl
	emcc $(WEB_LIB_SRCS) $(WEB_ENTRY) \
	    -o $@ \
	    -O2 \
	    $(WEB_M0_FLAGS) \
	    -s WASM=1 \
	    -s ALLOW_MEMORY_GROWTH=1 \
	    -s ASYNCIFY=1 \
	    -s EXPORTED_FUNCTIONS='["_trilog_web_init","_trilog_web_eval","_trilog_web_push_line","_trilog_web_is_reading","_trilog_web_take_output","_trilog_web_set_yield","_trilog_web_get_stats","_trilog_web_get_usage"]' \
	    -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","getValue"]' \
	    --embed-file core.pl@/core.pl \
	    --embed-file ledit.pl@/ledit.pl

.PHONY: serve-web
serve-web:
	-kill $$(ss -tlnp 'sport = :8080' 2>/dev/null | grep -oP 'pid=\K[0-9]+') 2>/dev/null; sleep 0.2
	php -S localhost:8080 -t $(WEB_DIR)

.PHONY: freestanding
freestanding: | $(BUILD_DIR)
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -Werror -g \
		-DTRILOG_FREESTANDING -DNDEBUG \
		-ffreestanding -nostdlib \
		$(EXAMPLES_DIR)/freestanding.c -o $(BUILD_DIR)/freestanding
.DEFAULT_GOAL := trilog

CC = gcc
AR = gcc-ar
CFLAGS = -Wall -Wextra -std=c11 -O2
CPPFLAGS = -Iinclude -Isrc/kernel -Isrc/io -Isrc/platform -I_build -MMD -MP

PLATFORM ?= posix
KERNEL_SRCS = src/kernel/heap.c src/kernel/unify.c src/kernel/term.c src/kernel/solve.c \
              src/kernel/parse.c src/kernel/arena.c src/kernel/gc.c src/kernel/mem.c
IO_SRCS = src/io/io.c src/io/streams.c
LIB_SRCS = $(KERNEL_SRCS) $(IO_SRCS) src/trilog.c src/platform/$(PLATFORM).c
CLI_SRCS = cli/main.c cli/terminal_$(PLATFORM).c
SRCS = $(KERNEL_SRCS) $(IO_SRCS) src/trilog.c cli/main.c
HDRS = include/trilog.h cli/terminal.h $(wildcard src/kernel/*.h) $(wildcard src/io/*.h) $(wildcard src/platform/*.h)

# OPAQUE=0 exports every engine symbol instead of only the trilog_* API.
OPAQUE ?= 1
VARIANT = $(PLATFORM)$(if $(filter 0,$(OPAQUE)),-open)
DEV = _build/dev-$(VARIANT)
REL = _build/release-$(VARIANT)
HIDE_INTERNALS = $(if $(filter 0,$(OPAQUE)),true,objcopy --wildcard --keep-global-symbol='trilog_*')
DEV_LIB_OBJS = $(patsubst %.c,$(DEV)/%.o,$(LIB_SRCS) src/kernel/embedded_none.c)
REL_LIB_OBJS = $(patsubst %.c,$(REL)/%.o,$(LIB_SRCS) _build/embedded.c)
DEV_CLI_OBJS = $(patsubst %.c,$(DEV)/%.o,$(CLI_SRCS))
REL_CLI_OBJS = $(patsubst %.c,$(REL)/%.o,$(CLI_SRCS))

$(DEV)/cli/%.o $(REL)/cli/%.o: CPPFLAGS = -Iinclude -Icli -MMD -MP

$(DEV)/%.o: %.c | format
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(REL)/%.o: %.c | format
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) -DTRILOG_EMBEDDED $(CFLAGS) -flto=auto -c $< -o $@

# Unless OPAQUE=0, internal names are not exported.
$(DEV)/libtrilog.a: $(DEV_LIB_OBJS)
	@rm -f $@
	$(CC) -r -nostdlib -o $(DEV)/libtrilog.o $^
	$(HIDE_INTERNALS) $(DEV)/libtrilog.o
	$(AR) rcs $@ $(DEV)/libtrilog.o

$(REL)/libtrilog.a: $(REL_LIB_OBJS)
	@rm -f $@
	$(CC) $(CFLAGS) -r -nostdlib -flto=auto -flinker-output=nolto-rel -o $(REL)/libtrilog.o $^
	$(HIDE_INTERNALS) $(REL)/libtrilog.o
	$(AR) rcs $@ $(REL)/libtrilog.o

GIT_DESCRIBE := $(shell git describe --tags --always --dirty 2>/dev/null || echo unknown)
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)

_build/version.h: FORCE
	@mkdir -p _build
	@printf '#define TRILOG_BUILD_VERSION "%s (%s)"\n' '$(GIT_DESCRIBE)' '$(GIT_BRANCH)' > $@.tmp
	@if cmp -s $@.tmp $@; then rm $@.tmp; else mv $@.tmp $@; fi

$(DEV)/src/trilog.o $(REL)/src/trilog.o: _build/version.h

.PHONY: FORCE
FORCE:

$(DEV)/trilog: $(DEV_CLI_OBJS) $(DEV)/libtrilog.a
	$(CC) $(CFLAGS) -o $@ $^ -lm

$(REL)/trilog: $(REL_CLI_OBJS) $(REL)/libtrilog.a
	$(CC) $(CFLAGS) -flto=auto -o $@ $^ -lm

-include $(DEV_LIB_OBJS:.o=.d) $(REL_LIB_OBJS:.o=.d) $(DEV_CLI_OBJS:.o=.d) $(REL_CLI_OBJS:.o=.d) \
         $(DEV)/examples/embed.d

.PHONY: trilog release lib
trilog: $(DEV)/trilog
	@cp $< $@

lib: $(DEV)/libtrilog.a

# The release build bakes boot/core.pl and lib/*.pl into the binary, so it
# runs from anywhere without the library files next to it.
EMBED_FILES = boot/core.pl $(sort $(wildcard lib/*.pl))

_build/embedded.c: $(EMBED_FILES) tools/embed_libs.sh
	@mkdir -p _build
	sh tools/embed_libs.sh $(EMBED_FILES) > $@

release: $(REL)/trilog
	@cp $< _build/trilog

examples/embed: $(DEV)/examples/embed.o $(DEV)/libtrilog.a
	$(CC) $(CFLAGS) -o $@ $^ -lm

clean:
	rm -rf trilog _build/trilog _build/embedded.c $(API_TEST_BINS) examples/embed _build/dev-* _build/release-*

format:
	clang-format -i $(SRCS) $(API_TEST_SRCS) examples/embed.c src/kernel/embedded_none.c src/platform/*.c cli/*.c $(HDRS)

format-check:
	clang-format --dry-run --Werror $(SRCS) $(API_TEST_SRCS) examples/embed.c src/kernel/embedded_none.c src/platform/*.c cli/*.c $(HDRS)

.PHONY: clean format format-check
include test/test.mk

# make sync builds the firmware and copies it to a Pico W on USB;
# make restart restarts the board; make get-ip prints its IP address;
# make term opens a terminal with line editing.
BUILD ?= build
PORT ?=
# Library text to bake in, such as EMBED_FILES=lib/charsio.pl; none by
# default, as loaded text puts its clauses in the board's scarce RAM.
export EMBED_FILES ?=

.PHONY: sync restart get-ip term build clean

sync: build
	./flash.sh $(BUILD)/trilog.uf2 $(PORT)

restart:
	./restart.sh $(PORT)

get-ip:
	@./get-ip.sh $(PORT)

term:
	@./term.py $(PORT)

build: $(BUILD)/Makefile
	cmake --build $(BUILD)

$(BUILD)/Makefile:
	cmake -S . -B $(BUILD)

clean:
	rm -rf $(BUILD)

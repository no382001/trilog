# make sync builds the firmware and copies it to a Pico W on USB;
# make restart restarts the board; make get-ip prints its IP address.
BUILD ?= build
PORT ?=

.PHONY: sync restart get-ip build clean

sync: build
	./flash.sh $(BUILD)/trilog.uf2 $(PORT)

restart:
	./restart.sh $(PORT)

get-ip:
	@./get-ip.sh $(PORT)

build: $(BUILD)/Makefile
	cmake --build $(BUILD)

$(BUILD)/Makefile:
	cmake -S . -B $(BUILD)

clean:
	rm -rf $(BUILD)

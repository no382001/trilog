# make sync builds the firmware and copies it to a Pico W on USB.
BUILD ?= build
PORT ?=

.PHONY: sync build clean

sync: build
	./flash.sh $(BUILD)/trilog.uf2 $(PORT)

build: $(BUILD)/Makefile
	cmake --build $(BUILD)

$(BUILD)/Makefile:
	cmake -S . -B $(BUILD)

clean:
	rm -rf $(BUILD)

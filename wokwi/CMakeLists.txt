cmake_minimum_required(VERSION 3.13)

set(PICO_SDK_PATH ${CMAKE_CURRENT_SOURCE_DIR}/pico-sdk)
set(PICO_BOARD pico2)
set(PICO_PLATFORM rp2350-arm-s)
include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(trilog C CXX ASM)
set(CMAKE_C_STANDARD 11)

pico_sdk_init()

set(ROOT ${CMAKE_CURRENT_SOURCE_DIR}/..)
set(LIBTRILOG ${ROOT}/_build/release-rp2350/libtrilog.a)

add_custom_target(libtrilog
  COMMAND make -C ${ROOT} _build/release-rp2350/libtrilog.a
          REL=_build/release-rp2350 PLATFORM=no_posix
          CC=arm-none-eabi-gcc AR=arm-none-eabi-gcc-ar
          "CFLAGS=-Wall -Wextra -std=c11 -O2 -mcpu=cortex-m33 -mthumb -march=armv8-m.main+fp+dsp -mfloat-abi=softfp -DGC_MIN_CELLS=2048 -DARENA_CHUNK_SIZE=4096 -DGC_SHRINK=0"
          "HIDE_INTERNALS=arm-none-eabi-objcopy --wildcard --keep-global-symbol=trilog_*"
  BYPRODUCTS ${LIBTRILOG}
)

add_executable(trilog hd44780.c leds.c main_rp2040.c)
add_dependencies(trilog libtrilog)
set_target_properties(trilog PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/trilog"
)

target_compile_definitions(trilog PRIVATE PICO_MALLOC_PANIC=0)
target_include_directories(trilog PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${ROOT}/include)

pico_enable_stdio_usb(trilog 0)
pico_enable_stdio_uart(trilog 1)

target_link_libraries(trilog ${LIBTRILOG} pico_stdlib hardware_gpio m)

pico_add_extra_outputs(trilog)

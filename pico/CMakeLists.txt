cmake_minimum_required(VERSION 3.13)

set(PICO_SDK_PATH ${CMAKE_CURRENT_SOURCE_DIR}/pico-sdk)
set(PICO_BOARD pico_w)
set(PICO_PLATFORM rp2040)
include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(trilog C CXX ASM)
set(CMAKE_C_STANDARD 11)

pico_sdk_init()

set(ROOT ${CMAKE_CURRENT_SOURCE_DIR}/..)
set(TRILOG_REL _build/release-rp2040)
set(LIBTRILOG ${ROOT}/${TRILOG_REL}/libtrilog.a)

add_custom_target(libtrilog
  COMMAND make -C ${ROOT} ${TRILOG_REL}/libtrilog.a
          REL=${TRILOG_REL} PLATFORM=no_posix
          "IMAGE_LOAD=consult('pico/server.pl')" IMAGE_DEPS=pico/server.pl
          CC=arm-none-eabi-gcc AR=arm-none-eabi-gcc-ar
          "CFLAGS=-Wall -Wextra -std=c11 -O2 -mcpu=cortex-m0plus -mthumb -DGC_MIN_CELLS=2048 -DARENA_CHUNK_SIZE=4096 -DGC_SHRINK=0"
          "HIDE_INTERNALS=arm-none-eabi-objcopy --wildcard --keep-global-symbol=trilog_* --keep-global-symbol=embedded_files"
  BYPRODUCTS ${LIBTRILOG}
  VERBATIM
)

add_executable(trilog main.c tcp.c vfs.c wifi.c server_pl.S)
add_dependencies(trilog libtrilog)
set_target_properties(trilog PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/trilog"
)
set_source_files_properties(server_pl.S PROPERTIES
  COMPILE_DEFINITIONS "SERVER_PL=\"${CMAKE_CURRENT_SOURCE_DIR}/server.pl\""
  OBJECT_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/server.pl)

target_compile_definitions(trilog PRIVATE PICO_MALLOC_PANIC=0
  "TRILOG_BOARD_NAME=\"${PICO_BOARD}\"")
target_include_directories(trilog PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${ROOT}/include)

pico_enable_stdio_usb(trilog 1)
pico_enable_stdio_uart(trilog 0)

target_link_libraries(trilog ${LIBTRILOG} pico_stdlib pico_cyw43_arch_lwip_threadsafe_background pico_flash m)

pico_add_extra_outputs(trilog)

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
          "IMAGE_LOAD=consult('pico/prolog/main.pl')" "IMAGE_DEPS=pico/prolog/*.pl"
          CC=arm-none-eabi-gcc AR=arm-none-eabi-gcc-ar
          "CFLAGS=-Wall -Wextra -std=c11 -O2 -mcpu=cortex-m0plus -mthumb -DGC_MIN_CELLS=2048 -DARENA_CHUNK_SIZE=4096 -DGC_SHRINK=0"
          "HIDE_INTERNALS=arm-none-eabi-objcopy --wildcard --keep-global-symbol=trilog_* --keep-global-symbol=embedded_files"
  BYPRODUCTS ${LIBTRILOG}
  VERBATIM
)

# Every prolog/*.pl is baked into flash, so /fs can list and serve it.
file(GLOB PROLOG_FILES CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/prolog/*.pl)
set(PROLOG_ASM ".section .rodata\n")
set(PROLOG_TABLE "")
set(i 0)
foreach(f ${PROLOG_FILES})
  get_filename_component(name ${f} NAME)
  string(APPEND PROLOG_ASM ".global prolog_file_${i}\nprolog_file_${i}:\n.incbin \"${f}\"\n.byte 0\n")
  string(APPEND PROLOG_DECLS "extern const char prolog_file_${i}[];\n")
  string(APPEND PROLOG_TABLE "    {\"pico/prolog/${name}\", prolog_file_${i}},\n")
  math(EXPR i "${i} + 1")
endforeach()
file(CONFIGURE OUTPUT prolog_files.S CONTENT "${PROLOG_ASM}")
file(CONFIGURE OUTPUT prolog_files.c CONTENT
  "${PROLOG_DECLS}const char *const prolog_files[][2] = {\n${PROLOG_TABLE}    {0, 0}};\n")

set(SRC ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_executable(trilog ${SRC}/main.c ${SRC}/terminal_pico.c ${SRC}/tcp.c
  ${SRC}/vfs.c ${SRC}/wifi.c ${CMAKE_BINARY_DIR}/prolog_files.S
  ${CMAKE_BINARY_DIR}/prolog_files.c ${ROOT}/cli/toplevel.c)
add_dependencies(trilog libtrilog)
set_target_properties(trilog PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/trilog"
)
set_source_files_properties(${CMAKE_BINARY_DIR}/prolog_files.S PROPERTIES
  OBJECT_DEPENDS "${PROLOG_FILES}")

target_compile_definitions(trilog PRIVATE PICO_MALLOC_PANIC=0 TOPLEVEL_LINE_MAX=256
  "TRILOG_BOARD_NAME=\"${PICO_BOARD}\"")
target_include_directories(trilog PRIVATE ${SRC} ${ROOT}/include ${ROOT}/cli)

pico_enable_stdio_usb(trilog 1)
pico_enable_stdio_uart(trilog 0)

target_link_libraries(trilog ${LIBTRILOG} pico_stdlib hardware_watchdog pico_cyw43_arch_lwip_threadsafe_background pico_flash m)

pico_add_extra_outputs(trilog)

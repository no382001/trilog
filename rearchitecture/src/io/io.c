#include "io.h"
#include <stdio.h>
#include <sys/stat.h>

static io_hooks_t hooks;

static void default_write_str(const char *str, void *ud) {
    (void)ud;
    fputs(str, stdout);
}
static void default_write_err(const char *str, void *ud) {
    (void)ud;
    fputs(str, stderr);
}
static int default_read_char(void *ud) {
    (void)ud;
    return getchar();
}
static char *default_read_line(char *buf, int size, void *ud) {
    (void)ud;
    return fgets(buf, size, stdin);
}
static void *default_file_open(const char *path, const char *mode, void *ud) {
    (void)ud;
    return fopen(path, mode);
}
static void default_file_close(void *handle, void *ud) {
    (void)ud;
    if (handle) fclose(handle);
}
static char *default_file_read_line(void *handle, char *buf, int size, void *ud) {
    (void)ud;
    return fgets(buf, size, handle);
}
static bool default_file_write(void *handle, const char *str, void *ud) {
    (void)ud;
    return fputs(str, handle) >= 0;
}
static bool default_file_exists(const char *path, void *ud) {
    (void)ud;
    struct stat st;
    return stat(path, &st) == 0;
}
static long long default_file_mtime(const char *path, void *ud) {
    (void)ud;
    struct stat st;
    return stat(path, &st) == 0 ? (long long)st.st_mtime : -1LL;
}

void io_hooks_init_default(void) {
    hooks = (io_hooks_t){
        .write_str = default_write_str,
        .write_err = default_write_err,
        .read_char = default_read_char,
        .read_line = default_read_line,
        .file_open = default_file_open,
        .file_close = default_file_close,
        .file_read_line = default_file_read_line,
        .file_write = default_file_write,
        .file_exists = default_file_exists,
        .file_mtime = default_file_mtime,
        .userdata = NULL,
    };
}

io_hooks_t io_hooks_get(void) { return hooks; }
void io_hooks_replace(io_hooks_t h) { hooks = h; }
void io_hooks_restore(io_hooks_t saved) { hooks = saved; }

void io_write_str(const char *str) {
    if (hooks.write_str) hooks.write_str(str, hooks.userdata);
}
void io_write_err(const char *str) {
    if (hooks.write_err) hooks.write_err(str, hooks.userdata);
}
int io_read_char(void) { return hooks.read_char ? hooks.read_char(hooks.userdata) : -1; }
char *io_read_line(char *buf, int size) {
    return hooks.read_line ? hooks.read_line(buf, size, hooks.userdata) : NULL;
}
void *io_file_open(const char *path, const char *mode) {
    return hooks.file_open ? hooks.file_open(path, mode, hooks.userdata) : NULL;
}
void io_file_close(void *handle) {
    if (hooks.file_close) hooks.file_close(handle, hooks.userdata);
}
char *io_file_read_line(void *handle, char *buf, int size) {
    return hooks.file_read_line ? hooks.file_read_line(handle, buf, size, hooks.userdata) : NULL;
}
bool io_file_write(void *handle, const char *str) {
    return hooks.file_write ? hooks.file_write(handle, str, hooks.userdata) : false;
}
bool io_file_exists(const char *path) {
    return hooks.file_exists ? hooks.file_exists(path, hooks.userdata) : false;
}
long long io_file_mtime(const char *path) {
    return hooks.file_mtime ? hooks.file_mtime(path, hooks.userdata) : -1LL;
}

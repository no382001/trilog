#pragma once
#include <stdbool.h>

typedef struct {
    void (*write_str)(const char *str, void *ud);
    void (*write_err)(const char *str, void *ud);
    int (*read_char)(void *ud);
    char *(*read_line)(char *buf, int size, void *ud);
    void *(*file_open)(const char *path, const char *mode, void *ud);
    void (*file_close)(void *handle, void *ud);
    char *(*file_read_line)(void *handle, char *buf, int size, void *ud);
    bool (*file_write)(void *handle, const char *str, void *ud);
    bool (*file_exists)(const char *path, void *ud);
    long long (*file_mtime)(const char *path, void *ud);
    void *userdata;
} io_hooks_t;

void io_hooks_init_default(void);

io_hooks_t io_hooks_get(void);
void io_hooks_replace(io_hooks_t hooks);
void io_hooks_restore(io_hooks_t saved);

void io_write_str(const char *str);
void io_write_err(const char *str);
int io_read_char(void);
char *io_read_line(char *buf, int size);
void *io_file_open(const char *path, const char *mode);
void io_file_close(void *handle);
char *io_file_read_line(void *handle, char *buf, int size);
bool io_file_write(void *handle, const char *str);
bool io_file_exists(const char *path);
long long io_file_mtime(const char *path);

#include <stdio.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 2)
    return 2;
  pid_t pid = fork();
  if (pid == 0) {
    if (!freopen("/dev/null", "w", stdout))
      _exit(126);
    execv(argv[1], argv + 1);
    _exit(127);
  }
  int status;
  struct rusage ru;
  if (pid < 0 || wait4(pid, &status, 0, &ru) < 0)
    return 1;
  printf("%ld\n", ru.ru_maxrss);
  return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

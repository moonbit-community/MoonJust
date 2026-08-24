#include <errno.h>
#include <stdint.h>
#include <stdlib.h>

#include <moonbit.h>

#ifndef _WIN32

#include <signal.h>
#include <sys/types.h>
#include <unistd.h>

/*
 * The payload is a NUL-delimited argv produced by process_group.mbt. It is
 * borrowed only for the duration of this call; execvp either replaces the
 * process or returns and the temporary pointer array is released.
 */
MOONBIT_FFI_EXPORT
int32_t moonjust_process_group_exec(moonbit_bytes_t payload, int32_t length) {
  if (payload == NULL || length <= 0 || payload[length - 1] != 0) {
    return EINVAL;
  }

  int32_t argc = 0;
  for (int32_t index = 0; index < length; ++index) {
    if (payload[index] == 0) {
      ++argc;
    }
  }
  if (argc == 0 || payload[0] == 0) {
    return EINVAL;
  }

  char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
  if (argv == NULL) {
    return ENOMEM;
  }
  int32_t argument = 0;
  int32_t offset = 0;
  while (offset < length && argument < argc) {
    argv[argument++] = (char *)(payload + offset);
    while (offset < length && payload[offset] != 0) {
      ++offset;
    }
    ++offset;
  }
  argv[argc] = NULL;

  if (setpgid(0, 0) != 0) {
    int error = errno;
    free(argv);
    return error;
  }
  execvp(argv[0], argv);
  int error = errno;
  free(argv);
  return error;
}

/* Return the process group ID, zero when the process no longer exists, and a
 * negative errno for an observable failure. EINTR is handled at this boundary
 * so MoonBit never has to retry an interrupted syscall itself. */
MOONBIT_FFI_EXPORT
int32_t moonjust_process_group_id(int32_t pid) {
  pid_t group;
  do {
    group = getpgid((pid_t)pid);
  } while (group < 0 && errno == EINTR);
  if (group < 0) {
    return errno == ESRCH ? 0 : -errno;
  }
  return (int32_t)group;
}

/* Signal an owned process group. Signal zero is used as a non-destructive
 * existence probe. */
MOONBIT_FFI_EXPORT
int32_t moonjust_process_group_signal(int32_t group, int32_t signal) {
  if (group <= 0) {
    return EINVAL;
  }
  int result;
  do {
    result = killpg((pid_t)group, signal);
  } while (result != 0 && errno == EINTR);
  if (result == 0) {
    return 0;
  }
  if (errno == ESRCH) {
    return signal == 0 ? 1 : 0;
  }
  return -errno;
}

#else

MOONBIT_FFI_EXPORT
int32_t moonjust_process_group_exec(moonbit_bytes_t payload, int32_t length) {
  (void)payload;
  (void)length;
  return 95;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_process_group_id(int32_t pid) {
  (void)pid;
  return -95;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_process_group_signal(int32_t group, int32_t signal) {
  (void)group;
  (void)signal;
  return -95;
}

#endif

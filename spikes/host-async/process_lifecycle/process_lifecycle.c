#include <moonbit.h>

#ifndef _WIN32

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static volatile sig_atomic_t moonjust_lifecycle_signal;

static void moonjust_lifecycle_handler(int signal) {
  if (moonjust_lifecycle_signal == 0) {
    moonjust_lifecycle_signal = signal;
  }
}

static void moonjust_lifecycle_signal_mask(sigset_t *previous) {
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGHUP);
  sigaddset(&set, SIGINT);
  sigaddset(&set, SIGQUIT);
  sigaddset(&set, SIGTERM);
  sigprocmask(SIG_BLOCK, &set, previous);
}

MOONBIT_FFI_EXPORT
void moonjust_async_lifecycle_install_signal_observer(void) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = moonjust_lifecycle_handler;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_RESTART;
  sigaction(SIGHUP, &action, NULL);
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGQUIT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_take_observed_signal(void) {
  sigset_t previous;
  moonjust_lifecycle_signal_mask(&previous);
  int32_t signal = moonjust_lifecycle_signal;
  moonjust_lifecycle_signal = 0;
  sigprocmask(SIG_SETMASK, &previous, NULL);
  return signal;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_send_signal(int32_t pid, int32_t signal) {
  if (kill((pid_t)pid, signal) == 0) {
    return 0;
  }
  return errno;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_process_id(void) {
  return (int32_t)getpid();
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_parent_process_id(void) {
  return (int32_t)getppid();
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_process_group_id(void) {
  return (int32_t)getpgid(0);
}

#else

MOONBIT_FFI_EXPORT
void moonjust_async_lifecycle_install_signal_observer(void) {}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_take_observed_signal(void) {
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_send_signal(int32_t pid, int32_t signal) {
  (void)pid;
  (void)signal;
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_process_id(void) {
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_parent_process_id(void) {
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_lifecycle_process_group_id(void) {
  return 0;
}

#endif

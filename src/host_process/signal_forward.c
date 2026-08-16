#include <moonbit.h>

#ifndef _WIN32

#include <signal.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#define MOONJUST_MAX_CHILDREN 1024

static volatile sig_atomic_t moonjust_children[MOONJUST_MAX_CHILDREN];
static volatile sig_atomic_t moonjust_child_signals[MOONJUST_MAX_CHILDREN];

static void moonjust_forward_signal(int signal) {
  for (size_t index = 0; index < MOONJUST_MAX_CHILDREN; ++index) {
    sig_atomic_t pid = moonjust_children[index];
    if (pid > 0) {
      if (moonjust_child_signals[index] == 0) {
        moonjust_child_signals[index] = signal;
      }
      kill((pid_t)pid, signal);
    }
  }
}

static void moonjust_signal_mask(sigset_t *previous) {
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGINT);
  sigaddset(&set, SIGHUP);
  sigaddset(&set, SIGQUIT);
  sigaddset(&set, SIGTERM);
  sigprocmask(SIG_BLOCK, &set, previous);
}

MOONBIT_FFI_EXPORT
void moonjust_configure_signal_forwarding(void) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = moonjust_forward_signal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_RESTART;
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGHUP, &action, NULL);
  sigaction(SIGQUIT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);
}

MOONBIT_FFI_EXPORT
int32_t moonjust_register_signal_child(int32_t pid) {
  sigset_t previous;
  moonjust_signal_mask(&previous);
  int32_t registered = 0;
  for (size_t index = 0; index < MOONJUST_MAX_CHILDREN; ++index) {
    if (moonjust_children[index] == 0) {
      moonjust_children[index] = pid;
      moonjust_child_signals[index] = 0;
      registered = 1;
      break;
    }
  }
  sigprocmask(SIG_SETMASK, &previous, NULL);
  return registered;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_unregister_signal_child(int32_t pid) {
  sigset_t previous;
  moonjust_signal_mask(&previous);
  int32_t signal = 0;
  for (size_t index = 0; index < MOONJUST_MAX_CHILDREN; ++index) {
    if (moonjust_children[index] == pid) {
      signal = moonjust_child_signals[index];
      moonjust_children[index] = 0;
      moonjust_child_signals[index] = 0;
      break;
    }
  }
  sigprocmask(SIG_SETMASK, &previous, NULL);
  return signal;
}

MOONBIT_FFI_EXPORT
void moonjust_kill_signal_child(int32_t pid) {
  kill((pid_t)pid, SIGKILL);
}

#else

MOONBIT_FFI_EXPORT
void moonjust_configure_signal_forwarding(void) {}

MOONBIT_FFI_EXPORT
int32_t moonjust_register_signal_child(int32_t pid) {
  (void)pid;
  return 1;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_unregister_signal_child(int32_t pid) {
  (void)pid;
  return 0;
}

MOONBIT_FFI_EXPORT
void moonjust_kill_signal_child(int32_t pid) {
  (void)pid;
}

#endif

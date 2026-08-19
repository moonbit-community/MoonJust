#include <moonbit.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#endif

#ifndef _WIN32

#include <signal.h>
#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#define MOONJUST_MAX_CHILDREN 1024

static volatile sig_atomic_t moonjust_children[MOONJUST_MAX_CHILDREN];
static volatile sig_atomic_t moonjust_child_signals[MOONJUST_MAX_CHILDREN];
static volatile sig_atomic_t moonjust_child_process_groups[MOONJUST_MAX_CHILDREN];
static volatile sig_atomic_t moonjust_info_requested;
static volatile sig_atomic_t moonjust_signal_request_enabled;
static volatile sig_atomic_t moonjust_signal_request_received;

static void moonjust_record_signal_request(int signal) {
  moonjust_signal_request_received = signal;
}

static void moonjust_forward_signal(int signal) {
  if (moonjust_signal_request_enabled) {
    moonjust_signal_request_received = signal;
    return;
  }
  sig_atomic_t has_children = 0;
  for (size_t index = 0; index < MOONJUST_MAX_CHILDREN; ++index) {
    sig_atomic_t pid = moonjust_children[index];
    if (pid > 0) {
      has_children = 1;
      if (moonjust_child_signals[index] == 0) {
        moonjust_child_signals[index] = signal;
      }
      if (signal == SIGTERM) {
        if (moonjust_child_process_groups[index]) {
          // A recipe may be a shell that has already spawned the actual
          // command. Signal the isolated group so the whole tree exits.
          kill(-(pid_t)pid, signal);
        } else {
          kill((pid_t)pid, signal);
        }
      }
    }
  }
  if (!has_children) {
    _exit(128 + signal);
  }
}

#ifdef SIGINFO
static void moonjust_record_signal_info(int signal) {
  (void)signal;
  moonjust_info_requested = 1;
}
#endif

static void moonjust_signal_mask(sigset_t *previous) {
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGINT);
  sigaddset(&set, SIGHUP);
  sigaddset(&set, SIGQUIT);
  sigaddset(&set, SIGTERM);
#ifdef SIGINFO
  sigaddset(&set, SIGINFO);
#endif
  sigprocmask(SIG_BLOCK, &set, previous);
}

static void moonjust_unblock_forwarding_signals(void) {
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGINT);
  sigaddset(&set, SIGHUP);
  sigaddset(&set, SIGQUIT);
  sigaddset(&set, SIGTERM);
#ifdef SIGINFO
  sigaddset(&set, SIGINFO);
#endif
  sigprocmask(SIG_UNBLOCK, &set, NULL);
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
#ifdef SIGINFO
  action.sa_handler = moonjust_record_signal_info;
  action.sa_flags = 0;
  sigaction(SIGINFO, &action, NULL);
#endif
  moonjust_unblock_forwarding_signals();
}

MOONBIT_FFI_EXPORT
int32_t moonjust_take_signal_info(void) {
  sigset_t previous;
  moonjust_signal_mask(&previous);
  int32_t requested = moonjust_info_requested;
  moonjust_info_requested = 0;
  sigprocmask(SIG_SETMASK, &previous, NULL);
  return requested;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_current_process_id(void) {
  return (int32_t)getpid();
}

MOONBIT_FFI_EXPORT
int32_t moonjust_wait_for_signal_request(void) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = moonjust_record_signal_request;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_RESTART;
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGHUP, &action, NULL);
  sigaction(SIGQUIT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);
  moonjust_unblock_forwarding_signals();
  moonjust_signal_request_received = 0;
  moonjust_signal_request_enabled = 1;
  while (moonjust_signal_request_received == 0) {
    usleep(1000);
  }
  int32_t signal = moonjust_signal_request_received;
  moonjust_signal_request_enabled = 0;
  moonjust_signal_request_received = 0;
  return signal;
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
      moonjust_child_process_groups[index] = 0;
      if (pid > 0) {
        // Isolate the child before it can create descendants. A short retry
        // covers the posix_spawn/exec hand-off without blocking signal code.
        for (int attempt = 0; attempt < 10; ++attempt) {
          if (setpgid((pid_t)pid, (pid_t)pid) == 0) {
            moonjust_child_process_groups[index] = 1;
            break;
          }
          if (errno != EINTR && errno != EACCES) {
            break;
          }
          usleep(1000);
        }
      }
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
      moonjust_child_process_groups[index] = 0;
      break;
    }
  }
  sigprocmask(SIG_SETMASK, &previous, NULL);
  return signal;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_peek_signal_child(int32_t pid) {
  sigset_t previous;
  moonjust_signal_mask(&previous);
  int32_t signal = 0;
  for (size_t index = 0; index < MOONJUST_MAX_CHILDREN; ++index) {
    if (moonjust_children[index] == pid) {
      signal = moonjust_child_signals[index];
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
int32_t moonjust_peek_signal_child(int32_t pid) {
  (void)pid;
  return 0;
}

MOONBIT_FFI_EXPORT
void moonjust_kill_signal_child(int32_t pid) {
  (void)pid;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_take_signal_info(void) {
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_current_process_id(void) {
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_wait_for_signal_request(void) {
  return 0;
}

#endif

#ifdef _WIN32
MOONBIT_FFI_EXPORT
int32_t moonjust_kind_of_fd(HANDLE handle) {
  return GetFileType(handle) == FILE_TYPE_DISK;
}
#else
MOONBIT_FFI_EXPORT
int32_t moonjust_kind_of_fd(int32_t fd) {
  struct stat info;
  return fstat(fd, &info) == 0 && S_ISREG(info.st_mode);
}
#endif

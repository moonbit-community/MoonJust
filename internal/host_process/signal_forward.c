#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>
#include <sys/stat.h>

MOONBIT_FFI_EXPORT
void moonjust_prepare_signal_forwarding(void) {}

MOONBIT_FFI_EXPORT
void moonjust_install_signal_pipe(int32_t fd) {
  (void)fd;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_signal_pipe_overflow(void) {
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_current_process_id(void) {
  return (int32_t)GetCurrentProcessId();
}

MOONBIT_FFI_EXPORT
int32_t moonjust_kind_of_fd(HANDLE handle) {
  return GetFileType(handle) == FILE_TYPE_DISK;
}

#else

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static volatile sig_atomic_t moonjust_signal_fd = -1;
static volatile sig_atomic_t moonjust_signal_overflowed = 0;
static volatile sig_atomic_t moonjust_signal_owner_pid = -1;

static void moonjust_restore_default_and_reraise(int signal) {
  struct sigaction action = {0};
  sigemptyset(&action.sa_mask);
  action.sa_handler = SIG_DFL;
  action.sa_flags = 0;
  sigaction(signal, &action, NULL);
  kill(getpid(), signal);
  _exit(128 + signal);
}

static void moonjust_record_signal(int signal) {
  int saved_errno = errno;
  if (moonjust_signal_owner_pid != (sig_atomic_t)getpid()) {
    moonjust_restore_default_and_reraise(signal);
  }
  int fd = (int)moonjust_signal_fd;
  if (fd >= 0) {
    unsigned char value = (unsigned char)signal;
    ssize_t written = write(fd, &value, sizeof(value));
    if (written != (ssize_t)sizeof(value)) {
      if (errno == EBADF) {
        // The async pipe is close-on-exec. A child that inherited this
        // disposition must retain normal default signal semantics.
        moonjust_restore_default_and_reraise(signal);
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        moonjust_signal_overflowed = 1;
      }
    }
  }
  errno = saved_errno;
}

MOONBIT_FFI_EXPORT
void moonjust_prepare_signal_forwarding(void) {
  // Do not block signals in the process. async may create its spawn worker
  // after this hook, and a blocked mask would be inherited by direct children.
}

MOONBIT_FFI_EXPORT
void moonjust_install_signal_pipe(int32_t fd) {
  struct sigaction action;
  action.sa_handler = moonjust_record_signal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_RESTART;
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGHUP, &action, NULL);
  sigaction(SIGQUIT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);
#ifdef SIGINFO
  sigaction(SIGINFO, &action, NULL);
#endif
  moonjust_signal_fd = (sig_atomic_t)fd;
  moonjust_signal_owner_pid = (sig_atomic_t)getpid();
  moonjust_signal_overflowed = 0;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_signal_pipe_overflow(void) {
  sig_atomic_t overflowed = moonjust_signal_overflowed;
  moonjust_signal_overflowed = 0;
  return overflowed != 0;
}

MOONBIT_FFI_EXPORT
int32_t moonjust_current_process_id(void) {
  return (int32_t)getpid();
}

MOONBIT_FFI_EXPORT
int32_t moonjust_kind_of_fd(int32_t fd) {
  struct stat info;
  return fstat(fd, &info) == 0 && S_ISREG(info.st_mode);
}

#endif

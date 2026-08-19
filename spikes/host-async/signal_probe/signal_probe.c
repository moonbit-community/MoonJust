#include <moonbit.h>

#ifndef _WIN32

#include <signal.h>
#include <string.h>

static volatile sig_atomic_t moonjust_async_probe_seen;

static void moonjust_async_probe_handler(int signal) {
  (void)signal;
  moonjust_async_probe_seen = 1;
}

MOONBIT_FFI_EXPORT
void moonjust_async_install_signal_probe(void) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = moonjust_async_probe_handler;
  sigemptyset(&action.sa_mask);
  sigaction(SIGINT, &action, NULL);
}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_signal_probe_seen(void) {
  return moonjust_async_probe_seen;
}

#else

MOONBIT_FFI_EXPORT
void moonjust_async_install_signal_probe(void) {}

MOONBIT_FFI_EXPORT
int32_t moonjust_async_signal_probe_seen(void) {
  return 0;
}

#endif

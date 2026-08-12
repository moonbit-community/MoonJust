#include <stdint.h>

#ifdef _WIN32
#include <io.h>
#include <stdio.h>
#elif defined(__unix__) || defined(__APPLE__)
#include <unistd.h>
#endif

#include "moonbit.h"

MOONBIT_FFI_EXPORT int32_t moonjust_host_operating_system(void) {
#ifdef _WIN32
  return 3;
#elif defined(__APPLE__) && defined(__MACH__)
  return 2;
#elif defined(__linux__)
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonjust_host_architecture(void) {
#if defined(_M_X64) || defined(__x86_64__)
  return 1;
#elif defined(_M_ARM64) || defined(__aarch64__)
  return 2;
#elif defined(_M_IX86) || defined(__i386__)
  return 3;
#elif defined(_M_ARM) || defined(__arm__)
  return 4;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonjust_host_is_terminal(int32_t stream) {
  if (stream < 0 || stream > 2) return 0;
#ifdef _WIN32
  FILE *file = stream == 0 ? stdin : stream == 1 ? stdout : stderr;
  return _isatty(_fileno(file)) != 0;
#elif defined(__unix__) || defined(__APPLE__)
  return isatty(stream) != 0;
#else
  return 0;
#endif
}

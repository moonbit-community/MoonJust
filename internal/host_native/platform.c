#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
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

MOONBIT_FFI_EXPORT moonbit_string_t
moonjust_host_short_path(moonbit_string_t path) {
#ifdef _WIN32
  WCHAR stack_buffer[1024];
  DWORD capacity = (DWORD)(sizeof(stack_buffer) / sizeof(stack_buffer[0]));
  DWORD length = GetShortPathNameW((LPCWSTR)path, stack_buffer, capacity);
  WCHAR *resolved = stack_buffer;
  if (length >= capacity) {
    capacity = length + 1;
    resolved = (WCHAR *)malloc((size_t)capacity * sizeof(WCHAR));
    if (resolved == NULL) return path;
    length = GetShortPathNameW((LPCWSTR)path, resolved, capacity);
  }
  if (length == 0 || length >= capacity || length > INT32_MAX) {
    if (resolved != stack_buffer) free(resolved);
    return path;
  }
  moonbit_string_t result = moonbit_make_string_raw((int32_t)length);
  memcpy(result, resolved, (size_t)length * sizeof(WCHAR));
  if (resolved != stack_buffer) free(resolved);
  return result;
#else
  return path;
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

MOONBIT_FFI_EXPORT int32_t moonjust_host_pid(void) {
#ifdef _WIN32
  return (int32_t)GetCurrentProcessId();
#elif defined(__unix__) || defined(__APPLE__)
  return (int32_t)getpid();
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonjust_host_num_cpus(void) {
#ifdef _WIN32
  SYSTEM_INFO info;
  GetSystemInfo(&info);
  return (int32_t)info.dwNumberOfProcessors;
#elif defined(__unix__) || defined(__APPLE__)
  long count = sysconf(_SC_NPROCESSORS_ONLN);
  return count > 0 && count <= INT32_MAX ? (int32_t)count : 0;
#else
  return 0;
#endif
}

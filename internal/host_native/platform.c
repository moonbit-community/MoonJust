#include <stdint.h>
#include <stdio.h>
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

#if defined(__unix__) || defined(__APPLE__)
static int moonjust_cwd_nonunicode = 0;
static int moonjust_cwd_warning_emitted = 0;
static int moonjust_justfile_warning_emitted = 0;

static int moonjust_valid_utf8(const unsigned char *value, size_t length) {
  size_t index = 0;
  while (index < length) {
    unsigned char byte = value[index++];
    if (byte < 0x80) continue;
    size_t continuation = 0;
    uint32_t codepoint = 0;
    if (byte >= 0xc2 && byte <= 0xdf) {
      continuation = 1;
      codepoint = byte & 0x1f;
    } else if (byte >= 0xe0 && byte <= 0xef) {
      continuation = 2;
      codepoint = byte & 0x0f;
    } else if (byte >= 0xf0 && byte <= 0xf4) {
      continuation = 3;
      codepoint = byte & 0x07;
    } else {
      return 0;
    }
    if (index + continuation > length) return 0;
    for (size_t offset = 0; offset < continuation; offset++) {
      unsigned char next = value[index++];
      if ((next & 0xc0) != 0x80) return 0;
      codepoint = (codepoint << 6) | (next & 0x3f);
    }
    if ((continuation == 2 && codepoint < 0x800) ||
        (continuation == 3 && codepoint < 0x10000) ||
        (codepoint >= 0xd800 && codepoint <= 0xdfff) ||
        codepoint > 0x10ffff) {
      return 0;
    }
  }
  return 1;
}

static void moonjust_warn_nonunicode_cwd(const char *path, size_t length) {
  if (moonjust_cwd_warning_emitted) return;
  moonjust_cwd_warning_emitted = 1;
  fprintf(stderr, "The invocation directory path `");
  for (size_t index = 0; index < length; index++) {
    unsigned char byte = (unsigned char)path[index];
    if (byte >= 0x20 && byte <= 0x7e && byte != '`') {
      fputc((int)byte, stderr);
    } else {
      fputc('?', stderr);
    }
  }
  fprintf(
      stderr,
      "` is not Unicode. Just is considering phasing-out support for "
      "non-Unicode paths. If you see this warning, please leave a comment on "
      "https://github.com/casey/just/issues/3229. Thank you!\n");
  fflush(stderr);
}

static void moonjust_warn_nonunicode_justfile(void) {
  if (moonjust_justfile_warning_emitted) return;
  moonjust_justfile_warning_emitted = 1;
  fprintf(
      stderr,
      "The justfile path `?` is not Unicode. Just is considering phasing-out "
      "support for non-Unicode paths. If you see this warning, please leave a "
      "comment on https://github.com/casey/just/issues/3229. Thank you!\n");
  fflush(stderr);
}
#endif

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

MOONBIT_FFI_EXPORT moonbit_string_t moonjust_host_current_dir(void) {
#ifdef _WIN32
  WCHAR stack_buffer[1024];
  DWORD capacity = (DWORD)(sizeof(stack_buffer) / sizeof(stack_buffer[0]));
  DWORD length = GetCurrentDirectoryW(capacity, stack_buffer);
  WCHAR *resolved = stack_buffer;
  if (length >= capacity) {
    capacity = length + 1;
    resolved = (WCHAR *)malloc((size_t)capacity * sizeof(WCHAR));
    if (resolved == NULL) return moonbit_make_string_raw(0);
    length = GetCurrentDirectoryW(capacity, resolved);
  }
  if (length == 0 || length >= capacity || length > INT32_MAX) {
    if (resolved != stack_buffer) free(resolved);
    return moonbit_make_string_raw(0);
  }
  moonbit_string_t result = moonbit_make_string_raw((int32_t)length);
  memcpy(result, resolved, (size_t)length * sizeof(WCHAR));
  if (resolved != stack_buffer) free(resolved);
  return result;
#else
  return moonbit_make_string_raw(0);
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonjust_host_current_dir_bytes(void) {
#if defined(__unix__) || defined(__APPLE__)
  char *path = getcwd(NULL, 0);
  if (path == NULL) return moonbit_make_bytes(0, 0);
  size_t length = strlen(path);
  if (length > INT32_MAX) {
    free(path);
    return moonbit_make_bytes(0, 0);
  }
  moonjust_cwd_nonunicode = !moonjust_valid_utf8((const unsigned char *)path, length);
  if (moonjust_cwd_nonunicode) {
    moonjust_warn_nonunicode_cwd(path, length);
  }
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, path, length);
  free(path);
  return result;
#else
  return moonbit_make_bytes(0, 0);
#endif
}

MOONBIT_FFI_EXPORT int32_t moonjust_host_cwd_is_nonunicode(void) {
#if defined(__unix__) || defined(__APPLE__)
  return moonjust_cwd_nonunicode;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT void moonjust_host_warn_nonunicode_justfile(void) {
#if defined(__unix__) || defined(__APPLE__)
  if (moonjust_cwd_nonunicode) moonjust_warn_nonunicode_justfile();
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

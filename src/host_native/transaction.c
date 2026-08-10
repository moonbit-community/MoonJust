#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <time.h>

#ifdef _WIN32
#include <io.h>
#include <limits.h>
#include <share.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

#include "moonbit.h"

#ifdef _WIN32
typedef moonbit_string_t moonjust_native_path_t;
#else
typedef moonbit_bytes_t moonjust_native_path_t;
#endif

static int moonjust_status_from_errno(int error) {
  if (error == EEXIST) return 1;
  if (error == EACCES || error == EPERM || error == EROFS) return 2;
  if (error == ENOENT || error == ENOTDIR) return 3;
  return 4;
}

MOONBIT_FFI_EXPORT int moonjust_host_create_exclusive(
    moonjust_native_path_t path, moonbit_bytes_t contents) {
  int descriptor = -1;
#ifdef _WIN32
  errno_t opened = _wsopen_s(
      &descriptor,
      (const wchar_t *)path,
      _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY,
      _SH_DENYRW,
      _S_IREAD | _S_IWRITE);
  if (opened != 0) return moonjust_status_from_errno((int)opened);
#else
  descriptor = open((const char *)path, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (descriptor < 0) return moonjust_status_from_errno(errno);
#endif
  size_t length = Moonbit_array_length(contents);
  size_t offset = 0;
  while (offset < length) {
#ifdef _WIN32
    size_t remaining = length - offset;
    unsigned int chunk = remaining > INT_MAX ? INT_MAX : (unsigned int)remaining;
    int written = _write(descriptor, contents + offset, chunk);
#else
    ssize_t written = write(descriptor, contents + offset, length - offset);
#endif
    if (written <= 0) {
      int error = errno;
#ifdef _WIN32
      _close(descriptor);
      _wremove((const wchar_t *)path);
#else
      close(descriptor);
      unlink((const char *)path);
#endif
      return moonjust_status_from_errno(error);
    }
    offset += (size_t)written;
  }
#ifdef _WIN32
  int sync_result = _commit(descriptor);
  int sync_error = errno;
  int close_result = _close(descriptor);
  int close_error = errno;
  if (sync_result != 0 || close_result != 0) {
    int error = sync_result != 0 ? sync_error : close_error;
    _wremove((const wchar_t *)path);
#else
  int sync_result = fsync(descriptor);
  int sync_error = errno;
  int close_result = close(descriptor);
  int close_error = errno;
  if (sync_result != 0 || close_result != 0) {
    int error = sync_result != 0 ? sync_error : close_error;
    unlink((const char *)path);
#endif
    return moonjust_status_from_errno(error);
  }
  return 0;
}

MOONBIT_FFI_EXPORT int64_t moonjust_host_now_millis(void) {
#ifdef _WIN32
  FILETIME value;
  GetSystemTimeAsFileTime(&value);
  ULARGE_INTEGER ticks;
  ticks.LowPart = value.dwLowDateTime;
  ticks.HighPart = value.dwHighDateTime;
  return (int64_t)(ticks.QuadPart / 10000ULL) - 11644473600000LL;
#else
  struct timespec value;
  if (clock_gettime(CLOCK_REALTIME, &value) != 0) return -1;
  return (int64_t)value.tv_sec * 1000LL + value.tv_nsec / 1000000LL;
#endif
}

MOONBIT_FFI_EXPORT int moonjust_host_persist_temp(
    moonjust_native_path_t temporary,
    moonjust_native_path_t destination,
    int overwrite) {
#ifdef _WIN32
  DWORD destination_attributes = GetFileAttributesW((const wchar_t *)destination);
  if (destination_attributes != INVALID_FILE_ATTRIBUTES &&
      (destination_attributes & FILE_ATTRIBUTE_READONLY)) {
    return 2;
  }
  DWORD flags = MOVEFILE_WRITE_THROUGH;
  if (overwrite) flags |= MOVEFILE_REPLACE_EXISTING;
  if (MoveFileExW(
          (const wchar_t *)temporary,
          (const wchar_t *)destination,
          flags)) {
    return 0;
  }
  DWORD error = GetLastError();
  if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS) return 1;
  if (error == ERROR_ACCESS_DENIED || error == ERROR_SHARING_VIOLATION) return 2;
  if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) return 3;
  return 4;
#else
  if (overwrite) {
    struct stat metadata;
    if (stat((const char *)destination, &metadata) == 0) {
      if ((metadata.st_mode & 0222) == 0) return 2;
      if (chmod((const char *)temporary, metadata.st_mode & 07777) != 0) {
        return moonjust_status_from_errno(errno);
      }
    } else if (errno != ENOENT) {
      return moonjust_status_from_errno(errno);
    }
    if (rename((const char *)temporary, (const char *)destination) == 0) return 0;
    return moonjust_status_from_errno(errno);
  }
  if (link((const char *)temporary, (const char *)destination) != 0) {
    return moonjust_status_from_errno(errno);
  }
  if (unlink((const char *)temporary) != 0) {
    int error = errno;
    unlink((const char *)destination);
    return moonjust_status_from_errno(error);
  }
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int moonjust_host_set_readonly_for_test(
    moonjust_native_path_t path, int readonly) {
#ifdef _WIN32
  DWORD attributes = GetFileAttributesW((const wchar_t *)path);
  if (attributes == INVALID_FILE_ATTRIBUTES) return 3;
  if (readonly) {
    attributes |= FILE_ATTRIBUTE_READONLY;
  } else {
    attributes &= ~FILE_ATTRIBUTE_READONLY;
  }
  return SetFileAttributesW((const wchar_t *)path, attributes) ? 0 : 4;
#else
  struct stat metadata;
  if (stat((const char *)path, &metadata) != 0) {
    return moonjust_status_from_errno(errno);
  }
  mode_t mode = metadata.st_mode;
  if (readonly) {
    mode &= ~0222;
  } else {
    mode |= 0200;
  }
  return chmod((const char *)path, mode) == 0
      ? 0
      : moonjust_status_from_errno(errno);
#endif
}

MOONBIT_FFI_EXPORT int moonjust_host_set_executable(
    moonjust_native_path_t path) {
#ifdef _WIN32
  (void)path;
  return 0;
#else
  struct stat metadata;
  if (stat((const char *)path, &metadata) != 0) {
    return moonjust_status_from_errno(errno);
  }
  return chmod((const char *)path, metadata.st_mode | 0100) == 0
      ? 0
      : moonjust_status_from_errno(errno);
#endif
}

MOONBIT_FFI_EXPORT int moonjust_host_symlink_for_test(
    moonjust_native_path_t target, moonjust_native_path_t link_path) {
#ifdef _WIN32
#ifndef SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
#define SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE 0x2
#endif
  if (CreateSymbolicLinkW(
          (const wchar_t *)link_path,
          (const wchar_t *)target,
          SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE)) {
    return 0;
  }
  DWORD error = GetLastError();
  if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS) return 1;
  if (error == ERROR_ACCESS_DENIED || error == ERROR_PRIVILEGE_NOT_HELD) return 2;
  if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) return 3;
  return 4;
#else
  return symlink((const char *)target, (const char *)link_path) == 0
      ? 0
      : moonjust_status_from_errno(errno);
#endif
}

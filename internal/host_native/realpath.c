#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>
#include <stdio.h>
#include <sys/stat.h>
#include <wchar.h>

#ifdef _WIN32
#include <direct.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

#include "moonbit.h"

#ifdef _WIN32
typedef moonbit_string_t moonjust_native_path_t;

MOONBIT_FFI_EXPORT moonbit_string_t
moonjust_host_realpath(moonjust_native_path_t path) {
  HANDLE handle = CreateFileW(
      (LPCWSTR)path,
      0,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      NULL,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL | FILE_FLAG_BACKUP_SEMANTICS,
      NULL);
  if (handle == INVALID_HANDLE_VALUE) {
    return moonbit_make_string_raw(0);
  }
  WCHAR stack_buffer[1024];
  WCHAR *resolved = stack_buffer;
  DWORD capacity = (DWORD)(sizeof(stack_buffer) / sizeof(stack_buffer[0]));
  DWORD length = GetFinalPathNameByHandleW(
      handle,
      resolved,
      capacity,
      FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (length >= capacity) {
    capacity = length + 1;
    resolved = (WCHAR *)malloc((size_t)capacity * sizeof(WCHAR));
    if (resolved != NULL) {
      length = GetFinalPathNameByHandleW(
          handle,
          resolved,
          capacity,
          FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    }
  }
  CloseHandle(handle);
  if (resolved == NULL || length == 0 || length >= capacity || length > INT32_MAX) {
    if (resolved != stack_buffer) free(resolved);
    return moonbit_make_string_raw(0);
  }

  DWORD source_offset = 0;
  DWORD result_length = length;
  int unc = length >= 8 && wcsncmp(resolved, L"\\\\?\\UNC\\", 8) == 0;
  if (unc) {
    source_offset = 8;
    result_length = length - 6;
  } else if (length >= 4 && wcsncmp(resolved, L"\\\\?\\", 4) == 0) {
    source_offset = 4;
    result_length = length - 4;
  }
  moonbit_string_t result = moonbit_make_string_raw((int32_t)result_length);
  DWORD result_offset = 0;
  if (unc) {
    result[0] = L'\\';
    result[1] = L'\\';
    result_offset = 2;
  }
  memcpy(
      result + result_offset,
      resolved + source_offset,
      (length - source_offset) * sizeof(WCHAR));
  if (resolved != stack_buffer) free(resolved);
  return result;
}
#else
typedef moonbit_bytes_t moonjust_native_path_t;

MOONBIT_FFI_EXPORT moonbit_bytes_t
moonjust_host_realpath(moonjust_native_path_t path) {
  char *resolved = realpath((const char *)path, NULL);
  if (resolved == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  size_t length = strlen(resolved);
  moonbit_bytes_t result = moonbit_make_bytes(length, 0);
  memcpy(result, resolved, length);
  free(resolved);
  return result;
}
#endif

MOONBIT_FFI_EXPORT int64_t
moonjust_host_file_size(moonjust_native_path_t path) {
#ifdef _WIN32
  struct _stat64 info;
  if (_wstat64((const wchar_t *)path, &info) != 0) {
    return -1;
  }
#else
  struct stat info;
  if (stat((const char *)path, &info) != 0) {
    return -1;
  }
#endif
  return (int64_t)info.st_size;
}

MOONBIT_FFI_EXPORT int32_t
moonjust_host_file_executable(moonjust_native_path_t path) {
#ifdef _WIN32
  return _waccess((const wchar_t *)path, 0) == 0;
#else
  return access((const char *)path, X_OK) == 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
moonjust_host_read_file_range(
  moonjust_native_path_t path,
  int64_t offset,
  int32_t length
) {
  if (offset < 0 || length < 0) {
    return moonbit_make_bytes(0, 0);
  }
#ifdef _WIN32
  FILE *file = _wfopen((const wchar_t *)path, L"rb");
#else
  FILE *file = fopen((const char *)path, "rb");
#endif
  if (file == NULL) {
    return moonbit_make_bytes(0, 0);
  }
#ifdef _WIN32
  int seek_result = _fseeki64(file, offset, SEEK_SET);
#else
  int seek_result = fseeko(file, (off_t)offset, SEEK_SET);
#endif
  if (seek_result != 0) {
    fclose(file);
    return moonbit_make_bytes(0, 0);
  }
  unsigned char *buffer = NULL;
  if (length > 0) {
    buffer = (unsigned char *)malloc((size_t)length);
    if (buffer == NULL) {
      fclose(file);
      return moonbit_make_bytes(0, 0);
    }
  }
  size_t count = fread(buffer, 1, (size_t)length, file);
  fclose(file);
  moonbit_bytes_t result = moonbit_make_bytes(count, 0);
  if (count > 0) {
    memcpy(result, buffer, count);
  }
  free(buffer);
  return result;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
moonjust_host_read_file_stream(moonjust_native_path_t path) {
#ifdef _WIN32
  FILE *file = _wfopen((const wchar_t *)path, L"rb");
#else
  FILE *file = fopen((const char *)path, "rb");
#endif
  if (file == NULL) {
    return moonbit_make_bytes(1, 0);
  }
  size_t capacity = 4096;
  size_t length = 0;
  unsigned char *buffer = (unsigned char *)malloc(capacity);
  if (buffer == NULL) {
    fclose(file);
    return moonbit_make_bytes(1, 0);
  }
  while (1) {
    if (length == capacity) {
      if (capacity > (size_t)INT32_MAX / 2) {
        free(buffer);
        fclose(file);
        return moonbit_make_bytes(1, 0);
      }
      capacity *= 2;
      unsigned char *grown = (unsigned char *)realloc(buffer, capacity);
      if (grown == NULL) {
        free(buffer);
        fclose(file);
        return moonbit_make_bytes(1, 0);
      }
      buffer = grown;
    }
    size_t count = fread(buffer + length, 1, capacity - length, file);
    length += count;
    if (count == 0) {
      if (ferror(file)) {
        free(buffer);
        fclose(file);
        return moonbit_make_bytes(1, 0);
      }
      break;
    }
  }
  if (length > (size_t)INT32_MAX - 1 || fclose(file) != 0) {
    free(buffer);
    return moonbit_make_bytes(1, 0);
  }
  moonbit_bytes_t result = moonbit_make_bytes(length + 1, 0);
  result[0] = 1;
  if (length > 0) {
    memcpy(result + 1, buffer, length);
  }
  free(buffer);
  return result;
}

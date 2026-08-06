#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <direct.h>
#else
#include <limits.h>
#include <unistd.h>
#endif

#include "moonbit.h"

MOONBIT_FFI_EXPORT moonbit_bytes_t
moonjust_host_realpath(moonbit_bytes_t path) {
#ifdef _WIN32
  char *resolved = _fullpath(NULL, (const char *)path, 0);
#else
  char *resolved = realpath((const char *)path, NULL);
#endif
  if (resolved == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  size_t length = strlen(resolved);
  moonbit_bytes_t result = moonbit_make_bytes(length, 0);
  memcpy(result, resolved, length);
  free(resolved);
  return result;
}

MOONBIT_FFI_EXPORT int64_t
moonjust_host_file_size(moonbit_bytes_t path) {
#ifdef _WIN32
  struct _stat64 info;
  if (_stat64((const char *)path, &info) != 0) {
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

MOONBIT_FFI_EXPORT moonbit_bytes_t
moonjust_host_read_file_range(
  moonbit_bytes_t path,
  int64_t offset,
  int32_t length
) {
  if (offset < 0 || length < 0) {
    return moonbit_make_bytes(0, 0);
  }
  FILE *file = fopen((const char *)path, "rb");
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

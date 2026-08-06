#include <stdlib.h>
#include <string.h>

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

#ifdef __cplusplus
extern "C" {
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

// Execute a command and capture its stdout output
MOONBIT_FFI_EXPORT moonbit_bytes_t
mizchi_tomate_provider_exec_command(moonbit_bytes_t cmd) {
  FILE *fp = popen((const char *)cmd, "r");
  if (fp == NULL) {
    // Return empty bytes on failure
    return moonbit_make_bytes(0, 0);
  }

  // Read output in chunks
  size_t capacity = 4096;
  size_t length = 0;
  char *buffer = (char *)malloc(capacity);
  if (buffer == NULL) {
    pclose(fp);
    return moonbit_make_bytes(0, 0);
  }

  size_t n;
  while ((n = fread(buffer + length, 1, capacity - length, fp)) > 0) {
    length += n;
    if (length >= capacity) {
      capacity *= 2;
      char *new_buf = (char *)realloc(buffer, capacity);
      if (new_buf == NULL) {
        free(buffer);
        pclose(fp);
        return moonbit_make_bytes(0, 0);
      }
      buffer = new_buf;
    }
  }

  pclose(fp);

  moonbit_bytes_t result = moonbit_make_bytes(length, 0);
  memcpy(result, buffer, length);
  free(buffer);
  return result;
}

// Execute a command and return exit code
MOONBIT_FFI_EXPORT int
mizchi_tomate_provider_system_command(moonbit_bytes_t cmd) {
  return system((const char *)cmd);
}

#ifdef __cplusplus
}
#endif

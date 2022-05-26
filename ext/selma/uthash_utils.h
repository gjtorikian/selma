#ifndef _UTHASH_UTILS_H
#define _UTHASH_UTILS_H

#include "utarray_utils.h"

#include "uthash/uthash.h"

typedef struct StringHash {
  char *key;
  StringArray *values;
  UT_hash_handle hh;         /* makes this structure hashable */
} StringHash;

#endif

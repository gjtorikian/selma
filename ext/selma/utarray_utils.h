#ifndef _UTARRAY_UTILS_H
#define _UTARRAY_UTILS_H

#include "uthash/utarray.h"

typedef UT_array StringArray;

bool string_list_contains(StringArray *attributes, const char *name);
bool string_list_present(StringArray *list);
void set_in_string_list(StringArray *set, VALUE rb_attr, bool allow);
VALUE string_list_to_rb(StringArray *set);
void string_list_free(StringArray *list);

#endif

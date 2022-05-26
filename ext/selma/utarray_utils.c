#include <ruby.h>
#include <ruby/util.h>
#include <stdbool.h>
#include <string.h>

#include "selma.h"
#include "selma_utils.h"
#include "utarray_utils.h"

#include "uthash/utarray.h"

bool
string_list_contains(StringArray *list, const char *name)
{
  size_t len = utarray_len(list);

  for (size_t i = 0; i < len; i++) {
    char *str = *(char **)utarray_eltptr(list, i);
    if (!strcmp(str, name)) {
      return true;
    }
  }

  return false;
}

bool
string_list_present(StringArray *list)
{
  return utarray_len(list) > 0;
}

void
set_in_string_list(StringArray *list, VALUE rb_attr, bool allow)
{
  selma_utf8_strcheck(rb_attr);
  const char *attr = StringValueCStr(rb_attr);

  if (allow) {
    utarray_push_back(list, &attr);
  } else {
    size_t len = utarray_len(list);

    for (size_t i = 0; i < len; i++) {
      char *str = *(char **)utarray_eltptr(list, i);
      if (!strcmp(str, attr)) {
        utarray_erase(list, i, 1);
        break;
      }
    }
  }
}

VALUE
string_list_to_rb(StringArray *list)
{
  size_t len =  utarray_len(list);

  VALUE rb_array = rb_ary_new2(len);

  for (size_t i = 0; i < len; i++) {
    char *str = (char *)utarray_eltptr(list, i);
    rb_ary_push(rb_array, rb_str_new2(str));
  }

  return rb_array;
}

void
string_list_free(StringArray *list)
{
  utarray_free(list);
}

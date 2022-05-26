#include <ruby.h>

#include "selma.h"
#include "selma_utils.h"

#include "lol_html.h"
#include "uthash/utstring.h"

VALUE
rb_selma_element_to_s(VALUE self)
{
  UT_string *out;
  lol_html_element_t *element;

  Data_Get_Struct(self, lol_html_element_t, element);

  lol_html_str_t str = lol_html_element_tag_name_get(element);

  utstring_new(out);
  utstring_printf(out, "%s", str.data);
  lol_html_str_free(str);

  return utstring_to_rb(out, true);
}

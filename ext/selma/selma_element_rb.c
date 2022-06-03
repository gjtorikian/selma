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

VALUE
rb_selma_element_attr_get(VALUE rb_self, VALUE rb_key)
{
  lol_html_element_t *element;

  Data_Get_Struct(rb_self, lol_html_element_t, element);

  char *key = StringValueCStr(rb_key);
  size_t key_len = strlen(key);
  int fetch_status = lol_html_element_has_attribute(element, key, key_len);

  if (fetch_status == 0) {
    return Qnil;
  } else if (fetch_status < 0) {
    raise_lol_html_error();
  } else {
    lol_html_str_t attr = lol_html_element_get_attribute(element, key, key_len);
    return rb_enc_str_new_cstr(attr.data, rb_utf8_encoding());
  }
}

VALUE
rb_selma_element_attr_set(VALUE rb_self, VALUE rb_key, VALUE rb_value)
{
  lol_html_element_t *element;
  Data_Get_Struct(rb_self, lol_html_element_t, element);

  int status = lol_html_element_set_attribute(element, RSTRING_PTR(rb_key), RSTRING_LEN(rb_key), RSTRING_PTR(rb_value),
               RSTRING_LEN(rb_value));
  if (status) {
    raise_lol_html_error();
  }

  return rb_value;
}

VALUE
rb_selma_element_attr_remove(VALUE rb_self, VALUE rb_attr)
{
  lol_html_element_t *element;

  Data_Get_Struct(rb_self, lol_html_element_t, element);

  char *attr = StringValueCStr(rb_attr);
  size_t attr_len = strlen(attr);
  int has_attr = lol_html_element_has_attribute(element, attr, attr_len);
  int remove_status;

  if (has_attr == 0) {
    return Qnil;
  } else if (has_attr < 0) {
    raise_lol_html_error();
  } else {
    remove_status = lol_html_element_remove_attribute(element, attr, attr_len);
    if (!remove_status) {

      return Qtrue;
    } else {
      raise_lol_html_error();
    }
  }
}

VALUE
rb_selma_element_attributes(VALUE rb_self)
{
  lol_html_element_t *element;
  Data_Get_Struct(rb_self, lol_html_element_t, element);
  VALUE rb_attributes;

  lol_html_attributes_iterator_t *iter =
    lol_html_attributes_iterator_get(element);
  const lol_html_attribute_t *attr;

  rb_attributes = rb_hash_new();

  while ((attr = lol_html_attributes_iterator_next(iter))) {
    lol_html_str_t attr_name_str = lol_html_attribute_name_get(attr);
    lol_html_str_t attr_value_str = lol_html_attribute_value_get(attr);

    rb_hash_aset(rb_attributes, rb_str_new(attr_name_str.data, attr_name_str.len), rb_str_new(attr_value_str.data, attr_value_str.len));

    lol_html_str_free(attr_name_str);
    lol_html_str_free(attr_value_str);
  }

  return rb_attributes;
}

void
Init_selma_element_rb(void)
{
  rb_cElement = rb_define_class_under(rb_mSelma, "Element", rb_cHTML);

  rb_define_method(rb_cElement, "[]", rb_selma_element_attr_get, 1);
  rb_define_method(rb_cElement, "[]=", rb_selma_element_attr_set, 2);
  rb_define_method(rb_cElement, "remove_attribute", rb_selma_element_attr_remove, 1);
  rb_define_method(rb_cElement, "attributes", rb_selma_element_attributes, 0);
  // rb_define_method(rb_cElement, "children!", rb_selma_element_children_load, 0);
  // rb_define_method(rb_cElement, "text_content", rb_selma_element_text_content, 0);
  // rb_define_method(rb_cElement, "to_html", rb_selma_element_to_html, 0);
  rb_define_method(rb_cElement, "to_s", rb_selma_element_to_s, 0);
  // rb_define_method(rb_cElement, "inner_html", rb_selma_element_inner_html, 0);
  // rb_define_method(rb_cElement, "select", rb_selma_select, 1);
}

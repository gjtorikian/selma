#include <ruby/util.h>

#include "selma.h"
#include "selma_sanitizer.h"
#include "utarray_utils.h"
#include "selma.h"

#include "nokogiri-gumbo-parser/nokogiri_gumbo.h"
#include "uthash/utarray.h"

VALUE rb_cSanitizer;
VALUE rb_mConfig;
ID rb_selma_id_relative;

static VALUE
rb_selma_sanitizer_get_all_flags(VALUE rb_self)
{
  VALUE rb_flags = rb_hash_new();
  SelmaSanitizer *sanitizer;
  long i;

  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);

  for (i = 0; i < GUMBO_TAG_UNKNOWN; ++i) {
    if (sanitizer->flags[i]) {
      rb_hash_aset(rb_flags, gumbo_tag_to_rb((GumboTag)i),
                   INT2FIX(sanitizer->flags[i]));
    }
  }

  return rb_flags;
}

static int
each_element_sanitizer(st_data_t _tag, st_data_t _sef, st_data_t _payload)
{
  GumboTag tag = (GumboTag)_tag;
  SelmaElementSanitizer *sef = (SelmaElementSanitizer *)_sef;
  VALUE rb_allowed = (VALUE)_payload;

  rb_hash_aset(rb_allowed, gumbo_tag_to_rb(tag), string_list_to_rb(sef->allowed_attrs));
  return ST_CONTINUE;
}


static VALUE
rb_selma_sanitizer_allowed_attributes(VALUE rb_self)
{
  VALUE rb_allowed = rb_hash_new();
  SelmaSanitizer *sanitizer;

  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);

  if (string_list_present(sanitizer->allowed_attrs)) {
    rb_hash_aset(rb_allowed, ID2SYM(rb_intern("all")),
                 string_list_to_rb(sanitizer->allowed_attrs));
  }

  Check_Type(rb_allowed, T_HASH);

  st_foreach(sanitizer->element_sanitizers, &each_element_sanitizer,
             (st_data_t)rb_allowed);

  return rb_allowed;
}

static void
set_element_flags_1(uint8_t *flags, VALUE rb_tag, bool set,
                    int flag)
{
  GumboTag t = gumbo_tag_from_rb(rb_tag);
  if (set) {
    flags[(int)t] |= flag;
  } else {
    flags[(int)t] &= ~flag;
  }
}

void
selma_set_element_flags(uint8_t *flags, VALUE rb_el, bool set, int flag)
{
  if (RB_TYPE_P(rb_el, T_ARRAY)) {
    long i;
    for (i = 0; i < RARRAY_LEN(rb_el); ++i) {
      set_element_flags_1(flags, RARRAY_AREF(rb_el, i), set, flag);
    }
  } else {
    set_element_flags_1(flags, rb_el, set, flag);
  }
}

static VALUE
rb_selma_sanitizer_set_flag(VALUE rb_self, VALUE rb_element,
                            VALUE rb_flag, VALUE rb_bool)
{
  SelmaSanitizer *sanitizer;
  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);
  Check_Type(rb_flag, T_FIXNUM);
  selma_set_element_flags(sanitizer->flags, rb_element, RTEST(rb_bool),
                          FIX2INT(rb_flag));
  return Qnil;
}

static VALUE
rb_selma_sanitizer_set_all_flags(VALUE rb_self, VALUE rb_flag,
                                 VALUE rb_bool)
{
  long i;
  uint8_t flag;
  SelmaSanitizer *sanitizer;
  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);

  Check_Type(rb_flag, T_FIXNUM);
  flag = FIX2INT(rb_flag);

  if (RTEST(rb_bool)) {
    for (i = 0; i < GUMBO_TAG_UNKNOWN; ++i) {
      sanitizer->flags[i] |= flag;
    }
  } else {
    for (i = 0; i < GUMBO_TAG_UNKNOWN; ++i) {
      sanitizer->flags[i] &= ~flag;
    }
  }

  return Qnil;
}

static VALUE
rb_selma_sanitizer_allowed_protocols(VALUE rb_self,
                                     VALUE rb_elem,
                                     VALUE rb_attribute,
                                     VALUE rb_allowed)
{
  SelmaSanitizer *sanitizer;
  SelmaElementSanitizer *element_sanitizer = NULL;
  StringHash *protocol_sanitizer = NULL;
  long i;

  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);
  element_sanitizer =
    selma_sanitizer_get_element_sanitizer(sanitizer, gumbo_tag_from_rb(rb_elem));

  Check_Type(rb_attribute, T_STRING);
  const char *attr = StringValueCStr(rb_attribute);
  protocol_sanitizer = selma_get_protocol_sanitizers(element_sanitizer, attr);

  Check_Type(rb_allowed, T_ARRAY);
  for (i = 0; i < RARRAY_LEN(rb_allowed); ++i) {
    VALUE rb_proto = RARRAY_AREF(rb_allowed, i);
    char *protocol_name;

    if (SYMBOL_P(rb_proto) && SYM2ID(rb_proto) == rb_selma_id_relative) {
      protocol_name = malloc(2);
      protocol_name[0] = '#';
      protocol_name[1] = '\0';
      utarray_push_back(protocol_sanitizer->values, &protocol_name);
      protocol_name[0] = '/';
      utarray_push_back(protocol_sanitizer->values, &protocol_name);
      free(protocol_name);
    } else {
      Check_Type(rb_proto, T_STRING);
      protocol_name = downcase(StringValueCStr(rb_proto), RSTRING_LEN(rb_proto));
      utarray_push_back(protocol_sanitizer->values, &protocol_name);
      free(protocol_name);
    }
  }

  return Qnil;
}

static VALUE
rb_selma_sanitizer_set_allow_comments(VALUE rb_self,
                                      VALUE rb_bool)
{
  SelmaSanitizer *sanitizer;
  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);
  sanitizer->allow_comments = RTEST(rb_bool);
  return rb_bool;
}

static VALUE
rb_selma_sanitizer_set_allow_doctype(VALUE rb_self,
                                     VALUE rb_bool)
{
  SelmaSanitizer *sanitizer;
  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);
  sanitizer->allow_doctype = RTEST(rb_bool);
  return rb_bool;
}

static VALUE
rb_selma_sanitizer_set_name_prefix(VALUE rb_self,
                                   VALUE rb_prefix)
{
  SelmaSanitizer *sanitizer;
  const char *prefix = NULL;
  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);

  if (!NIL_P(rb_prefix)) {
    prefix = RSTRING_PTR(rb_prefix);
  }

  if (prefix == NULL || !prefix[0]) {
    xfree(sanitizer->name_prefix);
    sanitizer->name_prefix = NULL;
  } else {
    strlcpy(sanitizer->name_prefix, prefix, RSTRING_LEN(rb_prefix) + 1);
  }

  return rb_prefix;
}

static VALUE
rb_selma_sanitizer_allowed_attribute(VALUE rb_self, VALUE rb_elem,
                                     VALUE rb_attr,
                                     VALUE rb_allow)
{
  SelmaSanitizer *sanitizer;
  StringArray *set = NULL;

  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);

  if (rb_elem == CSTR2SYM("all")) {
    set = sanitizer->allowed_attrs;
  } else {
    SelmaElementSanitizer *element_sanitizer = selma_sanitizer_get_element_sanitizer(sanitizer, gumbo_tag_from_rb(rb_elem));
    set = element_sanitizer->allowed_attrs;
  }

  set_in_string_list(set, rb_attr, RTEST(rb_allow));

  return Qnil;
}

static VALUE
rb_selma_sanitizer_required_attribute(VALUE rb_self, VALUE rb_elem,
                                      VALUE rb_attr,
                                      VALUE rb_req)
{
  SelmaSanitizer *sanitizer;
  SelmaElementSanitizer *element_sanitizer = NULL;

  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);

  element_sanitizer = selma_sanitizer_get_element_sanitizer(sanitizer, gumbo_tag_from_rb(rb_elem));

  set_in_string_list(element_sanitizer->required_attrs, rb_attr, RTEST(rb_req));

  return Qnil;
}

static VALUE
rb_selma_sanitizer_allowed_class(VALUE rb_self, VALUE rb_elem,
                                 VALUE rb_class, VALUE rb_allow)
{
  SelmaSanitizer *sanitizer;
  StringArray *list = NULL;

  Data_Get_Struct(rb_self, SelmaSanitizer, sanitizer);

  if (rb_elem == CSTR2SYM("all")) {
    list = sanitizer->allowed_classes;
  } else {
    GumboTag tag = gumbo_tag_from_rb(rb_elem);
    SelmaElementSanitizer *element_sanitizer = selma_sanitizer_get_element_sanitizer(sanitizer, tag);
    list = element_sanitizer->allowed_classes;
  }

  set_in_string_list(list, rb_class, RTEST(rb_allow));
  return Qnil;
}

static VALUE
rb_selma_sanitizer_new(VALUE klass, VALUE rb_config)
{
  SelmaSanitizer *sanitizer = selma_sanitizer_new();
  VALUE rb_sanitizer_obj =
    Data_Wrap_Struct(klass, NULL, &selma_sanitizer_free, sanitizer);

  rb_funcall(rb_sanitizer_obj, rb_intern("setup"), 1, rb_config);

  return rb_sanitizer_obj;
}

void
Init_selma_sanitizer(void)
{
  rb_selma_id_relative = rb_intern("relative");

  rb_cSanitizer = rb_define_class_under(rb_mSelma, "Sanitizer", rb_cObject);
  rb_mConfig = rb_define_module_under(rb_cSanitizer, "Config");

  rb_define_singleton_method(rb_cSanitizer, "new", rb_selma_sanitizer_new, 1);

  rb_define_method(rb_cSanitizer, "set_flag", rb_selma_sanitizer_set_flag, 3);
  rb_define_method(rb_cSanitizer, "set_all_flags",
                   rb_selma_sanitizer_set_all_flags, 2);

  // rb_define_method(rb_cSanitizer, "element_flags",
  //                  rb_selma_sanitizer_get_all_flags, 0);

  // rb_define_method(rb_cSanitizer, "allowed_attributes",
  //                  rb_selma_sanitizer_allowed_attributes, 0);

  rb_define_method(rb_cSanitizer, "set_allow_comments",
                   rb_selma_sanitizer_set_allow_comments, 1);

  rb_define_method(rb_cSanitizer, "set_allow_doctype",
                   rb_selma_sanitizer_set_allow_doctype, 1);

  // rb_define_method(rb_cSanitizer, "set_name_prefix",
  //                  rb_selma_sanitizer_set_name_prefix, 1);

  rb_define_method(rb_cSanitizer, "set_allowed_attribute",
                   rb_selma_sanitizer_allowed_attribute, 3);

  rb_define_method(rb_cSanitizer, "set_allowed_class",
                   rb_selma_sanitizer_allowed_class, 3);

  rb_define_method(rb_cSanitizer, "set_allowed_protocols",
                   rb_selma_sanitizer_allowed_protocols, 3);

  // rb_define_method(rb_cSanitizer, "set_required_attribute",
  //                  rb_selma_sanitizer_required_attribute, 3);

  rb_define_const(rb_cSanitizer, "ALLOW", INT2FIX(SELMA_SANITIZER_ALLOW));

  rb_define_const(rb_cSanitizer, "REMOVE_CONTENTS",
                  INT2FIX(SELMA_SANITIZER_REMOVE_CONTENTS));

  rb_define_const(rb_cSanitizer, "WRAP_WHITESPACE",
                  INT2FIX(SELMA_SANITIZER_WRAP_WS));
}

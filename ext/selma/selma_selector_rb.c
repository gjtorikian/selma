#include <ruby.h>

#include "selma.h"
#include "selma_selector_rb.h"

VALUE rb_cSelector;

void
rb_selma_selector_free(SelmaSelector *sel)
{
  xfree(sel);
}

void
rb_selma_selector_check(VALUE rb_selector)
{
  if (!rb_obj_is_kind_of(rb_selector, rb_cSelector)) {
    rb_raise(rb_eTypeError, "expected a Selma::Selector instance, got %s",
             rb_obj_classname(rb_selector));
  }
}

static VALUE
rb_selma_selector_new(VALUE klass, VALUE rb_selector)
{
  VALUE rb_match = Qnil, rb_reject = Qnil;
  SelmaSelector *sel;

  if (rb_type(rb_selector) == T_HASH) {
    rb_match = rb_hash_lookup(rb_selector, CSTR2SYM("match"));
    if (!NIL_P(rb_match)) {
      Check_Type(rb_match, T_STRING);
    }

    rb_reject = rb_hash_lookup(rb_selector, CSTR2SYM("reject"));
    if (!NIL_P(rb_reject)) {
      Check_Type(rb_reject, T_STRING);
    }
  } else {
    rb_match = rb_selector;
    Check_Type(rb_match, T_STRING);
  }

  sel = xcalloc(1, sizeof(SelmaSelector));

  if (!NIL_P(rb_match)) {
    Check_Type(rb_match, T_STRING);
    sel->match = StringValueCStr(rb_match);
  }

  if (!NIL_P(rb_reject)) {
    Check_Type(rb_reject, T_STRING);
    sel->reject = StringValueCStr(rb_reject);
  }

  return Data_Wrap_Struct(klass, NULL, rb_selma_selector_free, sel);
}

void
Init_selma_selector(void)
{
  rb_cSelector = rb_define_class_under(rb_mSelma, "Selector", rb_cObject);
  rb_define_singleton_method(rb_cSelector, "new", rb_selma_selector_new, 1);
}

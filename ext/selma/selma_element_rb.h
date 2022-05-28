#ifndef _SELMA_ELEMENET_RB_H
#define _SELMA_ELEMENET_RB_H

#include <ruby.h>

enum {
  BEFORE_BEGIN = 0,
  AFTER_BEGIN = 1,
  BEFORE_END = 2,
  AFTER_END = 3
};

typedef struct {
  VALUE rb_result;
  VALUE rb_adjacent[4];
} SelmaReplace;

void Init_selma_element_rb(void);

VALUE rb_selma_element_to_s(VALUE self);

VALUE rb_selma_element_attr_get(VALUE rb_self, VALUE rb_key);
VALUE rb_selma_element_attr_set(VALUE rb_self, VALUE rb_key, VALUE rb_value);

#endif

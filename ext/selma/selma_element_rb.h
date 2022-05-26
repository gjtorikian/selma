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

VALUE rb_selma_element_to_s(VALUE self);

#endif

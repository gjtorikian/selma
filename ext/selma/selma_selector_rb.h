#ifndef _SELMA_SELECTOR_RB_H
#define _SELMA_SELECTOR_RB_H

#include <ruby.h>

#include "lol_html.h"

typedef struct {
  char *match;
  char *reject;
} SelmaSelector;

void Init_selma_selector(void);
void rb_selma_selector_check(VALUE rb_selector);

#endif

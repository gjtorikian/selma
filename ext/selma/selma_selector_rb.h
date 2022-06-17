#ifndef _SELMA_SELECTOR_RB_H
#define _SELMA_SELECTOR_RB_H

#include <ruby.h>

#include "uthash_utils.h"

#include "lol_html.h"
#include "uthash/utarray.h"

typedef struct {
  char *match;
  lol_html_selector_t *element_selector;
  char *text;
  lol_html_selector_t *text_selector;
} SelmaSelector;

void Init_selma_selector(void);
void rb_selma_selector_check(VALUE rb_selector);

#endif

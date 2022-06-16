#include "selma.h"

#include "selma_html.h"
#include "selma_selector_rb.h"
#include "selma_sanitizer_rb.h"
#include "selma_rewriter.h"

VALUE rb_mSelma;

__attribute__((visibility("default"))) void Init_selma(void)
{
  rb_mSelma = rb_define_module("Selma");

  Init_selma_html();
  Init_selma_sanitizer();
  Init_selma_selector();
  Init_selma_rewriter();
}

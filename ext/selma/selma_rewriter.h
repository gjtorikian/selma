#ifndef _SELMA_REWRITER_H
#define _SELMA_REWRITER_H

#include <ruby.h>

#include "lol_html.h"

typedef struct {
  VALUE rb_handler;
  VALUE rb_selector;
  int total_calls;
  double total_elapsed;
} Handler;

typedef struct {
  Handler *handlers;
  size_t handler_count;
  VALUE rb_rewriter;
  double total_elapsed;
} SelmaRewriter;

void iterate_handlers(SelmaRewriter *selma_rewriter, lol_html_rewriter_builder_t *builder);
lol_html_rewriter_directive_t selma_process_element_handlers(lol_html_element_t *element, void *user_data);
lol_html_rewriter_directive_t selma_process_handler_end(lol_html_doc_end_t *doc_end, void *user_data);
void Init_selma_rewriter(void);

#endif

#include <ruby.h>

#include "selma.h"

#include "selma_element_rb.h"
#include "selma_selector_rb.h"
#include "selma_rewriter.h"
#include "selma_utils.h"
#include "selma_perf.h"

#include "houdini/houdini.h"
#include "uthash/utstring.h"

VALUE rb_cRewriter;
VALUE rb_cElement;
ID g_id_handle_element;
ID g_id_handle_text;
ID g_id_adjacent_html[4];

static void
selma_rewriter_free(SelmaRewriter *rewriter)
{
  xfree(rewriter->handlers);
}

static void
selma_rewriter_mark(SelmaRewriter *rewriter)
{
  size_t i;

  for (i = 0; i < rewriter->handler_count; ++i) {
    Handler *h = &rewriter->handlers[i];
    rb_gc_mark(h->rb_handler);
    rb_gc_mark(h->rb_selector);
  }
}

static void
selma_rewriter_store_stats(SelmaRewriter *rewriter)
{
  VALUE rb_rewriter = rewriter->rb_rewriter;
  VALUE rb_stats = rb_attr_get(rb_rewriter, g_id_stats);

  Handler *handlers = rewriter->handlers;
  const size_t handler_count = rewriter->handler_count;

  size_t i;
  UT_string *buffer;
  utstring_new(buffer); // FIXME: Valgrind reports memory leak here.

  if (NIL_P(rb_stats)) {
    return;
  }

  selma_stats(rb_stats, "Selma#rewriter", 1, rewriter->total_elapsed);

  for (i = 0; i < handler_count; ++i) {
    utstring_clear(buffer);
    Handler *h = &handlers[i];

    if (!h->total_element_handler_calls) {
      continue;
    }

    utstring_printf(buffer, "%s#call", rb_obj_classname(h->rb_handler));
    selma_stats(rb_stats, utstring_body(buffer), h->total_element_handler_calls, h->total_elapsed_element_handlers);
  }

  utstring_free(buffer);
}

lol_html_rewriter_directive_t
selma_process_handler_end(lol_html_doc_end_t *doc_end, void *user_data)
{
  SelmaRewriter *rewriter = (SelmaRewriter *)user_data;

  selma_rewriter_store_stats(rewriter);

  return LOL_HTML_CONTINUE;
}

lol_html_rewriter_directive_t
selma_process_text_handlers(lol_html_text_chunk_t *chunk, void *user_data)
{
  SelmaRewriter *rewriter = (SelmaRewriter *)user_data;

  double begin_overall = selma_get_ms();

  Handler *handlers = rewriter->handlers;
  const size_t handler_count = rewriter->handler_count;
  size_t n;
  for (n = 0; n < handler_count; ++n) {
    Handler *h = &handlers[n];
    double handler_begin;

    handler_begin = selma_get_ms();

    // prevents missing `handle_text` function
    if (rb_respond_to(h->rb_handler, g_id_handle_text)) {
      lol_html_text_chunk_content_t content = lol_html_text_chunk_content_get(chunk);

      VALUE rb_text = rb_str_new(content.data, content.len);
      VALUE rb_result = rb_funcall(h->rb_handler, g_id_handle_text, 1, rb_text);

      Check_Type(rb_result, T_STRING);
      lol_html_text_chunk_replace(chunk, RSTRING_PTR(rb_result), RSTRING_LEN(rb_result), true);
    }
    h->total_elapsed_element_handlers += (selma_get_ms() - handler_begin);
    h->total_element_handler_calls++;
  }

  rewriter->total_elapsed = (selma_get_ms() - begin_overall);

  return LOL_HTML_CONTINUE;
}

lol_html_rewriter_directive_t
selma_process_element_handlers(lol_html_element_t *element, void *user_data)
{
  SelmaRewriter *rewriter = (SelmaRewriter *)user_data;

  double begin_overall = selma_get_ms();

  VALUE rb_element;

  // TODO: gc mark/free?
  rb_element = Data_Wrap_Struct(rb_cElement, NULL, NULL, element);

  SelmaReplace replace = {rb_element, {Qnil, Qnil, Qnil, Qnil}};

  Handler *handlers = rewriter->handlers;
  const size_t handler_count = rewriter->handler_count;

  for (size_t n = 0; n < handler_count; ++n) {
    Handler *h = &handlers[n];
    double handler_begin;

    handler_begin = selma_get_ms();

    // prevents missing `handle_element` function
    if (rb_respond_to(h->rb_handler, g_id_handle_element)) {
      rb_funcall(h->rb_handler, g_id_handle_element, 1, rb_element);

      h->total_elapsed_element_handlers += (selma_get_ms() - handler_begin);
      h->total_element_handler_calls++;
    }

    if (replace.rb_result != rb_element) {
      break;
    }
  }

  rewriter->total_elapsed = (selma_get_ms() - begin_overall);

  return LOL_HTML_CONTINUE;
}

void
destruct_selectors(SelmaRewriter *rewriter)
{
  Handler *handlers = rewriter->handlers;
  const size_t handler_count = rewriter->handler_count;

  size_t n;
  for (n = 0; n < handler_count; ++n) {
    Handler *h = &handlers[n];

    VALUE rb_selector = h->rb_selector;

    if (NIL_P(rb_selector)) {
      continue;
    }

    SelmaSelector *selma_selector = NULL;
    Data_Get_Struct(rb_selector, SelmaSelector, selma_selector);

    if (selma_selector->element_selector != NULL) {
      lol_html_selector_free(selma_selector->element_selector);
    }

    if (selma_selector->text_selector != NULL) {
      lol_html_selector_free(selma_selector->text_selector);
    }
  }
}

void
construct_handlers(SelmaRewriter *selma_rewriter, lol_html_rewriter_builder_t *builder)
{
  lol_html_rewriter_builder_add_document_content_handlers(builder, NULL, NULL, NULL, NULL, NULL, NULL,
      selma_process_handler_end, selma_rewriter);
  int element_status = 0, text_status = 0;

  Handler *handlers = selma_rewriter->handlers;
  const size_t handler_count = selma_rewriter->handler_count;

  size_t i;
  for (i = 0; i < handler_count; ++i) {
    Handler *h = &handlers[i];

    VALUE rb_selector = h->rb_selector;

    if (NIL_P(rb_selector)) {
      continue;
    }

    SelmaSelector *selma_selector = NULL;
    Data_Get_Struct(rb_selector, SelmaSelector, selma_selector);

    if (selma_selector->match != NULL) {
      selma_selector->element_selector = lol_html_selector_parse(selma_selector->match, strlen(selma_selector->match));
    }

    if (selma_selector->text != NULL) {
      selma_selector->text_selector = lol_html_selector_parse(selma_selector->text, strlen(selma_selector->text));
    }

    // invalid CSS comes back as NULL

    if (selma_selector->element_selector != NULL) {
      element_status = lol_html_rewriter_builder_add_element_content_handlers(
                         builder,  selma_selector->element_selector, selma_process_element_handlers, selma_rewriter, NULL, NULL, NULL, NULL);
    }

    if (selma_selector->text_selector != NULL) {
      text_status = lol_html_rewriter_builder_add_element_content_handlers(
                      builder,  selma_selector->text_selector, NULL, NULL, NULL, NULL, selma_process_text_handlers, selma_rewriter);
    }

    if (element_status || text_status) {
      raise_lol_html_error();
    }
  }
}


VALUE
selma_rewriter_new(VALUE klass, VALUE rb_handlers)
{
  VALUE rb_rewriter, rb_selector;
  SelmaRewriter *rewriter = NULL;

  if (NIL_P(rb_handlers)) {
    return Qnil;
  }

  size_t i;
  Check_Type(rb_handlers, T_ARRAY);
  rb_rewriter = Data_Make_Struct(klass, SelmaRewriter, selma_rewriter_mark, selma_rewriter_free, rewriter);

  rewriter->handlers = xcalloc(RARRAY_LEN(rb_handlers), sizeof(Handler));
  rewriter->handler_count = RARRAY_LEN(rb_handlers);

  for (i = 0; i < rewriter->handler_count; ++i) {
    Handler *h = &rewriter->handlers[i];
    VALUE rb_handler = RARRAY_AREF(rb_handlers, i);

    h->rb_handler = rb_handler;
    h->rb_selector = Qnil;

    // prevents missing SELECTOR const from ruining things
    if (!rb_respond_to(rb_handler, g_id_selector)) {
      continue;
    }

    rb_selector = rb_funcall(rb_handler, g_id_selector, 0);

    rb_selma_selector_check(rb_selector);

    SelmaSelector *selma_selector = NULL;
    Data_Get_Struct(rb_selector, SelmaSelector, selma_selector);

    h->rb_selector = rb_selector;
  }

  rb_cElement = rb_define_class_under(rb_mSelma, "Element", rb_cHTML);

  return rb_rewriter;
}


void
Init_selma_rewriter(void)
{
  rb_cRewriter = rb_define_class_under(rb_mSelma, "Rewriter", rb_cObject);
  rb_define_singleton_method(rb_cRewriter, "new", selma_rewriter_new, 1);

  Init_selma_element_rb();
}

#include <ruby.h>

#include "selma.h"

#include "selma_element_rb.h"
#include "selma_selector_rb.h"
#include "selma_rewriter.h"
#include "selma_utils.h"
#include "selma_perf.h"

#include "uthash/utstring.h"

VALUE rb_cRewriter;
VALUE rb_cElement;
ID g_id_process;
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
parse_replace_options(SelmaReplace *replace, VALUE rb_opts)
{
  if (!NIL_P(rb_opts)) {
    int i;
    Check_Type(rb_opts, T_HASH);
    for (i = 0; i < 4; ++i) {
      replace->rb_adjacent[i] =
        rb_hash_lookup(rb_opts, ID2SYM(g_id_adjacent_html[i]));
    }
  }
}

static void
check_replace_result_1(SelmaReplace *replace, VALUE rb_result)
{
  switch (rb_type(rb_result)) {
    case T_NIL:
      break;

    case T_FALSE:
      replace->rb_result = Qfalse;
      break;

    case T_STRING:
    case T_DATA:
      replace->rb_result = rb_result;
      break;

    default:
      rb_raise(rb_eTypeError,
               "expected a String or Element");
  }
}

static void
check_replace_result(SelmaReplace *replace, VALUE rb_result)
{
  switch (rb_type(rb_result)) {
    case T_NIL:
      break;

    case T_FALSE:
      replace->rb_result = Qfalse;
      break;

    case T_ARRAY: {
      VALUE rb_element = rb_ary_entry(rb_result, 0);
      Check_Type(rb_element, T_DATA);
      if (rb_class_of(rb_element) != rb_cElement) {
        rb_raise(rb_eTypeError, "First element of array must be an Element");
      }

      replace->rb_result = rb_element;
      parse_replace_options(replace, rb_ary_entry(rb_result, 1));
      break;
    }

    default:
      check_replace_result_1(replace, rb_result);
      break;
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
  utstring_new(buffer);

  if (NIL_P(rb_stats)) {
    return;
  }

  selma_stats(rb_stats, "Selma#rewriter", 1, rewriter->total_elapsed);

  for (i = 0; i < handler_count; ++i) {
    utstring_clear(buffer);
    Handler *h = &handlers[i];

    if (!h->total_calls) {
      continue;
    }

    utstring_printf(buffer, "%s#call", rb_obj_classname(h->rb_handler));
    selma_stats(rb_stats, utstring_body(buffer), h->total_calls, h->total_elapsed);
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
selma_process_element_handlers(lol_html_element_t *element, void *user_data)
{
  SelmaRewriter *rewriter = (SelmaRewriter *)user_data;

  double begin_overall;

  begin_overall = selma_get_ms();

  VALUE rb_element;

  // TODO: gc mark/free?
  rb_element = Data_Wrap_Struct(rb_cElement, NULL, NULL, element);

  SelmaReplace replace = {rb_element, {Qnil, Qnil, Qnil, Qnil}};

  Handler *handlers = rewriter->handlers;
  const size_t handler_count = rewriter->handler_count;
  size_t n;
  for (n = 0; n < handler_count; ++n) {
    Handler *h = &handlers[n];
    double handler_begin;
    VALUE rb_result = rb_element;

    handler_begin = selma_get_ms();

    // prevents missing `process` function
    if (rb_respond_to(h->rb_handler, g_id_process)) {
      rb_result = rb_funcall(h->rb_handler, g_id_process, 1, rb_element);
    }
    h->total_elapsed += (selma_get_ms() - handler_begin);
    h->total_calls++;

    // check_replace_result(&replace, rb_result);
    if (replace.rb_result != rb_element) {
      break;
    }
  }

  rewriter->total_elapsed = (selma_get_ms() - begin_overall);
  // rb_result = strbuf_to_rb(&serial->out, false);

  return LOL_HTML_CONTINUE;
}

void
iterate_handlers(SelmaRewriter *selma_rewriter, lol_html_rewriter_builder_t *builder)
{
  lol_html_rewriter_builder_add_document_content_handlers(builder, NULL, NULL, NULL, NULL, NULL, NULL,
      selma_process_handler_end, selma_rewriter);
  int status;

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

    lol_html_selector_t *selector =
      lol_html_selector_parse(selma_selector->match, strlen(selma_selector->match));

    status = lol_html_rewriter_builder_add_element_content_handlers(
               builder, selector, selma_process_element_handlers, selma_rewriter, NULL, NULL, NULL, NULL);
    if (status) {
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

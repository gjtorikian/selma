#include <ruby.h>

#include "selma.h"
#include "selma_html.h"
#include "selma_sanitizer.h"
#include "selma_selector_rb.h"
#include "selma_rewriter.h"
#include "selma_utils.h"
#include "selma_perf.h"

#include "lol_html.h"

VALUE rb_cHTML;

ID g_id_stats;
ID g_id_sanitizer;
ID g_id_selector;
ID g_id_rewriter;

void
output_sink(const char *chunk, size_t chunk_len, void *user_data)
{
  UT_string *output = (UT_string *)user_data;

  // chunk includes end tag (eg. </a>) while chunk_len
  // only has relevant inner content (eg. "foo")
  utstring_printf(output, "%.*s", chunk_len, chunk);
}

static VALUE
encode_utf8_string(const char *c_string)
{
  VALUE string = rb_str_new2(c_string);
  int enc = rb_enc_find_index(EXPECTED_ENCODING);
  rb_enc_associate_index(string, enc);
  return string;
}

static void
initialize_sanitation(SelmaSanitizer *sanitizer,
                      lol_html_rewriter_builder_t *builder, lol_html_selector_t *selector)
{
  int status = 0;

  lol_html_rewriter_builder_add_document_content_handlers(
    builder, selma_sanitize_doctype, sanitizer, selma_sanitize_comment, sanitizer, NULL, NULL, NULL, NULL);

  status = lol_html_rewriter_builder_add_element_content_handlers(
             builder, selector, selma_sanitize_element, sanitizer, NULL, NULL, NULL, NULL);

  if (status) {
    raise_lol_html_error();
  }
}

static lol_html_rewriter_t *
initialize_rewriter(lol_html_rewriter_builder_t *builder, UT_string *output)
{
  lol_html_rewriter_t *rewriter = lol_html_rewriter_build(
                                    builder, EXPECTED_ENCODING, strlen(EXPECTED_ENCODING),
  (lol_html_memory_settings_t) {
    .preallocated_parsing_buffer_size =
      BUFFER_SIZE,
      .max_allowed_memory_usage = MAX_MEMORY
  },
  output_sink, output, true);

  // "In case of an error the function returns a NULL pointer."
  if (rewriter == NULL) {
    raise_lol_html_error();
  }

  return rewriter;
}

static char *
perform_lol_html_rewrite(lol_html_rewriter_t *rewriter, char *src, UT_string *output)
{
  int status = 0;
  char *html;

  status = lol_html_rewriter_write(rewriter, src, strlen(src));
  if (status) {
    raise_lol_html_error();
  }

  html = strndup(utstring_body(output), utstring_len(output));

  return html;
}

static char *
perform_initial_sanitization(SelmaSanitizer *sanitizer, lol_html_selector_t *selector, char *html, UT_string *output)
{
  lol_html_rewriter_builder_t *builder = lol_html_rewriter_builder_new();

  int status = 0;

  lol_html_rewriter_builder_add_document_content_handlers(
    builder, selma_sanitize_doctype, sanitizer, selma_sanitize_comment, sanitizer, NULL, NULL, NULL, NULL);
  status = lol_html_rewriter_builder_add_element_content_handlers(
             builder, selector, selma_sanitize_element, sanitizer, NULL, NULL, NULL, NULL);

  if (status) {
    raise_lol_html_error();
  }

  lol_html_rewriter_t *lol_html_rewriter = initialize_rewriter(builder, output);
  lol_html_rewriter_builder_free(builder);
  char *first_pass_html = perform_lol_html_rewrite(lol_html_rewriter, html, output);

  lol_html_rewriter_end(lol_html_rewriter);
  if (lol_html_rewriter != NULL) {
    lol_html_rewriter_free(lol_html_rewriter);
  } else {
    raise_lol_html_error();
  }

  return first_pass_html;
}

static char *
perform_final_sanitization(SelmaSanitizer *sanitizer, lol_html_selector_t *selector, char *html, UT_string *output)
{
  lol_html_rewriter_builder_t *builder = lol_html_rewriter_builder_new();

  int status = lol_html_rewriter_builder_add_element_content_handlers(
                 builder, selector, selma_sanitize_attributes, sanitizer, NULL, NULL, selma_sanitize_text, NULL);
  if (status) {
    raise_lol_html_error();
  }

  lol_html_rewriter_t *lol_html_rewriter = initialize_rewriter(builder, output);
  lol_html_rewriter_builder_free(builder);
  char *sanitized_html = perform_lol_html_rewrite(lol_html_rewriter, html, output);

  lol_html_rewriter_end(lol_html_rewriter);
  if (lol_html_rewriter != NULL) {
    lol_html_rewriter_free(lol_html_rewriter);
  } else {
    raise_lol_html_error();
  }

  return sanitized_html;
}

static char *
perform_handler_rewrite(SelmaRewriter *selma_rewriter, char *html, UT_string *output)
{
  lol_html_rewriter_builder_t *builder = lol_html_rewriter_builder_new();

  iterate_handlers(selma_rewriter, builder);

  lol_html_rewriter_t *lol_html_rewriter = initialize_rewriter(builder, output);
  lol_html_rewriter_builder_free(builder);
  char *sanitized_html = perform_lol_html_rewrite(lol_html_rewriter, html, output);

  lol_html_rewriter_end(lol_html_rewriter);
  if (lol_html_rewriter != NULL) {
    lol_html_rewriter_free(lol_html_rewriter);
  } else {
    raise_lol_html_error();
  }

  return sanitized_html;
}

static VALUE
rb_selma_html_rewrite(VALUE self)
{
  VALUE rb_stats, rb_sanitizer, rb_rewriter, rb_html;

  rb_sanitizer = rb_iv_get(self, "@sanitizer");
  rb_rewriter = rb_iv_get(self, "@rewriter");
  rb_html = rb_iv_get(self, "@html");
  int has_sanitizer = rb_obj_is_kind_of(rb_sanitizer, rb_cSanitizer);
  int has_rewriter = rb_obj_is_kind_of(rb_rewriter, rb_cRewriter);

  double do_measure_stats = rb_iv_get(self, "@measuring");
  double begin = selma_get_ms();

  if (do_measure_stats) {
    rb_stats = rb_ary_new();
    rb_ivar_set(self, g_id_stats, rb_stats);
    selma_stats(rb_stats, "HTML#rewrite", 1, selma_get_ms() - begin);
  }

  SelmaSanitizer *sanitizer = NULL;
  if (has_sanitizer) {
    Data_Get_Struct(rb_sanitizer, SelmaSanitizer, sanitizer);
  }

  SelmaRewriter *selma_rewriter = NULL;
  if (has_rewriter) {
    Data_Get_Struct(rb_rewriter, SelmaRewriter, selma_rewriter);
  }

  char *html = strndup(
                 RSTRING_PTR(rb_html),
                 RSTRING_LEN(rb_html)
               );

  UT_string *output;
  utstring_new(output);

  if (has_sanitizer) {
    const char *selector_str = "*";
    lol_html_selector_t *selector =
      lol_html_selector_parse(selector_str, strlen(selector_str));

    char *first_pass_html = perform_initial_sanitization(sanitizer, selector, html, output);
    // due to malicious html crafting
    // (e.g. <<foo>script>...</script>, or <div <!-- comment -->> as in tests),
    // we need to run sanitization several times to truly remove unwanted tags,
    // because lol-html happily accepts this garbage (by design?)
    utstring_clear(output);
    char *sanitized_html = perform_final_sanitization(sanitizer, selector, first_pass_html, output);

    if (do_measure_stats) {
      selma_stats(rb_stats, "HTML#sanitize", 1, selma_get_ms() - begin);
    }
    if (!has_rewriter) {
      rb_html = encode_utf8_string(sanitized_html);
      rb_iv_set(self, "@html", rb_html);
    } else {
      utstring_clear(output);
      char *processed_html = perform_handler_rewrite(selma_rewriter, first_pass_html, output);
      rb_html = encode_utf8_string(processed_html);
      rb_iv_set(self, "@html", rb_html);
      free(processed_html);
    }

    lol_html_selector_free(selector);
    free(first_pass_html);
    free(sanitized_html);
  } else if (has_rewriter) {
    char *processed_html = perform_handler_rewrite(selma_rewriter, html, output);
    rb_html = encode_utf8_string(processed_html);
    rb_iv_set(self, "@html", rb_html);
    free(processed_html);
  }

  free(html);
  utstring_free(output);

  return rb_html;
}

static VALUE
configure_default_sanitizer()
{
  VALUE rb_sanitizer_config = rb_const_get_at(rb_mConfig, rb_intern("DEFAULT"));
  return rb_funcall(rb_cSanitizer, rb_intern("new"), 1, rb_sanitizer_config);
}

static VALUE
rb_selma_html_new(int argc, VALUE *argv, VALUE klass)
{
  VALUE rb_html, rb_string, rb_sanitizer = Qnil, rb_rewriter = Qnil, rb_handlers, rb_opts;
  SelmaHTML *html = NULL;
  rb_html = Data_Make_Struct(klass, SelmaHTML, NULL, NULL, html);

  SelmaSanitizer *sanitizer = NULL;
  SelmaRewriter *rewriter = NULL;

  int do_measure_stats = 0;

  rb_check_arity(argc, 1, 2);
  rb_scan_args(argc, argv, "1:", &rb_string, &rb_opts);

  Check_Type(rb_string, T_STRING);
  if (!NIL_P(rb_opts)) {
    do_measure_stats = RTEST(rb_hash_lookup(rb_opts, CSTR2SYM("measure")));
    rb_iv_set(rb_html, "measuring", do_measure_stats);

    // config passed, but no explicit sanitization rule -- sanitize by default
    rb_sanitizer = rb_hash_lookup2(rb_opts, CSTR2SYM("sanitizer"), configure_default_sanitizer());
    rb_handlers = rb_hash_lookup(rb_opts, CSTR2SYM("handlers"));

    if (!NIL_P(rb_handlers)) {
      rb_rewriter = rb_funcall(rb_cRewriter, rb_intern("new"), 1, rb_handlers);
    }
  } else { // no config passed -- sanitize by default
    rb_sanitizer = configure_default_sanitizer();
  }

  selma_utf8_strcheck(rb_string);
  rb_iv_set(rb_html, "@html", rb_string);

  if (!NIL_P(rb_sanitizer)) {
    if (!rb_obj_is_kind_of(rb_sanitizer, rb_cSanitizer)) {
      rb_raise(rb_eTypeError, "expected a Selma::Sanitizer instance");
    }
    Data_Get_Struct(rb_sanitizer, SelmaSanitizer, sanitizer);
  }

  rb_ivar_set(rb_html, g_id_sanitizer, rb_sanitizer);
  rb_ivar_set(rb_html, g_id_rewriter, rb_rewriter);

  return rb_html;
}

void
Init_selma_html(void)
{
  g_id_stats = rb_intern("@__stats__");
  g_id_rewriter = rb_intern("@rewriter");
  g_id_sanitizer = rb_intern("@sanitizer");
  g_id_selector = rb_intern("selector");
  g_id_process = rb_intern("process");

  rb_cHTML = rb_define_class_under(rb_mSelma, "HTML", rb_cObject);
  rb_define_singleton_method(rb_cHTML, "new", rb_selma_html_new, -1);
  rb_define_method(rb_cHTML, "rewrite", rb_selma_html_rewrite, 0);
}

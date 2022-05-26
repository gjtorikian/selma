#ifndef _SELMA_SANITIZER_H
#define _SELMA_SANITIZER_H

#include <ruby.h>

#include "selma_utils.h"
#include "utarray_utils.h"
#include "uthash_utils.h"

#include "lol_html.h"
#include "nokogiri-gumbo-parser/nokogiri_gumbo.h"
#include "uthash/utarray.h"
#include "uthash/uthash.h"

typedef struct {
  uint8_t flags[GUMBO_TAG_LAST];
  StringArray *allowed_attrs;
  StringArray *allowed_classes;
  st_table *element_sanitizers;
  char *name_prefix;
  int allow_comments : 1;
  int allow_doctype : 1;
} SelmaSanitizer;

typedef struct {
  StringArray *allowed_attrs;
  StringArray *required_attrs;
  StringArray *allowed_classes;
  StringHash *protocol_sanitizers;
} SelmaElementSanitizer;

enum {
  SELMA_SANITIZER_ALLOW = (1 << 0),
  SELMA_SANITIZER_REMOVE_CONTENTS = (1 << 1),
  SELMA_SANITIZER_WRAP_WS = (1 << 2),
};

SelmaSanitizer *selma_sanitizer_new(void);

lol_html_rewriter_directive_t selma_sanitize_doctype(lol_html_doctype_t *doctype, void *user_data);
lol_html_rewriter_directive_t selma_sanitize_comment(lol_html_comment_t *comment, void *user_data);
lol_html_rewriter_directive_t selma_sanitize_element(lol_html_element_t *element, void *user_data);
lol_html_rewriter_directive_t selma_sanitize_attributes(lol_html_element_t *element, void *user_data);
lol_html_rewriter_directive_t selma_sanitize_text(lol_html_text_chunk_t *chunk, void *user_data);

SelmaElementSanitizer *selma_sanitizer_get_element_sanitizer(SelmaSanitizer *sanitizer,
    GumboTag tag);

void selma_set_element_flags(uint8_t *flags, VALUE rb_el, bool set, int flag);

StringHash *selma_get_protocol_sanitizers(SelmaElementSanitizer *element,
    const char *attr_name);

void selma_sanitizer_free(void *_sanitizer);

#endif

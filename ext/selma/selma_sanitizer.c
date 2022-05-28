#include <ctype.h>
#include <ruby/util.h>

#include "selma.h"
#include "selma_sanitizer.h"
#include "utarray_utils.h"
#include "selma_utils.h"

#include "houdini/houdini.h"
#include "liblolhtml/lol_html.h"
#include "nokogiri-gumbo-parser/nokogiri_gumbo.h"
#include "uthash/utarray.h"


static const char *href_name = "href";
static const char *charset_name = "charset";
static const char *utf8_name = "utf-8";
static const size_t utf8_name_len = 5; // strlen
static const char *comment_open = "<!--";

static int
free_each_element_sanitizer(st_data_t _unused1, st_data_t _element_sanitizer,
                            st_data_t _unused2)
{
  SelmaElementSanitizer *element_sanitizer = (SelmaElementSanitizer *)_element_sanitizer;

  (void)_unused1;
  (void)_unused2;

  StringHash *protocol_sanitizers = element_sanitizer->protocol_sanitizers;
  StringHash *s, *tmp;
  HASH_ITER(hh, protocol_sanitizers, s, tmp) {
    utarray_free(s->values);
    free(s->key);
    HASH_DEL(protocol_sanitizers, s);
  }

  string_list_free(element_sanitizer->allowed_attrs);
  string_list_free(element_sanitizer->required_attrs);
  string_list_free(element_sanitizer->allowed_classes);

  xfree(element_sanitizer);

  return ST_CONTINUE;
}

void
selma_sanitizer_free(void *_sanitizer)
{
  SelmaSanitizer *sanitizer = _sanitizer;

  string_list_free(sanitizer->allowed_attrs);
  string_list_free(sanitizer->allowed_classes);

  st_foreach(sanitizer->element_sanitizers, &free_each_element_sanitizer, 0);
  st_free_table(sanitizer->element_sanitizers);

  xfree(sanitizer->name_prefix);
  xfree(sanitizer);
}

SelmaSanitizer *
selma_sanitizer_new(void)
{
  SelmaSanitizer *sanitizer = xcalloc(1, sizeof(SelmaSanitizer));

  utarray_new(sanitizer->allowed_attrs, &ut_str_icd);
  utarray_new(sanitizer->allowed_classes, &ut_str_icd);

  sanitizer->element_sanitizers = st_init_numtable();

  return sanitizer;
}

static void
lol_html_str_copy(void *_dst, const void *_src)
{
  lol_html_str_t *dst = (lol_html_str_t *)_dst, *src = (lol_html_str_t *)_src;
  if (src->len > 0) {
    dst->data = strndup(src->data, src->len);
    dst->len = src->len;
  } else {
    dst->data = NULL;
    dst->len = 0;
  }
}

static void
lol_html_str_dtor(void *_elt)
{
  lol_html_str_t *elt = (lol_html_str_t *)_elt;
  if (elt->data) { lol_html_str_free(*elt); }
}

static SelmaElementSanitizer *
try_find_element_sanitizer(SelmaSanitizer *sanitizer,
                           GumboTag tag)
{
  st_data_t data;

  if (st_lookup(sanitizer->element_sanitizers, (st_data_t)tag, (st_data_t *)&data)) {
    return (SelmaElementSanitizer *)data;
  }

  return NULL;
}

SelmaElementSanitizer *
selma_sanitizer_get_element_sanitizer(SelmaSanitizer *sanitizer,
                                      GumboTag tag)
{
  SelmaElementSanitizer *element_sanitizer = try_find_element_sanitizer(sanitizer, tag);

  if (element_sanitizer == NULL) {
    element_sanitizer = malloc(sizeof(SelmaElementSanitizer));

    utarray_new(element_sanitizer->allowed_attrs, &ut_str_icd);
    utarray_new(element_sanitizer->required_attrs, &ut_str_icd);
    utarray_new(element_sanitizer->allowed_classes, &ut_str_icd);

    element_sanitizer->protocol_sanitizers = NULL;

    st_insert(sanitizer->element_sanitizers, (st_data_t)tag, (st_data_t)element_sanitizer);
  }

  return element_sanitizer;
}

static bool
sanitize_class_attribute(SelmaSanitizer *sanitizer,
                         lol_html_element_t *element,
                         SelmaElementSanitizer *element_sanitizer,
                         const lol_html_attribute_t *attr)
{
  StringArray *allowed_global = NULL;
  StringArray *allowed_local = NULL;
  UT_string *buf;

  int valid_classes = 0;
  char *value = NULL, *end = NULL;

  if (string_list_present(sanitizer->allowed_classes)) {
    allowed_global = sanitizer->allowed_classes;
  }

  if (element_sanitizer && string_list_present(element_sanitizer->allowed_classes)) {
    allowed_local = element_sanitizer->allowed_classes;
  }

  // No class filters, so everything goes through
  if (!allowed_global && !allowed_local) {
    return true;
  }

  lol_html_str_t attr_value = lol_html_attribute_value_get(attr);
  strncpy(value, attr_value.data, attr_value.len);

  end = value + attr_value.len;

  while (value < end) {
    while (value < end && isspace(*value)) {
      value++;
    }

    if (value < end) {
      const char *class = value;
      bool allowed = false;
      while (value < end && !isspace(*value)) {
        value++;
      }

      *value = 0;

      if (allowed_local && string_list_contains(allowed_local, class)) {
        allowed = true;
      }

      if (allowed_global && string_list_contains(allowed_global, class)) {
        allowed = true;
      }

      if (allowed) {
        if (!valid_classes) {
          utstring_new(buf);
        } else {
          utstring_printf(buf, "%c", ' ');
        }

        utstring_printf(buf, "%s", class);
        valid_classes++;
      }

      value = value + 1;
    }
  }

  // There are still classes that passed the allowlist,
  // so replace the existing class values
  if (valid_classes) {
    char *classes = utstring_body(buf);
    lol_html_str_t attr_name = lol_html_attribute_name_get(attr);
    lol_html_element_set_attribute(element, attr_name.data, attr_name.len,
                                   classes, strlen(classes));
    utstring_free(buf);
    free(classes);

    return true;
  }

  lol_html_str_free(attr_value);
  return false;
}

static bool
has_allowed_protocol(StringArray *protocols_allowed,
                     lol_html_element_t *element,
                     const lol_html_attribute_t *attr)
{
  lol_html_str_t attr_value = lol_html_attribute_value_get(attr);
  lol_html_str_t attr_name = lol_html_attribute_name_get(attr);
  char *value = strndup(attr_value.data, attr_value.len);

  char *protocol;
  size_t len = 0;

  while (value[len] && value[len] != ':' && value[len] != '/' && value[len] != '#') {
    len++;
  }

  if (value[len] == '/') {
    lol_html_str_free(attr_name);
    lol_html_str_free(attr_value);
    free(value);
    return string_list_contains(protocols_allowed, "/");
  }

  if (value[len] == '#') {
    lol_html_str_free(attr_name);
    lol_html_str_free(attr_value);
    free(value);
    return string_list_contains(protocols_allowed, "#");
  }

  // Make protocol name case-insensitive
  protocol = downcase(value, len);

  bool contains = string_list_contains(protocols_allowed, protocol);

  free(protocol);
  lol_html_str_free(attr_name);
  lol_html_str_free(attr_value);
  // free(value);

  return contains;
}

static bool
should_keep_attribute(SelmaSanitizer *sanitizer,
                      lol_html_element_t *element,
                      SelmaElementSanitizer *element_sanitizer,
                      const lol_html_attribute_t *attr)
{
  bool allowed = false;

  lol_html_str_t attr_name = lol_html_attribute_name_get(attr);
  char *attr_name_val = strndup(attr_name.data, attr_name.len);

  if (element_sanitizer && string_list_contains(element_sanitizer->allowed_attrs, attr_name_val)) {
    allowed = true;
  }

  if (!allowed && string_list_contains(sanitizer->allowed_attrs, attr_name_val)) {
    allowed = true;
  }

  if (!allowed) {
    free(attr_name_val);
    return false;
  }

  if (element_sanitizer && element_sanitizer->protocol_sanitizers) {
    StringHash *protocol_sanitizers = element_sanitizer->protocol_sanitizers;
    StringHash *protocol_sanitizer;


    HASH_FIND_STR(protocol_sanitizers, attr_name_val, protocol_sanitizer);
    if (protocol_sanitizer) {
      if (!has_allowed_protocol(protocol_sanitizers->values, element, attr)) {
        free(attr_name_val);
        return false;
      }
    }
  }

  if (!strcmp(attr_name.data, "class")) {
    if (!sanitize_class_attribute(sanitizer, element, element_sanitizer, attr)) {
      free(attr_name_val);
      return false;
    }
  }

  free(attr_name_val);
  return true;
}

StringHash *
selma_get_protocol_sanitizers(SelmaElementSanitizer *element,
                              const char *attr_name)
{
  StringHash *protocol_sanitizers = element->protocol_sanitizers;
  StringHash *protocol_sanitizer;

  HASH_FIND_STR(protocol_sanitizers, attr_name, protocol_sanitizer);
  if (protocol_sanitizer)  {
    return protocol_sanitizer;
  }

  protocol_sanitizer = malloc(sizeof(StringHash));
  protocol_sanitizer->key = strdup(attr_name);
  utarray_new(protocol_sanitizer->values, &ut_str_icd);

  HASH_ADD_STR(element->protocol_sanitizers, key, protocol_sanitizer);

  return protocol_sanitizer;
}

static lol_html_rewriter_directive_t
remove_end_tag(lol_html_end_tag_t *end_tag, void *user_data)
{
  SELMA_UNUSED(user_data);

  lol_html_end_tag_remove(end_tag);

  return LOL_HTML_CONTINUE;
}

static void
remove_element(lol_html_element_t *element, uint8_t flags)
{
  bool wrap_whitespace = (flags & SELMA_SANITIZER_WRAP_WS);
  bool remove_contents = (flags & SELMA_SANITIZER_REMOVE_CONTENTS);

  if (remove_contents) {
    lol_html_element_remove(element);
  } else {
    if (wrap_whitespace) {
      lol_html_str_t tag_name = lol_html_element_tag_name_get(element);
      GumboTag tag = gumbo_tagn_enum(tag_name.data, tag_name.len);
      if (!gumbo_tag_is_void(tag)) {
        lol_html_element_before(element, " ", 1, false);
        lol_html_element_after(element, " ", 1, false);
      } else {
        lol_html_element_after(element, " ", 1, false);
      }
      lol_html_str_free(tag_name);
    }

    lol_html_element_remove_and_keep_content(element);
  }

  if (!lol_html_element_is_removed(element)) {
    raise_lol_html_error();
  }
}

static bool
force_remove_element(SelmaSanitizer *sanitizer, lol_html_element_t *element)
{
  lol_html_str_t tag_name = lol_html_element_tag_name_get(element);
  GumboTag tag = gumbo_tagn_enum(tag_name.data, tag_name.len);

  bool should_remove = false;

  uint8_t flags = (tag == GUMBO_TAG_UNKNOWN) ? 0 : sanitizer->flags[tag];

  remove_element(element, flags);

  lol_html_str_free(tag_name);

  if (lol_html_element_is_removed(element)) {
    lol_html_element_on_end_tag(element, remove_end_tag, NULL);
  } else {
    return false;
  }
  return true;
}

static bool
try_remove_element(SelmaSanitizer *sanitizer,
                   lol_html_element_t *element)
{
  lol_html_str_t tag_name = lol_html_element_tag_name_get(element);
  GumboTag tag = gumbo_tagn_enum(tag_name.data, tag_name.len);

  bool should_remove = false;

  uint8_t flags = (tag == GUMBO_TAG_UNKNOWN) ? 0 : sanitizer->flags[tag];

  if ((flags & SELMA_SANITIZER_ALLOW) == 0) {
    should_remove = true;
  }

  if (should_remove) {
    // the contents of these are considered "text nodes" and must be removed
    if ((tag == GUMBO_TAG_SCRIPT || tag == GUMBO_TAG_STYLE ||
         tag == GUMBO_TAG_MATH || tag == GUMBO_TAG_SVG)) {
      remove_element(element, SELMA_SANITIZER_REMOVE_CONTENTS);
    } else {
      remove_element(element, flags);
    }

    if (lol_html_element_is_removed(element)) {
      lol_html_element_on_end_tag(element, remove_end_tag, NULL);
    }
  } else {
    // anything in <iframe> must be removed, if it's kept
    if (tag == GUMBO_TAG_IFRAME) {
      if (sanitizer->flags[tag]) {
        lol_html_element_set_inner_content(element, " ", 1, false);
      } else {
        lol_html_element_set_inner_content(element, "", 0, false);
      }
    }
  }

  lol_html_str_free(tag_name);

  return should_remove;
}

lol_html_rewriter_directive_t
selma_sanitize_doctype(lol_html_doctype_t *doctype, void *user_data)
{
  SelmaSanitizer *sanitizer = (SelmaSanitizer *)user_data;

  if (!sanitizer->allow_doctype) {
    lol_html_doctype_remove(doctype);
  }

  return LOL_HTML_CONTINUE;
}

lol_html_rewriter_directive_t
selma_sanitize_comment(lol_html_comment_t *comment, void *user_data)
{
  SelmaSanitizer *sanitizer = (SelmaSanitizer *)user_data;

  if (!sanitizer->allow_comments) {
    lol_html_comment_remove(comment);
  }

  return LOL_HTML_CONTINUE;
}

lol_html_rewriter_directive_t
selma_sanitize_element(lol_html_element_t *element, void *user_data)
{
  SelmaSanitizer *sanitizer = (SelmaSanitizer *)user_data;

  try_remove_element(sanitizer, element);

  return LOL_HTML_CONTINUE;
}

lol_html_rewriter_directive_t
selma_sanitize_attributes(lol_html_element_t *element, void *user_data)
{
  SelmaSanitizer *sanitizer = (SelmaSanitizer *)user_data;

  bool keep_element = try_remove_element(sanitizer, element);

  if (keep_element) {
    return LOL_HTML_CONTINUE;
  }

  lol_html_str_t str = lol_html_element_tag_name_get(element);
  GumboTag tag = gumbo_tagn_enum(str.data, str.len);

  SelmaElementSanitizer *element_sanitizer =
    try_find_element_sanitizer(sanitizer, tag);

  lol_html_str_free(str);

  lol_html_attributes_iterator_t *iter =
    lol_html_attributes_iterator_get(element);
  const lol_html_attribute_t *attr;

  UT_string *unescaped_attr_value;
  utstring_new(unescaped_attr_value);
  UT_string *escaped_attr_value;
  utstring_new(escaped_attr_value);

  UT_array *removed_attrs;
  UT_icd lol_html_str_icd = {sizeof(lol_html_str_t), NULL, lol_html_str_copy, lol_html_str_dtor};
  utarray_new(removed_attrs, &lol_html_str_icd);

  while ((attr = lol_html_attributes_iterator_next(iter))) {
    lol_html_str_t attr_name_str = lol_html_attribute_name_get(attr);
    const char *attr_name = attr_name_str.data;

    // you can actually embed <!-- ... --> inside
    // an HTML tag to pass malicious data. If this is
    // encountered, remove the entire element to be safe.
    if (!strcmp(attr_name, comment_open)) {
      lol_html_str_free(attr_name_str);
      force_remove_element(sanitizer, element);
      continue;
    }

    size_t attr_name_len = attr_name_str.len;
    lol_html_str_t attr_val = lol_html_attribute_value_get(attr);
    utstring_clear(unescaped_attr_value);
    utstring_clear(escaped_attr_value);
    char *unescaped = NULL, *escaped = NULL;

    if (attr_val.len > 0) {
      // first, unescape any encodings...
      houdini_unescape_html(unescaped_attr_value, attr_val.data, attr_val.len);
      unescaped = strndup(utstring_body(unescaped_attr_value), utstring_len(unescaped_attr_value));

      // ...trim leading spaces...
      while (isspace(*unescaped)) {
        unescaped++;
      }

      lol_html_element_set_attribute(element, attr_name, attr_name_len, unescaped, strlen(unescaped));

      if (!should_keep_attribute(sanitizer, element, element_sanitizer, attr)) {
        utarray_push_back(removed_attrs, &attr_name_str);
      } else {
        // Prevent the use of `<meta>` elements that set a charset other than UTF-8,
        // since output is always UTF-8.
        if (tag == GUMBO_TAG_META) {
          if (!strcmp(attr_name, charset_name) && strcmp(unescaped, utf8_name)) {
            lol_html_element_set_attribute(element, attr_name, attr_name_len,
                                           utf8_name, utf8_name_len);
          }
        } else {
          // ...then, encode any special characters, for security
          if (!strcmp(attr_name, href_name)) {
            houdini_escape_href(escaped_attr_value, unescaped, strlen(unescaped));
          } else {
            houdini_escape_html(escaped_attr_value, unescaped, strlen(unescaped));
          }
          escaped = strndup(utstring_body(escaped_attr_value), utstring_len(escaped_attr_value));

          lol_html_element_set_attribute(element, attr_name, attr_name_len, escaped, strlen(escaped));
        }
      }
    } else { // no value? remove the attribute
      utarray_push_back(removed_attrs, &attr_name_str);
    }

    lol_html_str_free(attr_name_str);
    lol_html_str_free(attr_val);
  }

  lol_html_attributes_iterator_free(iter);
  utstring_free(unescaped_attr_value);
  utstring_free(escaped_attr_value);

  // seems to be some issue where removing an attr while
  // iterating messes up the iteration. so, keep track of
  // attrs that need to be removed and remove at the end
  lol_html_str_t *a = NULL;
  while ((a = (lol_html_str_t *)utarray_next(removed_attrs, a))) {
    lol_html_element_remove_attribute(element, a->data, a->len);
  }
  utarray_free(removed_attrs);

  if (element_sanitizer && string_list_present(element_sanitizer->required_attrs)) {
    StringArray *required = element_sanitizer->required_attrs;

    if (string_list_contains(required, "*")) {
      return LOL_HTML_CONTINUE;
    }

    lol_html_attributes_iterator_t *iter =
      lol_html_attributes_iterator_get(element);

    while ((attr = lol_html_attributes_iterator_next(iter)) != NULL) {
      lol_html_str_t name = lol_html_attribute_name_get(attr);
      if (string_list_contains(required, name.data)) {
        lol_html_str_free(name);
        break;
      }
    }
  }
}

lol_html_rewriter_directive_t
selma_sanitize_text(lol_html_text_chunk_t *chunk, void *user_data)
{
  SELMA_UNUSED(user_data);

  UT_string *text;
  utstring_new(text);

  lol_html_text_chunk_content_t content = lol_html_text_chunk_content_get(chunk);

  houdini_escape_html(text, content.data, content.len);
  lol_html_text_chunk_replace(chunk, utstring_body(text), utstring_len(text), true);

  utstring_free(text);

  return LOL_HTML_CONTINUE;
}

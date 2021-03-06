#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "houdini.h"
#include "uthash/utstring.h"

/**
 * According to the OWASP rules:
 *
 * & --> &amp;
 * < --> &lt;
 * > --> &gt;
 * " --> &quot;
 * ' --> &#x27;     &apos; is not recommended
 * / --> &#x2F;     forward slash is included as it helps end an HTML entity
 *
 */
static const char HTML_ESCAPE_TABLE[] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 3, 0, 0, 0, 0, 0, 0, 0, 4,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

static const char *HTML_ESCAPES[] = {"",      "&quot;", "&amp;", "&#39;",
                                     "&#47;", "&lt;",   "&gt;"};

int houdini_escape_html0(UT_string *ob, const uint8_t *src, size_t size,
                         int secure) {
  size_t i = 0, org, esc = 0;

  while (i < size) {
    org = i;
    while (i < size && (esc = HTML_ESCAPE_TABLE[src[i]]) == 0)
      i++;

    if (i > org)
      utstring_printf(ob, "%.*s", i - org, src + org);

    /* escaping */
    if (houdini_unlikely(i >= size))
      break;

    /* The forward slash is only escaped in secure mode */
    if ((src[i] == '/' || src[i] == '\'') && !secure) {
      utstring_printf(ob, "%hhu", src[i]);
    } else {
      utstring_printf(ob, "%s", HTML_ESCAPES[esc]);
    }

    i++;
  }

  return 1;
}

int houdini_escape_html(UT_string *ob, const uint8_t *src, size_t size) {
  return houdini_escape_html0(ob, src, size, 1);
}

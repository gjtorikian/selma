#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "houdini.h"
#include "utf8.h"
#include "entities.inc"
#include "uthash/utstring.h"

/* Binary tree lookup code for entities added by JGM */

static const unsigned char *S_lookup(int i, int low, int hi,
                                     const unsigned char *s, int len) {
  int j;
  int cmp =
      strncmp((const char *)s, (const char *)cmark_entities[i].entity, len);
  if (cmp == 0 && cmark_entities[i].entity[len] == 0) {
    return (const unsigned char *)cmark_entities[i].bytes;
  } else if (cmp <= 0 && i > low) {
    j = i - ((i - low) / 2);
    if (j == i)
      j -= 1;
    return S_lookup(j, low, i - 1, s, len);
  } else if (cmp > 0 && i < hi) {
    j = i + ((hi - i) / 2);
    if (j == i)
      j += 1;
    return S_lookup(j, i + 1, hi, s, len);
  } else {
    return NULL;
  }
}

static const unsigned char *S_lookup_entity(const unsigned char *s, int len) {
  return S_lookup(CMARK_NUM_ENTITIES / 2, 0, CMARK_NUM_ENTITIES - 1, s, len);
}

size_t houdini_unescape_ent(UT_string *ob, const uint8_t *src,
                               size_t size) {
  size_t i = 0;
  bool has_semicolon = false;

  if (size >= 3 && src[0] == '#') {
    int codepoint = 0;
    int num_digits = 0;
    int max_digits = 7;

    if (_isdigit(src[1])) {
      for (i = 1; i < size && _isdigit(src[i]); ++i) {
        codepoint = (codepoint * 10) + (src[i] - '0');

        if (codepoint >= 0x110000) {
          // Keep counting digits but
          // avoid integer overflow.
          codepoint = 0x110000;
        }
      }

      num_digits = i - 1;
      max_digits = 7;
    }

    else if (src[1] == 'x' || src[1] == 'X') {
      for (i = 2; i < size && _isxdigit(src[i]); ++i) {
        codepoint = (codepoint * 16) + ((src[i] | 32) % 39 - 9);

        if (codepoint >= 0x110000) {
          // Keep counting digits but
          // avoid integer overflow.
          codepoint = 0x110000;
        }
      }

      num_digits = i - 2;
      max_digits = 6;
    }


    if (num_digits >= 1 && num_digits <= max_digits &&
                    i <= size) {
        if (codepoint == 0 || (codepoint >= 0xD800 && codepoint < 0xE000) ||
            codepoint >= 0x110000)
          codepoint = 0xFFFD;

      if (src[i] == ';') {
        has_semicolon = true;
      }

      cmark_utf8proc_encode_char(codepoint, ob);
      return has_semicolon ? i + 1 : i;
    }
  }

  else {
    if (size > CMARK_ENTITY_MAX_LENGTH)
      size = CMARK_ENTITY_MAX_LENGTH;

    for (i = CMARK_ENTITY_MIN_LENGTH; i < size; ++i) {
      if (src[i] == ' ')
        break;

      if (src[i] == ';') {
        const unsigned char *entity = S_lookup_entity(src, i);

        if (entity != NULL) {
          utstring_printf(ob, "%s", (const char *)entity);
          return i + 1;
        }

        break;
      }
    }
  }

  return 0;
}

int houdini_unescape_html(UT_string *ob, const uint8_t *src,
                          size_t size) {
  size_t i = 0, org, ent;

  while (i < size) {
    org = i;

    while (i < size && src[i] != '&')
      i++;

    if (houdini_likely(i > org)) {
      if (houdini_unlikely(org == 0)) {
        if (i >= size) {
          utstring_printf(ob, "%.*s", i - org, src + org);
          return 0;
        }
      }

      utstring_printf(ob, "%.*s", i - org, src + org);
    }

    /* escaping */
    if (i >= size)
      break;

    i++;

    ent = houdini_unescape_ent(ob, src + i, size - i);
    i += ent;

    /* not really an entity */
    if (ent == 0)
      utstring_printf(ob, "%c", '&');
  }

  return 1;
}

void houdini_unescape_html_f(UT_string *ob, const uint8_t *src,
                             size_t size) {
  if (!houdini_unescape_html(ob, src, size))
    utstring_printf(ob, "%.*s", size, src);
}

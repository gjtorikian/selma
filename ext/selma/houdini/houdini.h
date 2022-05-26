#ifndef CMARK_HOUDINI_H
#define CMARK_HOUDINI_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include "uthash/utstring.h"

#ifdef HAVE___BUILTIN_EXPECT
#define houdini_likely(x) __builtin_expect((x), 1)
#define houdini_unlikely(x) __builtin_expect((x), 0)
#else
#define houdini_likely(x) (x)
#define houdini_unlikely(x) (x)
#endif

#ifdef HOUDINI_USE_LOCALE
#define _isxdigit(c) isxdigit(c)
#define _isdigit(c) isdigit(c)
#else
/*
 * Helper _isdigit methods -- do not trust the current locale
 * */
#define _isxdigit(c) (strchr("0123456789ABCDEFabcdef", (c)) != NULL)
#define _isdigit(c) ((c) >= '0' && (c) <= '9')
#endif

#define HOUDINI_ESCAPED_SIZE(x) (((x)*12) / 10)
#define HOUDINI_UNESCAPED_SIZE(x) (x)

extern size_t houdini_unescape_ent(UT_string *ob, const uint8_t *src,
                                      size_t size);
extern int houdini_escape_html(UT_string *ob, const uint8_t *src,
                               size_t size);
extern int houdini_escape_html0(UT_string *ob, const uint8_t *src,
                                size_t size, int secure);
extern int houdini_unescape_html(UT_string *ob, const uint8_t *src,
                                 size_t size);
extern void houdini_unescape_html_f(UT_string *ob, const uint8_t *src,
                                    size_t size);
extern int houdini_escape_href(UT_string *ob, const uint8_t *src,
                               size_t size);

#ifdef __cplusplus
}
#endif

#endif

#ifndef CMARK_UTF8_H
#define CMARK_UTF8_H

#include <stdint.h>
#include "uthash/utstring.h"

#ifdef __cplusplus
extern "C" {
#endif

void cmark_utf8proc_case_fold(UT_string *dest, const uint8_t *str,
                              size_t len);
void cmark_utf8proc_encode_char(int32_t uc, UT_string *buf);
int cmark_utf8proc_iterate(const uint8_t *str, size_t str_len, int32_t *dst);
void cmark_utf8proc_check(UT_string *dest, const uint8_t *line,
                          size_t size);
int cmark_utf8proc_is_space(int32_t uc);
int cmark_utf8proc_is_punctuation(int32_t uc);

#ifdef __cplusplus
}
#endif

#endif

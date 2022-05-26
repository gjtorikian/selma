#ifndef _SELMA_UTILS_H
#define _SELMA_UTILS_H

#include "nokogiri-gumbo-parser/nokogiri_gumbo.h"
#include "uthash/utstring.h"

void selma_utf8_strcheck(VALUE rb_str);
VALUE utstring_to_rb(UT_string *s, bool do_free);
VALUE gumbo_tag_to_rb(GumboTag tag);
GumboTag gumbo_tag_from_rb(VALUE rb_tag);
void raise_lol_html_error();
char *downcase(char *str, unsigned long len);
bool gumbo_tag_is_void(GumboTag tag);

#endif

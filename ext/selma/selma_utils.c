#include <ruby.h>
#include <ruby/encoding.h>

#include "selma.h"

#include "lol_html.h"
#include "nokogiri-gumbo-parser/nokogiri_gumbo.h"
#include "uthash/utstring.h"

static ID g_SelmaTagNames[GUMBO_TAG_LAST];

int
rb_sym_char_cmp(VALUE sym, char *str)
{
  VALUE rb_string = rb_funcall(sym, rb_intern("name"), 0);

  return strcmp(rb_string, str);
}

void
selma_utf8_strcheck(VALUE rb_str)
{
  Check_Type(rb_str, T_STRING);
  if (ENCODING_GET_INLINED(rb_str) != rb_utf8_encindex()) {
    rb_raise(rb_eEncodingError, "Expected UTF8 encoding");
  }
}

VALUE
utstring_to_rb(UT_string *s, bool do_free)
{
  VALUE rb_out =
    rb_utf8_str_new(utstring_body(s), utstring_len(s));
  if (do_free) {
    utstring_free(s);
  }

  return rb_out;
}

VALUE
gumbo_tag_to_rb(GumboTag tag)
{
  if (tag < GUMBO_TAG_UNKNOWN) {
    return ID2SYM(g_SelmaTagNames[tag]);
  }
  return Qnil;
}

GumboTag
gumbo_tag_from_rb(VALUE rb_tag)
{
  const char *tag_name;
  GumboTag t;

  if (SYMBOL_P(rb_tag)) {
    tag_name = rb_id2name(SYM2ID(rb_tag));
  } else {
    tag_name = StringValuePtr(rb_tag);
  }

  if ((t = gumbo_tagn_enum(tag_name, strlen(tag_name))) == GUMBO_TAG_UNKNOWN) {
    rb_raise(rb_eArgError, "unknown HTML5 tag: '%s'", tag_name);
  }

  return t;
}

char *
downcase(char *str, unsigned long len)
{
  char *tmp = malloc(len + 1);

  for (unsigned long i = 0; i < len; ++i) {
    tmp[i] = tolower(str[i]);
  }

  tmp[len] = '\0';

  return tmp;
}

bool
gumbo_tag_is_void(GumboTag tag)
{
  switch (tag) {
    case GUMBO_TAG_AREA:
    case GUMBO_TAG_BASE:
    case GUMBO_TAG_BASEFONT:
    case GUMBO_TAG_BGSOUND:
    case GUMBO_TAG_BR:
    case GUMBO_TAG_COL:
    case GUMBO_TAG_EMBED:
    case GUMBO_TAG_FRAME:
    case GUMBO_TAG_HR:
    case GUMBO_TAG_IMG:
    case GUMBO_TAG_INPUT:
    case GUMBO_TAG_KEYGEN:
    case GUMBO_TAG_LINK:
    case GUMBO_TAG_MENUITEM:
    case GUMBO_TAG_META:
    case GUMBO_TAG_PARAM:
    case GUMBO_TAG_SOURCE:
    case GUMBO_TAG_TRACK:
    case GUMBO_TAG_WBR:
      return true;

    default:
      return false;
  }
}

_Noreturn void
raise_lol_html_error()
{
  lol_html_str_t msg = lol_html_take_last_error();

  rb_raise(rb_eRuntimeError, "%s", msg.data);
}

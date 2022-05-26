#ifndef _SELMA_HTML_H
#define _SELMA_HTML_H

#include <ruby.h>

#include "selma.h"
#include "selma_sanitizer.h"

typedef struct {
  VALUE html;
  SelmaSanitizer *sanitizer;
} SelmaHTML;

void Init_selma_html(void);

#endif

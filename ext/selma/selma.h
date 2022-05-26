#ifndef _SELMA_RB_H
#define _SELMA_RB_H

#include <assert.h>
#include <ruby.h>
#include <ruby/st.h>
#include <ruby/encoding.h>
#include <ruby/util.h>
#include <ruby/version.h>

extern VALUE rb_mSelma;
extern VALUE rb_cHTML;
extern VALUE rb_cSanitizer;
extern VALUE rb_cRewriter;
extern VALUE rb_mConfig;
extern VALUE rb_cElement;

#define EXPECTED_ENCODING "UTF-8"

#define SELMA_UNUSED (void)

// arbitrary safety values
#define BUFFER_SIZE 0
#define MAX_MEMORY 2048

#define CSTR2SYM(s) (ID2SYM(rb_intern((s))))

// Internal IDs
extern ID g_id_stats;
extern ID g_id_sanitizer;
extern ID g_id_selector;
extern ID g_id_rewriter;
extern ID g_id_process;
extern ID g_id_adjacent_html[4];

void Init_selma(void);

#endif

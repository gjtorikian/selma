//! Cheap byte scans that decide whether a rewriting pass has any work to do, so the
//! expensive part (a full lol_html parse, or materializing every text chunk) is only
//! paid for when it can matter.

use memchr::memchr;

fn starts_with_ignore_ascii_case(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.len() >= needle.len() && haystack[..needle.len()].eq_ignore_ascii_case(needle)
}

/// Whether any `<` in `html` can end up in an entity-decoding text chunk, which is the
/// only place `SelmaSanitizer::escape_text_chunk` has work to do.
///
/// In the data state the tokenizer emits a `<` as text exactly when the byte after it
/// can start neither a tag (ASCII letter), a comment or doctype (`!`), an end tag (`/`),
/// nor a bogus comment (`?`). Inside `<textarea>` and `<title>` (RCDATA) every `<` is
/// text, so the presence of either start tag counts as well. Raw-text contexts such as
/// `<script>` and `<style>` are never escaped and need no consideration here.
///
/// A false positive only costs registering the handler; there are no false negatives.
pub fn has_escapable_lt(html: &[u8]) -> bool {
    let mut pos = 0;
    while let Some(i) = memchr(b'<', &html[pos..]) {
        let at = pos + i;
        match html.get(at + 1) {
            Some(b'!' | b'/' | b'?') => {}
            Some(c) if c.is_ascii_alphabetic() => {
                let name = &html[at + 1..];
                if starts_with_ignore_ascii_case(name, b"textarea")
                    || starts_with_ignore_ascii_case(name, b"title")
                {
                    return true;
                }
            }
            // anything else (or nothing at all) after a `<` makes it text
            _ => return true,
        }
        pos = at + 1;
    }
    false
}

/// Whether `html` contains a start tag for any of `names`, compared ASCII
/// case-insensitively. Matching by prefix over-approximates (`<titlex>` counts for
/// `title`), which is the safe direction for a gate.
pub fn has_start_tag(html: &[u8], names: &[&[u8]]) -> bool {
    let mut pos = 0;
    while let Some(i) = memchr(b'<', &html[pos..]) {
        let at = pos + i;
        let name = &html[at + 1..];
        if names.iter().any(|n| starts_with_ignore_ascii_case(name, n)) {
            return true;
        }
        pos = at + 1;
    }
    false
}

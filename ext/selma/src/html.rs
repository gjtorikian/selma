use lol_html::{doc_comments, doctype, element, HtmlRewriter, Settings};
use magnus::{function, method, Error, Module, Object, RModule};

use crate::{rewriter::SelmaRewriter, sanitizer::SelmaSanitizer};

#[derive(Clone, Debug)]
#[magnus::wrap(class = "Selma::HTML")]
pub(crate) struct SelmaHTML {
    html: String,
}

/// SAFETY: This is safe because we only access this data when the GVL is held.
// unsafe impl Send for SelmaHTML {}

impl SelmaHTML {
    fn new(html: String) -> Self {
        Self { html }
    }

    /// Perform HTML rewrite sequence.
    fn rewrite(
        &self,
        sanitizer: Option<&SelmaSanitizer>,
        rewriter: Option<&SelmaRewriter>,
    ) -> String {
        let sanitized_html = match sanitizer {
            None => self.html.to_string(),
            Some(sanitizer) => {
                let first_pass_html =
                    Self::perform_initial_sanitization(sanitizer, &self.html).unwrap();

                // due to malicious html crafting
                // (e.g. <<foo>script>...</script>, or <div <!-- comment -->> as in tests),
                // we need to run sanitization several times to truly remove unwanted tags,
                // because lol-html happily accepts this garbage (by design?)
                let final_html =
                    Self::perform_final_sanitization(sanitizer, &first_pass_html).unwrap();

                String::from_utf8(final_html).unwrap()
            }
        };

        match rewriter {
            None => sanitized_html,
            Some(rewriter) => {
                let rewritten_html = rewriter.perform_handler_rewrite(sanitized_html).unwrap();
                String::from_utf8(rewritten_html).unwrap()
            }
        }
    }

    fn perform_initial_sanitization(
        sanitizer: &SelmaSanitizer,
        html: &String,
    ) -> Result<Vec<u8>, Error> {
        let mut output = vec![];
        {
            let mut rewriter = HtmlRewriter::new(
                Settings {
                    document_content_handlers: vec![
                        doctype!(|d| {
                            sanitizer.sanitize_doctype(d);
                            Ok(())
                        }),
                        doc_comments!(|c| {
                            sanitizer.sanitize_comment(c);
                            Ok(())
                        }),
                    ],
                    element_content_handlers: vec![element!("*", |el| {
                        sanitizer.try_remove_element(el);

                        Ok(())
                    })],
                    ..Settings::default()
                },
                |c: &[u8]| output.extend_from_slice(c),
            );
            rewriter.write(html.as_bytes()).unwrap();
        }
        Ok(output)
    }

    fn perform_final_sanitization(
        sanitizer: &SelmaSanitizer,
        html: &[u8],
    ) -> Result<Vec<u8>, Error> {
        let mut output = vec![];
        {
            let mut rewriter = HtmlRewriter::new(
                Settings {
                    element_content_handlers: vec![element!("*", |el| {
                        sanitizer.sanitize_attributes(el);

                        Ok(())
                    })],
                    ..Settings::default()
                },
                |c: &[u8]| output.extend_from_slice(c),
            );
            rewriter.write(html).unwrap();
        }
        Ok(output)
    }
}

pub fn init(m_selma: RModule) -> Result<(), Error> {
    let c_html = m_selma.define_class("HTML", Default::default()).unwrap();

    c_html.define_singleton_method("new", function!(SelmaHTML::new, 1))?;
    c_html
        .define_private_method("selma_rewrite", method!(SelmaHTML::rewrite, 2))
        .expect("cannot define private method: selma_rewrite");

    element::init(c_html);
    end_tag::init(c_html);

    Ok(())
}

pub mod element;
pub mod end_tag;

use std::borrow::Cow;

use lol_html::{
    doc_comments, doctype, element,
    html_content::{ContentType, Element, TextChunk},
    text, ElementContentHandlers, HtmlRewriter, Selector, Settings,
};
use magnus::{
    exception, function, method, scan_args, Error, Module, Object, RArray, RModule, Value,
};

use crate::{
    html::{element::SelmaHTMLElement, end_tag::SelmaHTMLEndTag},
    sanitizer::SelmaSanitizer,
    selector::SelmaSelector,
    wrapped_struct::WrappedStruct,
};

#[derive(Clone, Debug)]
struct Handler {
    rb_handler: Value,
    rb_selector: WrappedStruct<SelmaSelector>,
    total_element_handler_calls: usize,
    total_elapsed_element_handlers: f64,

    total_text_handler_calls: usize,
    total_elapsed_text_handlers: f64,

    encountered_elements: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct Rewriter {
    sanitizer: Option<SelmaSanitizer>,
    handlers: Vec<Handler>,
    total_elapsed: f64,
}

#[derive(Clone, Debug)]
#[magnus::wrap(class = "Selma::Rewriter")]
pub struct SelmaRewriter(std::cell::RefCell<Rewriter>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for SelmaRewriter {}

impl SelmaRewriter {
    const SELMA_ON_END_TAG: &str = "on_end_tag";
    const SELMA_HANDLE_ELEMENT: &str = "handle_element";
    const SELMA_HANDLE_TEXT: &str = "handle_text";

    /// @yard
    /// @def new(sanitizer: Selma::Sanitizer.new(Selma::Sanitizer::Config::DEFAULT), handlers: [])
    /// @param sanitizer [Selma::Sanitizer] The sanitizer which performs the initial cleanup
    /// @param handlers  [Array<Selma::Selector>] The handlers to use to perform HTML rewriting
    /// @return [Selma::Rewriter]
    fn new(arguments: &[Value]) -> Result<Self, Error> {
        let args = scan_args::scan_args::<(), (), (), (), _, ()>(arguments)?;
        let kw = scan_args::get_kwargs::<
            _,
            (),
            (
                Option<Option<WrappedStruct<SelmaSanitizer>>>,
                Option<RArray>,
            ),
            (),
        >(args.keywords, &[], &["sanitizer", "handlers"])?;

        let (rb_sanitizer, rb_handlers) = kw.optional;

        let sanitizer = match rb_sanitizer {
            None => {
                let default_sanitizer = SelmaSanitizer::new(&[])?;
                let wrapped_sanitizer = WrappedStruct::from(default_sanitizer);
                wrapped_sanitizer.funcall::<&str, (), Value>("setup", ())?;
                Some(wrapped_sanitizer.get().unwrap().clone())
            }
            Some(sanitizer_value) => match sanitizer_value {
                None => None,
                Some(sanitizer) => {
                    sanitizer.funcall::<&str, (), Value>("setup", ())?;
                    Some(sanitizer.get().unwrap().clone())
                }
            },
        };

        let handlers = match rb_handlers {
            None => vec![],
            Some(rb_handlers) => {
                let mut handlers: Vec<Handler> = vec![];
                for r in rb_handlers.each() {
                    let rb_handler = r.unwrap();

                    // prevents missing #selector from ruining things
                    if !rb_handler.respond_to("selector", true).unwrap() {
                        return Err(magnus::Error::new(
                            exception::type_error(),
                            "Handler values must be instantiated classes",
                        ));
                    }

                    let rb_selector = rb_handler.funcall("selector", ()).unwrap();
                    handlers.push(Handler {
                        rb_handler,
                        rb_selector,
                        total_element_handler_calls: 0,
                        total_elapsed_element_handlers: 0.0,

                        total_text_handler_calls: 0,
                        total_elapsed_text_handlers: 0.0,

                        encountered_elements: vec![],
                    })
                }
                handlers
            }
        };

        if sanitizer.is_none() && handlers.is_empty() {
            return Err(magnus::Error::new(
                exception::arg_error(),
                "Must provide a sanitizer or a handler",
            ));
        }

        Ok(Self(std::cell::RefCell::new(Rewriter {
            sanitizer,
            handlers,
            total_elapsed: 0.0,
        })))
    }

    /// Perform HTML rewrite sequence.
    fn rewrite(&self, html: String) -> Result<String, Error> {
        let sanitized_html = match &self.0.borrow().sanitizer {
            None => html,
            Some(sanitizer) => {
                let first_pass_html = Self::perform_initial_sanitization(sanitizer, &html).unwrap();

                // due to malicious html crafting
                // (e.g. <<foo>script>...</script>, or <div <!-- comment -->> as in tests),
                // we need to run sanitization several times to truly remove unwanted tags,
                // because lol-html happily accepts this garbage (by design?)
                let final_html =
                    Self::perform_final_sanitization(sanitizer, &first_pass_html).unwrap();

                String::from_utf8(final_html).unwrap()
            }
        };

        let rewritten_html = Self::perform_handler_rewrite(self, sanitized_html).unwrap();
        Ok(String::from_utf8(rewritten_html).unwrap())
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

    pub fn perform_handler_rewrite(&self, html: String) -> Result<Vec<u8>, Error> {
        // TODO: this should be done ahead of time, not on every call
        // let element_content_handlers = Self::construct_handlers(self);
        let mut element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)> = vec![];

        self.0.borrow().handlers.iter().for_each(|h| {
            let selector = h.rb_selector.get().unwrap();

            // TODO: test final raise by simulating errors
            if selector.match_element().is_some() {
                element_content_handlers.push(element!(selector.match_element().unwrap(), |el| {
                    Self::process_element_handlers(self, el);
                    Ok(())
                }));
            }
            if selector.match_text_within().is_some() {
                element_content_handlers.push(text!(
                    selector.match_text_within().unwrap(),
                    |text| {
                        Self::process_text_handlers(self, text);
                        Ok(())
                    }
                ));
            }
        });
        let mut output = vec![];
        {
            let mut rewriter = HtmlRewriter::new(
                Settings {
                    element_content_handlers,
                    ..Settings::default()
                },
                |c: &[u8]| output.extend_from_slice(c),
            );
            rewriter.write(html.as_bytes()).unwrap();
        }
        Ok(output)
    }

    // fn construct_handlers(&self) -> Vec<(Cow<Selector>, ElementContentHandlers<'static>)> {
    //     let mut element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)> = vec![];

    //     self.0.borrow().handlers.iter().for_each(|h| {
    //         let selector = &h.selector;
    //         // TODO: test final raise by simulating errors
    //         if !selector.match_element().is_empty() {
    //             element_content_handlers.push(element!(selector.match_element(), |el| {
    //                 Self::process_element_handlers(self, el);
    //                 Ok(())
    //             }));
    //         }
    //         if !selector.text_element().is_empty() {
    //             element_content_handlers.push(text!(selector.match_element(), |text| {
    //                 Self::process_text_handlers(self, text);
    //                 Ok(())
    //             }));
    //         }
    //     });
    //     element_content_handlers
    // }

    fn process_element_handlers(&self, element: &mut Element) {
        let handlers = unsafe { &(*self.0.as_ptr()).handlers };
        handlers.iter().for_each(|handler| {
            if handler
                .rb_handler
                .respond_to(Self::SELMA_ON_END_TAG, true)
                .unwrap()
            {
                element
                    .on_end_tag(move |end_tag| {
                        let rb_end_tag = SelmaHTMLEndTag::new(end_tag);

                        handler
                            .rb_handler
                            .funcall::<_, _, Value>(Self::SELMA_ON_END_TAG, (rb_end_tag,))
                            .unwrap();
                        Ok(())
                    })
                    .unwrap();
            }

            // prevents missing `handle_element` function
            if handler
                .rb_handler
                .respond_to(Self::SELMA_HANDLE_ELEMENT, true)
                .unwrap()
            {
                let rb_element = SelmaHTMLElement::new(element);

                handler
                    .rb_handler
                    .funcall::<_, _, Value>(Self::SELMA_HANDLE_ELEMENT, (rb_element,))
                    .unwrap();
            }
        });
    }

    fn process_text_handlers(&self, text: &mut TextChunk) {
        self.0.borrow().handlers.iter().for_each(|handler| {
            // prevents missing `handle_text` function
            if handler
                .rb_handler
                .respond_to(Self::SELMA_HANDLE_TEXT, true)
                .unwrap()
            {
                // if !handler.selector.ignore_text_within().is_empty()
                //     && !handler.encountered_elements.is_empty()
                {}

                let content = text.as_str();
                let rb_result: Result<String, Error> = handler
                    .rb_handler
                    .funcall(Self::SELMA_HANDLE_TEXT, (content,));

                match rb_result {
                    Err(_) => {}
                    Ok(returned_string) => {
                        // do the replace iff the incoming and outgoing strings are not equal
                        text.replace(&returned_string, ContentType::Text)
                    }
                }
            }
        });
    }
}

pub fn init(m_selma: RModule) -> Result<(), Error> {
    let c_rewriter = m_selma
        .define_class("Rewriter", Default::default())
        .expect("cannot find class Selma::Rewriter");

    c_rewriter.define_singleton_method("new", function!(SelmaRewriter::new, -1))?;
    c_rewriter
        .define_method("rewrite", method!(SelmaRewriter::rewrite, 1))
        .expect("cannot define method `rewrite`");

    Ok(())
}

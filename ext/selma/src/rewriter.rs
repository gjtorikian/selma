use lol_html::{
    doc_comments, doctype, element,
    html_content::{Element, TextChunk},
    text, DocumentContentHandlers, ElementContentHandlers, HtmlRewriter, Selector, Settings,
};
use magnus::{
    exception, function, method, scan_args,
    typed_data::Obj,
    value::{Opaque, ReprValue},
    Module, Object, RArray, RModule, Ruby, Value,
};

use std::{borrow::Cow, cell::RefCell, primitive::str, rc::Rc};

use crate::{
    html::{element::SelmaHTMLElement, end_tag::SelmaHTMLEndTag, text_chunk::SelmaHTMLTextChunk},
    sanitizer::SelmaSanitizer,
    selector::SelmaSelector,
    tags::Tag,
};

#[derive(Clone)]
pub struct Handler {
    rb_handler: Opaque<Value>,
    rb_selector: Opaque<Obj<SelmaSelector>>,
    // total_element_handler_calls: usize,
    // total_elapsed_element_handlers: f64,

    // total_text_handler_calls: usize,
    // total_elapsed_text_handlers: f64,
}

pub struct Rewriter {
    sanitizer: Option<SelmaSanitizer>,
    handlers: Vec<Handler>,
    // total_elapsed: f64,
}

#[magnus::wrap(class = "Selma::Rewriter")]
pub struct SelmaRewriter(std::cell::RefCell<Rewriter>);

type RewriterValues = (Option<Option<Obj<SelmaSanitizer>>>, Option<RArray>);

impl SelmaRewriter {
    const SELMA_ON_END_TAG: &'static str = "on_end_tag";
    const SELMA_HANDLE_ELEMENT: &'static str = "handle_element";
    const SELMA_HANDLE_TEXT_CHUNK: &'static str = "handle_text_chunk";

    /// @yard
    /// @def new(sanitizer: Selma::Sanitizer.new(Selma::Sanitizer::Config::DEFAULT), handlers: [])
    /// @param sanitizer [Selma::Sanitizer] The sanitizer which performs the initial cleanup
    /// @param handlers  [Array<Selma::Selector>] The handlers to use to perform HTML rewriting
    /// @return [Selma::Rewriter]
    fn new(args: &[Value]) -> Result<Self, magnus::Error> {
        let (rb_sanitizer, rb_handlers) = Self::scan_parse_args(args)?;

        let sanitizer = match rb_sanitizer {
            None => {
                // no `sanitizer:` provided, use default
                let default_sanitizer = SelmaSanitizer::new(&[])?;
                let wrapped_sanitizer = Obj::wrap(default_sanitizer);
                wrapped_sanitizer.funcall::<&str, (), Value>("setup", ())?;
                Some(wrapped_sanitizer.get().to_owned())
            }
            Some(sanitizer_value) => match sanitizer_value {
                None => None, // no `sanitizer:` provided, use default
                Some(sanitizer) => {
                    sanitizer.funcall::<&str, (), Value>("setup", ())?;
                    Some(sanitizer.get().to_owned())
                }
            },
        };

        let handlers = match rb_handlers {
            None => vec![],
            Some(rb_handlers) => {
                let mut handlers: Vec<Handler> = vec![];

                for h in rb_handlers.each() {
                    let rb_handler = h.unwrap();

                    // prevents missing #selector from ruining things
                    if !rb_handler.respond_to("selector", true).unwrap() {
                        let classname = unsafe { rb_handler.classname() };
                        return Err(magnus::Error::new(
                            exception::no_method_error(),
                            format!(
                                "Could not call #selector on {classname:?}; is this an object that defines it?",

                            ),
                        ));
                    }

                    let rb_selector: Obj<SelmaSelector> = match rb_handler.funcall("selector", ()) {
                        Err(err) => {
                            return Err(magnus::Error::new(
                                exception::type_error(),
                                format!("Error instantiating selector: {err:?}"),
                            ));
                        }
                        Ok(rb_selector) => rb_selector,
                    };
                    let handler = Handler {
                        rb_handler: Opaque::from(rb_handler),
                        rb_selector: Opaque::from(rb_selector),
                        // total_element_handler_calls: 0,
                        // total_elapsed_element_handlers: 0.0,

                        // total_text_handler_calls: 0,
                        // total_elapsed_text_handlers: 0.0,
                    };
                    handlers.push(handler);
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
            // total_elapsed: 0.0,
        })))
    }

    #[allow(clippy::let_unit_value)]
    fn scan_parse_args(args: &[Value]) -> Result<RewriterValues, magnus::Error> {
        let args = scan_args::scan_args(args)?;
        let _: () = args.required;
        let _: () = args.optional;
        let _: () = args.splat;
        let _: () = args.trailing;
        let _: () = args.block;

        let kwargs = scan_args::get_kwargs::<
            _,
            (),
            (Option<Option<Obj<SelmaSanitizer>>>, Option<RArray>),
            (),
        >(args.keywords, &[], &["sanitizer", "handlers"])?;
        let (rb_sanitizer, rb_handlers) = kwargs.optional;

        Ok((rb_sanitizer, rb_handlers))
    }

    /// Perform HTML rewrite sequence.
    fn rewrite(&self, html: String) -> Result<String, magnus::Error> {
        let binding = self.0.borrow_mut();
        let handlers = &binding.handlers;
        let sanitizer = &binding.sanitizer;

        let rewritten_html = match Self::perform_handler_rewrite(self, handlers, html) {
            Ok(html) => html,
            Err(err) => return Err(err),
        };

        let sanitized_html = match sanitizer {
            None => rewritten_html,
            Some(sanitizer) => match Self::perform_sanitization(sanitizer, &rewritten_html) {
                Ok(sanitized_html) => sanitized_html,
                Err(err) => return Err(err),
            },
        };

        Ok(String::from_utf8(sanitized_html).expect("string should be valid utf8"))
    }

    fn perform_sanitization(
        sanitizer: &SelmaSanitizer,
        html: &Vec<u8>,
    ) -> Result<Vec<u8>, magnus::Error> {
        let mut first_pass_html = vec![];
        {
            let mut document_content_handlers: Vec<DocumentContentHandlers> = vec![];
            if !sanitizer.get_allow_doctype() {
                document_content_handlers.push(doctype!(|d| {
                    sanitizer.remove_doctype(d);
                    Ok(())
                }));
            }
            if !sanitizer.get_allow_comments() {
                document_content_handlers.push(doc_comments!(|c| {
                    sanitizer.remove_comment(c);
                    Ok(())
                }));
            }
            let mut rewriter = HtmlRewriter::new(
                Settings {
                    document_content_handlers,
                    element_content_handlers: vec![element!("*", |el| {
                        sanitizer.try_remove_element(el);
                        if el.removed() {
                            return Ok(());
                        }
                        match sanitizer.sanitize_attributes(el) {
                            Ok(_) => Ok(()),
                            Err(err) => Err(err.to_string().into()),
                        }
                    })],
                    // TODO: allow for MemorySettings to be defined
                    ..Settings::default()
                },
                |c: &[u8]| first_pass_html.extend_from_slice(c),
            );

            let result = rewriter.write(html);
            if result.is_err() {
                return Err(magnus::Error::new(
                    exception::runtime_error(),
                    format!("Failed to sanitize HTML: {}", result.unwrap_err()),
                ));
            }
        }

        let mut output = vec![];
        {
            let mut element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)> = vec![];
            if sanitizer.get_escape_tagfilter() {
                element_content_handlers.push(element!(Tag::ESCAPEWORTHY_TAGS_CSS, |el| {
                    let should_remove = sanitizer.allow_element(el);
                    if should_remove {
                        sanitizer.force_remove_element(el);
                    }

                    Ok(())
                }));
            }

            let mut rewriter = HtmlRewriter::new(
                Settings {
                    element_content_handlers,
                    ..Settings::default()
                },
                |c: &[u8]| output.extend_from_slice(c),
            );

            let result = rewriter.write(first_pass_html.as_slice());
            if result.is_err() {
                return Err(magnus::Error::new(
                    exception::runtime_error(),
                    format!("Failed to sanitize HTML: {}", result.unwrap_err()),
                ));
            }
        }

        Ok(output)
    }

    pub fn perform_handler_rewrite(
        &self,
        handlers: &[Handler],
        html: String,
    ) -> Result<Vec<u8>, magnus::Error> {
        // TODO: this should ideally be done ahead of time, not on every `#rewrite` call
        let mut element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)> = vec![];

        handlers.iter().for_each(|handler| {
            let element_stack: Rc<RefCell<Vec<String>>> = Rc::new(RefCell::new(vec![]));

            let ruby = Ruby::get().unwrap();

            let selector = ruby.get_inner(handler.rb_selector);

            // TODO: test final raise by simulating errors
            if selector.match_element().is_some() {
                let closure_element_stack = element_stack.clone();

                element_content_handlers.push(element!(
                    selector.match_element().unwrap(),
                    move |el| {
                        match Self::process_element_handlers(
                            ruby.get_inner(handler.rb_handler),
                            el,
                            &closure_element_stack.borrow(),
                        ) {
                            Ok(_) => Ok(()),
                            Err(err) => Err(err.to_string().into()),
                        }
                    }
                ));
            }

            if selector.match_text_within().is_some() {
                let closure_element_stack = element_stack.clone();

                element_content_handlers.push(text!(
                    selector.match_text_within().unwrap(),
                    move |text| {
                        let element_stack = closure_element_stack.as_ref().borrow();
                        if selector.ignore_text_within().is_some() {
                            // check if current tag is a tag we should be ignoring text within
                            let head_tag_name = element_stack.last().unwrap().to_string();
                            if selector
                                .ignore_text_within()
                                .unwrap()
                                .iter()
                                .any(|f| f == &head_tag_name)
                            {
                                return Ok(());
                            }
                        }

                        let ruby = Ruby::get().unwrap();
                        match Self::process_text_handlers(ruby.get_inner(handler.rb_handler), text)
                        {
                            Ok(_) => Ok(()),
                            Err(err) => Err(err.to_string().into()),
                        }
                    }
                ));
            }

            // we need to check *every* element we iterate over, to create a stack of elements
            element_content_handlers.push(element!("*", move |el| {
                let tag_name = el.tag_name().to_lowercase();

                // no need to track self-closing tags
                if Tag::tag_from_tag_name(&tag_name).self_closing {
                    return Ok(());
                };

                element_stack.as_ref().borrow_mut().push(tag_name);

                let closure_element_stack = element_stack.clone();

                el.end_tag_handlers()
                    .unwrap()
                    .push(Box::new(move |_end_tag| {
                        let mut stack = closure_element_stack.as_ref().borrow_mut();
                        stack.pop();
                        Ok(())
                    }));

                Ok(())
            }));
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
            match rewriter.write(html.as_bytes()) {
                Ok(_) => {}
                Err(err) => {
                    return Err(magnus::Error::new(
                        exception::runtime_error(),
                        format!("{err:?}"),
                    ));
                }
            }
        }
        Ok(output)
    }

    fn process_element_handlers(
        rb_handler: Value,
        element: &mut Element,
        ancestors: &[String],
    ) -> Result<(), magnus::Error> {
        // if `on_end_tag` function is defined, call it
        if rb_handler.respond_to(Self::SELMA_ON_END_TAG, true).unwrap() {
            // TODO: error here is an "EndTagError"
            element
                .end_tag_handlers()
                .unwrap()
                .push(Box::new(move |end_tag| {
                    let rb_end_tag = SelmaHTMLEndTag::new(end_tag);

                    match rb_handler.funcall::<_, _, Value>(Self::SELMA_ON_END_TAG, (rb_end_tag,)) {
                        Ok(_) => Ok(()),
                        Err(err) => Err(err.to_string().into()),
                    }
                }));
        }

        let rb_element = SelmaHTMLElement::new(element, ancestors);
        let rb_result =
            rb_handler.funcall::<_, _, Value>(Self::SELMA_HANDLE_ELEMENT, (rb_element,));
        match rb_result {
            Ok(_) => Ok(()),
            Err(err) => Err(err),
        }
    }

    fn process_text_handlers(
        rb_handler: Value,
        text_chunk: &mut TextChunk,
    ) -> Result<(), magnus::Error> {
        // prevents missing `handle_text_chunk` function
        let content = text_chunk.as_str();

        // seems that sometimes lol-html returns blank text / EOLs?
        if content.is_empty() {
            return Ok(());
        }

        let rb_text_chunk = SelmaHTMLTextChunk::new(text_chunk);
        match rb_handler.funcall::<_, _, Value>(Self::SELMA_HANDLE_TEXT_CHUNK, (rb_text_chunk,)) {
            Ok(_) => Ok(()),
            Err(err) => Err(magnus::Error::new(
                exception::runtime_error(),
                format!("{err:?}"),
            )),
        }
    }
}

pub fn init(m_selma: RModule) -> Result<(), magnus::Error> {
    let c_rewriter = m_selma
        .define_class("Rewriter", magnus::class::object())
        .expect("cannot define class Selma::Rewriter");

    c_rewriter.define_singleton_method("new", function!(SelmaRewriter::new, -1))?;
    c_rewriter
        .define_method("rewrite", method!(SelmaRewriter::rewrite, 1))
        .expect("cannot define method `rewrite`");

    Ok(())
}

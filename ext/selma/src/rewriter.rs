use lol_html::{
    doc_comments, doctype, element,
    html_content::{Element, TextChunk},
    text, DocumentContentHandlers, ElementContentHandlers, HtmlRewriter, MemorySettings, Selector,
    Settings,
};
use magnus::{
    exception, function, gc, method,
    r_hash::ForEach,
    scan_args,
    typed_data::Obj,
    value::{Opaque, ReprValue},
    DataTypeFunctions, Integer, IntoValue, Module, Object, RArray, RHash, RModule, Ruby, Symbol,
    TypedData, Value,
};

use std::{
    borrow::Cow,
    cell::{Ref, RefCell},
    mem,
    ops::Deref,
    primitive::str,
    rc::Rc,
};

use crate::{
    html::{element::SelmaHTMLElement, end_tag::SelmaHTMLEndTag, text_chunk::SelmaHTMLTextChunk},
    native_ref_wrap::NativeRefWrap,
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

struct RewriterOptions {
    memory_options: MemorySettings,
}

pub struct Rewriter {
    sanitizer: Option<SelmaSanitizer>,
    handlers: Vec<Handler>,
    options: RewriterOptions,
    // total_elapsed: f64,
}

#[derive(TypedData)]
#[magnus(class = "Selma::Rewriter", free_immediately, mark)]
pub struct SelmaRewriter(std::cell::RefCell<Rewriter>);

impl DataTypeFunctions for SelmaRewriter {
    fn mark(&self, marker: &gc::Marker) {
        self.0.borrow().handlers.iter().for_each(|handler| {
            marker.mark(handler.rb_handler);
        });
    }
}

type RewriterValues = (
    Option<Option<Obj<SelmaSanitizer>>>,
    Option<RArray>,
    Option<RHash>,
);

impl SelmaRewriter {
    const SELMA_ON_END_TAG: &'static str = "on_end_tag";
    const SELMA_HANDLE_ELEMENT: &'static str = "handle_element";
    const SELMA_HANDLE_TEXT_CHUNK: &'static str = "handle_text_chunk";

    /// @yard
    /// @def new(sanitizer: Selma::Sanitizer.new(Selma::Sanitizer::Config::DEFAULT), handlers: [])
    /// @param sanitizer [Selma::Sanitizer] The sanitizer which performs the initial cleanup
    /// @param handlers  [Array<Selma::Selector>] The handlers to use to perform HTML rewriting
    /// @param options  [Hash] Any additional options to pass to the rewriter
    /// @return [Selma::Rewriter]
    fn new(args: &[Value]) -> Result<Self, magnus::Error> {
        let (rb_sanitizer, rb_handlers, rb_options) = Self::scan_parse_args(args)?;

        let sanitizer = match rb_sanitizer {
            None => {
                // no `sanitizer:` provided, use default
                let default_sanitizer = SelmaSanitizer::new(&[])?;
                let wrapped_sanitizer = Obj::wrap(default_sanitizer);
                wrapped_sanitizer.funcall::<&str, (), Value>("setup", ())?;
                Some(wrapped_sanitizer.deref().to_owned())
            }
            Some(sanitizer_value) => match sanitizer_value {
                None => None, // no `sanitizer:` provided, use default
                Some(sanitizer) => {
                    sanitizer.funcall::<&str, (), Value>("setup", ())?;
                    Some(sanitizer.deref().to_owned())
                }
            },
        };

        let handlers = match rb_handlers {
            None => vec![],
            Some(rb_handlers) => {
                let mut handlers: Vec<Handler> = vec![];

                for rb_handler in rb_handlers.into_iter() {
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

        let mut rewriter_options = RewriterOptions::new();

        match rb_options {
            None => {}
            Some(options) => {
                options.foreach(|key: Symbol, value: RHash| {
                    let key = key.to_string();
                    match key.as_str() {
                        "memory" => {
                            let max_allowed_memory_usage = value.get(Symbol::new("max_allowed_memory_usage"));
                            if max_allowed_memory_usage.is_some() {
                                let max_allowed_memory_usage = max_allowed_memory_usage.unwrap();
                                let max_allowed_memory_usage =
                                    Integer::from_value(max_allowed_memory_usage);
                                if max_allowed_memory_usage.is_some() {
                                    match max_allowed_memory_usage.unwrap().to_u64() {
                                        Ok(max_allowed_memory_usage) => {
                                            rewriter_options.memory_options.max_allowed_memory_usage =
                                                max_allowed_memory_usage as usize;
                                        }
                                        Err(_e) => {
                                            return Err(magnus::Error::new(
                                                exception::arg_error(),
                                                "max_allowed_memory_usage must be a positive integer",
                                            ));
                                        }
                                    }
                                } else {
                                    rewriter_options.memory_options.max_allowed_memory_usage = MemorySettings::default().max_allowed_memory_usage;
                                }
                            }

                            let preallocated_parsing_buffer_size = value.get(Symbol::new("preallocated_parsing_buffer_size"));
                            if preallocated_parsing_buffer_size.is_some() {
                                let preallocated_parsing_buffer_size = preallocated_parsing_buffer_size.unwrap();
                                let preallocated_parsing_buffer_size =
                                    Integer::from_value(preallocated_parsing_buffer_size);
                                if preallocated_parsing_buffer_size.is_some() {
                                    match preallocated_parsing_buffer_size.unwrap().to_u64() {
                                        Ok(preallocated_parsing_buffer_size) => {
                                            rewriter_options.memory_options.preallocated_parsing_buffer_size =
                                                preallocated_parsing_buffer_size as usize;
                                        }
                                        Err(_e) => {
                                            return Err(magnus::Error::new(
                                                exception::arg_error(),
                                                "preallocated_parsing_buffer_size must be a positive integer",
                                            ));
                                        }
                                    }
                                } else {
                                    rewriter_options.memory_options.preallocated_parsing_buffer_size = MemorySettings::default().preallocated_parsing_buffer_size;
                                }
                            }
                        }
                        _ => {
                            return Err(magnus::Error::new(
                                exception::arg_error(),
                                format!("Unknown option: {key:?}"),
                            ));
                        }
                    }
                    Ok(ForEach::Continue)
                })?;
            }
        }

        if rewriter_options
            .memory_options
            .preallocated_parsing_buffer_size
            > rewriter_options.memory_options.max_allowed_memory_usage
        {
            return Err(magnus::Error::new(
                exception::arg_error(),
                "max_allowed_memory_usage must be greater than preallocated_parsing_buffer_size",
            ));
        }

        Ok(Self(std::cell::RefCell::new(Rewriter {
            sanitizer,
            handlers,
            options: rewriter_options,
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
            (
                Option<Option<Obj<SelmaSanitizer>>>,
                Option<RArray>,
                Option<RHash>,
            ),
            (),
        >(args.keywords, &[], &["sanitizer", "handlers", "options"])?;
        let (rb_sanitizer, rb_handlers, rb_options) = kwargs.optional;

        Ok((rb_sanitizer, rb_handlers, rb_options))
    }

    /// Perform HTML rewrite sequence.
    fn rewrite(&self, html: String) -> Result<String, magnus::Error> {
        let binding = self.0.borrow();

        let mut sanitizer_document_content_handlers: Vec<DocumentContentHandlers> = vec![];
        let mut sanitizer_element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)> =
            vec![];

        match &binding.sanitizer {
            None => (),
            Some(sanitizer) => {
                if !sanitizer.get_allow_doctype() {
                    sanitizer_document_content_handlers.push(doctype!(|d| {
                        sanitizer.remove_doctype(d);
                        Ok(())
                    }));
                }
                if !sanitizer.get_allow_comments() {
                    sanitizer_document_content_handlers.push(doc_comments!(|c| {
                        sanitizer.remove_comment(c);
                        Ok(())
                    }));
                }
                sanitizer_element_content_handlers.push(element!("*", |el| {
                    sanitizer.try_remove_element(el);
                    if el.removed() {
                        return Ok(());
                    }
                    // if it was removed, there are no attributes to sanitize
                    match sanitizer.sanitize_attributes(el) {
                        Ok(_) => Ok(()),
                        Err(err) => Err(err.to_string().into()),
                    }
                }));
            }
        };

        let handlers: &Vec<Handler> = &binding.handlers;

        match Self::perform_handler_rewrite(
            self,
            sanitizer_document_content_handlers,
            sanitizer_element_content_handlers,
            handlers,
            html,
        ) {
            Ok(rewritten_html) => match &binding.sanitizer {
                None => match String::from_utf8(rewritten_html) {
                    Ok(output) => Ok(output),
                    Err(err) => Err(magnus::Error::new(
                        exception::runtime_error(),
                        format!("{err:?}"),
                    )),
                },
                Some(sanitizer) => {
                    Self::perform_final_sanitization(self, sanitizer, rewritten_html)
                }
            },
            Err(err) => Err(err),
        }
    }

    // to get rid of some really nasty edge cases with dangerous tags, we perform one more
    // sanitization pass at the end
    fn perform_final_sanitization(
        &self,
        sanitizer: &SelmaSanitizer,
        html: Vec<u8>,
    ) -> Result<String, magnus::Error> {
        // TODO: this should ideally be done ahead of time on `initialize`, not on every `#rewrite` call
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

        match Self::run_rewrite(self, vec![], element_content_handlers, html.as_slice()) {
            Ok(rewritten_html) => match String::from_utf8(rewritten_html) {
                Ok(output) => Ok(output),
                Err(err) => Err(magnus::Error::new(
                    exception::runtime_error(),
                    format!("{err:?}"),
                )),
            },
            Err(err) => Err(err),
        }
    }

    pub fn perform_handler_rewrite(
        &self,
        sanitizer_document_content_handlers: Vec<DocumentContentHandlers>,
        sanitizer_element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)>,
        handlers: &[Handler],
        html: String,
    ) -> Result<Vec<u8>, magnus::Error> {
        // TODO: this should ideally be done ahead of time on `initialize`, not on every `#rewrite` call
        let mut element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)> = vec![];

        // have sanitization happen first
        element_content_handlers.extend(sanitizer_element_content_handlers);

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
                            handler,
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

                        match Self::process_text_handlers(handler, text) {
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

                if let Some(end_tag_handlers) = el.end_tag_handlers() {
                    end_tag_handlers.push(Box::new(move |_end_tag| {
                        closure_element_stack.as_ref().borrow_mut().pop();
                        Ok(())
                    }));
                }

                Ok(())
            }));
        });

        Self::run_rewrite(
            self,
            sanitizer_document_content_handlers,
            element_content_handlers,
            html.as_bytes(),
        )
    }

    fn run_rewrite(
        &self,
        document_content_handlers: Vec<DocumentContentHandlers>,
        element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)>,
        html: &[u8],
    ) -> Result<Vec<u8>, magnus::Error> {
        let binding = &self.0.borrow();
        let mut output = vec![];
        {
            let mut rewriter = HtmlRewriter::new(
                Settings {
                    document_content_handlers,
                    element_content_handlers,
                    memory_settings: Self::get_memory_options(binding),
                    ..Settings::default()
                },
                |c: &[u8]| output.extend_from_slice(c),
            );
            match rewriter.write(html) {
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
        handler: &Handler,
        element: &mut Element,
        ancestors: &[String],
    ) -> Result<(), magnus::Error> {
        let rb_handler = handler.rb_handler.into_value();

        // if `on_end_tag` function is defined, call it
        if rb_handler.respond_to(Self::SELMA_ON_END_TAG, true).unwrap() {
            // TODO: error here is an "EndTagError"
            element
                .end_tag_handlers()
                .unwrap()
                .push(Box::new(move |end_tag| {
                    let (ref_wrap, anchor) = NativeRefWrap::wrap(end_tag);

                    let rb_end_tag = SelmaHTMLEndTag::new(ref_wrap);

                    let result =
                        rb_handler.funcall::<_, _, Value>(Self::SELMA_ON_END_TAG, (rb_end_tag,));

                    mem::drop(anchor);

                    match result {
                        Ok(_) => Ok(()),
                        Err(err) => Err(err.to_string().into()),
                    }
                }));
        }

        let (ref_wrap, anchor) = NativeRefWrap::wrap(element);
        let rb_element = SelmaHTMLElement::new(ref_wrap, ancestors);
        let result = rb_handler.funcall::<_, _, Value>(Self::SELMA_HANDLE_ELEMENT, (rb_element,));

        mem::drop(anchor);

        match result {
            Ok(_) => Ok(()),
            Err(err) => Err(magnus::Error::new(
                exception::runtime_error(),
                format!("{err:?}"),
            )),
        }
    }

    fn process_text_handlers(
        handler: &Handler,
        text_chunk: &mut TextChunk,
    ) -> Result<(), magnus::Error> {
        let rb_handler = handler.rb_handler.into_value();

        // prevents missing `handle_text_chunk` function
        let content = text_chunk.as_str();

        // seems that sometimes lol-html returns blank text / EOLs?
        if content.is_empty() {
            return Ok(());
        }

        let (ref_wrap, anchor) = NativeRefWrap::wrap(text_chunk);

        let rb_text_chunk = SelmaHTMLTextChunk::new(ref_wrap);
        let result =
            rb_handler.funcall::<_, _, Value>(Self::SELMA_HANDLE_TEXT_CHUNK, (rb_text_chunk,));

        mem::drop(anchor);

        match result {
            Ok(_) => Ok(()),
            Err(err) => Err(magnus::Error::new(
                exception::runtime_error(),
                format!("{err:?}"),
            )),
        }
    }

    fn get_memory_options(binding: &Ref<Rewriter>) -> MemorySettings {
        let options = &binding.options.memory_options;
        MemorySettings {
            max_allowed_memory_usage: options.max_allowed_memory_usage,
            preallocated_parsing_buffer_size: options.preallocated_parsing_buffer_size,
        }
    }
}

impl RewriterOptions {
    pub fn new() -> Self {
        Self {
            memory_options: MemorySettings::default(),
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

use std::borrow::Cow;

use lol_html::{
    element,
    html_content::{ContentType, Element, TextChunk},
    text, ElementContentHandlers, HtmlRewriter, Selector, Settings,
};
use magnus::{function, Error, Module, Object, RArray, RClass, RModule, Value};

use crate::{
    html::element::SelmaHTMLElement,
    selector::{self, SelmaSelector},
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
    handlers: Vec<Handler>,
    total_elapsed: f64,
}

#[derive(Clone, Debug)]
#[magnus::wrap(class = "Selma::Rewriter")]
pub struct SelmaRewriter(std::cell::RefCell<Rewriter>);

impl SelmaRewriter {
    const SELMA_ON_END_TAG: &str = "on_end_tag";
    const SELMA_HANDLE_ELEMENT: &str = "handle_element";
    const SELMA_HANDLE_TEXT: &str = "handle_text";

    fn new(rb_handlers: RArray) -> Self {
        if rb_handlers.is_empty() {
            Self(std::cell::RefCell::new(Rewriter {
                handlers: vec![],
                total_elapsed: 0.0,
            }))
        } else {
            let mut handlers: Vec<Handler> = vec![];
            for r in rb_handlers.each() {
                let rb_handler = r.unwrap();
                // prevents missing #selector from ruining things
                let has_selector = rb_handler.respond_to("selector", true).unwrap();
                if !has_selector {
                    continue;
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

            Self(std::cell::RefCell::new(Rewriter {
                handlers,
                total_elapsed: 0.0,
            }))
        }
    }

    pub fn perform_handler_rewrite(&self, html: String) -> Result<Vec<u8>, Error> {
        // let element_content_handlers = Self::construct_handlers(self);
        let mut element_content_handlers: Vec<(Cow<Selector>, ElementContentHandlers)> = vec![];

        self.0.borrow().handlers.iter().for_each(|h| {
            let selector = h.rb_selector.get().unwrap();

            // TODO: test final raise by simulating errors
            if !selector.match_element().is_empty() {
                element_content_handlers.push(element!(selector.match_element(), |el| {
                    Self::process_element_handlers(self, el);
                    Ok(())
                }));
            }
            // if !selector.text_element().is_empty() {
            //     element_content_handlers.push(text!(selector.match_element(), |text| {
            //         Self::process_text_handlers(self, text);
            //         Ok(())
            //     }));
            // }
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
        self.0.borrow().handlers.iter().for_each(|handler| {
            if handler
                .rb_handler
                .respond_to(Self::SELMA_ON_END_TAG, true)
                .unwrap()
            {
                // element
                //     .on_end_tag(move |end| {
                //         handler.rb_handler.funcall(Self::SELMA_ON_END_TAG, (end,));
                //         Ok(())
                //     })
                //     .unwrap();
            }

            // prevents missing `handle_element` function
            if handler
                .rb_handler
                .respond_to(Self::SELMA_HANDLE_ELEMENT, true)
                .unwrap()
            {
                let mut rb_element = SelmaHTMLElement::new(element);

                // handler.rb_handler.ivar_set("@element", rb_element);
                let _: Value = handler
                    .rb_handler
                    .funcall(Self::SELMA_HANDLE_ELEMENT, (rb_element,))
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

    c_rewriter.define_singleton_method("new", function!(SelmaRewriter::new, 1))?;

    Ok(())
}

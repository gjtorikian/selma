use std::cell::RefCell;

use crate::native_ref_wrap::NativeRefWrap;
use lol_html::html_content::{TextChunk, TextType};
use magnus::{exception, method, Error, Module, RClass, Symbol, Value};

struct HTMLTextChunk {
    text_chunk: NativeRefWrap<TextChunk<'static>>,
}

#[magnus::wrap(class = "Selma::HTML::TextChunk")]
pub struct SelmaHTMLTextChunk(RefCell<HTMLTextChunk>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for SelmaHTMLTextChunk {}

impl SelmaHTMLTextChunk {
    pub fn new(ref_wrap: NativeRefWrap<TextChunk<'static>>) -> Self {
        Self(RefCell::new(HTMLTextChunk {
            text_chunk: ref_wrap,
        }))
    }

    fn to_s(&self) -> Result<String, Error> {
        let binding = self.0.borrow();

        if let Ok(tc) = binding.text_chunk.get() {
            Ok(tc.as_str().to_string())
        } else {
            Err(Error::new(
                exception::runtime_error(),
                "`to_s` is not available",
            ))
        }
    }

    fn text_type(&self) -> Result<Symbol, Error> {
        let binding = self.0.borrow();

        if let Ok(tc) = binding.text_chunk.get() {
            match tc.text_type() {
                TextType::Data => Ok(Symbol::new("data")),
                TextType::PlainText => Ok(Symbol::new("plain_text")),
                TextType::RawText => Ok(Symbol::new("raw_text")),
                TextType::ScriptData => Ok(Symbol::new("script")),
                TextType::RCData => Ok(Symbol::new("rc_data")),
                TextType::CDataSection => Ok(Symbol::new("cdata_section")),
            }
        } else {
            Err(Error::new(
                exception::runtime_error(),
                "`text_type` is not available",
            ))
        }
    }

    fn is_removed(&self) -> Result<bool, Error> {
        let binding = self.0.borrow();

        match binding.text_chunk.get() {
            Ok(tc) => Ok(tc.removed()),
            Err(_) => Err(Error::new(
                exception::runtime_error(),
                "`is_removed` is not available",
            )),
        }
    }

    fn before(&self, args: &[Value]) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let text_chunk = binding.text_chunk.get_mut().unwrap();

        let (text_str, content_type) = match crate::scan_text_args(args) {
            Ok((text_str, content_type)) => (text_str, content_type),
            Err(err) => return Err(err),
        };

        text_chunk.before(&text_str, content_type);

        Ok(())
    }

    fn after(&self, args: &[Value]) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let text_chunk = binding.text_chunk.get_mut().unwrap();

        let (text_str, content_type) = match crate::scan_text_args(args) {
            Ok((text_str, content_type)) => (text_str, content_type),
            Err(err) => return Err(err),
        };

        text_chunk.after(&text_str, content_type);

        Ok(())
    }

    fn replace(&self, args: &[Value]) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let text_chunk = binding.text_chunk.get_mut().unwrap();

        let (text_str, content_type) = match crate::scan_text_args(args) {
            Ok((text_str, content_type)) => (text_str, content_type),
            Err(err) => return Err(err),
        };

        text_chunk.replace(&text_str, content_type);

        Ok(())
    }
}

pub fn init(c_html: RClass) -> Result<(), Error> {
    let c_text_chunk = c_html
        .define_class("TextChunk", magnus::class::object())
        .expect("cannot define class Selma::HTML::TextChunk");

    c_text_chunk.define_method("to_s", method!(SelmaHTMLTextChunk::to_s, 0))?;
    c_text_chunk.define_method("content", method!(SelmaHTMLTextChunk::to_s, 0))?;
    c_text_chunk.define_method("text_type", method!(SelmaHTMLTextChunk::text_type, 0))?;
    c_text_chunk.define_method("before", method!(SelmaHTMLTextChunk::before, -1))?;
    c_text_chunk.define_method("after", method!(SelmaHTMLTextChunk::after, -1))?;
    c_text_chunk.define_method("replace", method!(SelmaHTMLTextChunk::replace, -1))?;
    c_text_chunk.define_method("removed?", method!(SelmaHTMLTextChunk::is_removed, 0))?;

    Ok(())
}

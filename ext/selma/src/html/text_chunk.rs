use crate::native_ref_wrap::NativeRefWrap;
use lol_html::html_content::{TextChunk, TextType};
use magnus::{exception, method, Error, Module, RClass, Symbol, Value};

struct HTMLTextChunk {
    text_chunk: NativeRefWrap<TextChunk<'static>>,
}

#[magnus::wrap(class = "Selma::HTML::TextChunk")]
pub struct SelmaHTMLTextChunk(std::cell::RefCell<HTMLTextChunk>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for SelmaHTMLTextChunk {}

impl SelmaHTMLTextChunk {
    pub fn new(text_chunk: &mut TextChunk) -> Self {
        let (ref_wrap, _anchor) = NativeRefWrap::wrap_mut(text_chunk);

        Self(std::cell::RefCell::new(HTMLTextChunk {
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
                TextType::Data => Ok(Symbol::from("data")),
                TextType::PlainText => Ok(Symbol::from("plain_text")),
                TextType::RawText => Ok(Symbol::from("raw_text")),
                TextType::ScriptData => Ok(Symbol::from("script")),
                TextType::RCData => Ok(Symbol::from("rc_data")),
                TextType::CDataSection => Ok(Symbol::from("cdata_section")),
            }
        } else {
            Err(Error::new(
                exception::runtime_error(),
                "`text_type` is not available",
            ))
        }
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
        .define_class("TextChunk", Default::default())
        .expect("cannot find class Selma::HTML::TextChunk");

    c_text_chunk.define_method("to_s", method!(SelmaHTMLTextChunk::to_s, 0))?;
    c_text_chunk.define_method("content", method!(SelmaHTMLTextChunk::to_s, 0))?;
    c_text_chunk.define_method("text_type", method!(SelmaHTMLTextChunk::text_type, 0))?;
    c_text_chunk.define_method("replace", method!(SelmaHTMLTextChunk::replace, -1))?;

    Ok(())
}

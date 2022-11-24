use crate::native_ref_wrap::NativeRefWrap;
use lol_html::html_content::EndTag;
use magnus::{method, Error, Module, RClass};

struct HTMLEndTag {
    end_tag: NativeRefWrap<EndTag<'static>>,
}

#[magnus::wrap(class = "Selma::HTML::Element")]
pub struct SelmaHTMLEndTag(std::cell::RefCell<HTMLEndTag>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for SelmaHTMLEndTag {}

impl SelmaHTMLEndTag {
    pub fn new(end_tag: &mut EndTag) -> Self {
        let (ref_wrap, _anchor) = NativeRefWrap::wrap(end_tag);

        Self(std::cell::RefCell::new(HTMLEndTag { end_tag: ref_wrap }))
    }

    fn tag_name(&self) -> String {
        self.0.borrow().end_tag.get().unwrap().name()
    }
}

pub fn init(c_html: RClass) -> Result<(), Error> {
    let c_end_tag = c_html
        .define_class("EndTag", Default::default())
        .expect("cannot find class Selma::EndTag");

    c_end_tag.define_method("tag_name", method!(SelmaHTMLEndTag::tag_name, 0))?;

    Ok(())
}

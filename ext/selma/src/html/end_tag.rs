use std::cell::RefCell;

use crate::native_ref_wrap::NativeRefWrap;
use lol_html::html_content::EndTag;
use magnus::{method, Error, Module, RClass};

struct HTMLEndTag {
    end_tag: NativeRefWrap<EndTag<'static>>,
}

#[magnus::wrap(class = "Selma::HTML::EndTag")]
pub struct SelmaHTMLEndTag(RefCell<HTMLEndTag>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for SelmaHTMLEndTag {}

impl SelmaHTMLEndTag {
    pub fn new(ref_wrap: NativeRefWrap<EndTag<'static>>) -> Self {
        Self(RefCell::new(HTMLEndTag { end_tag: ref_wrap }))
    }

    fn tag_name(&self) -> String {
        self.0.borrow().end_tag.get().unwrap().name()
    }
}

pub fn init(c_html: RClass) -> Result<(), Error> {
    let c_end_tag = c_html
        .define_class("EndTag", magnus::class::object())
        .expect("cannot define class Selma::HTML::EndTag");

    c_end_tag.define_method("tag_name", method!(SelmaHTMLEndTag::tag_name, 0))?;

    Ok(())
}

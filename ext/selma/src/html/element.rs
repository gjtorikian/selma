use lol_html::html_content::{Attribute as NativeAttribute, Element};
use magnus::{function, method, Error, Module, RClass};

use crate::native_ref_wrap::NativeRefWrap;

struct HTMLElement {
    element: NativeRefWrap<Element<'static, 'static>>,
}

#[magnus::wrap(class = "Selma::HTML::Element")]
pub struct SelmaHTMLElement(std::cell::RefCell<HTMLElement>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for SelmaHTMLElement {}

impl SelmaHTMLElement {
    pub fn new(element: &mut Element) -> Self {
        let (ref_wrap, anchor) = NativeRefWrap::wrap(element);

        Self(std::cell::RefCell::new(HTMLElement { element: ref_wrap }))
    }

    fn tag_name() {}

    fn get_attribute(_x: isize) {}

    fn set_attribute(_x: isize, _y: isize) {}

    fn remove_attribute(&self, attr: String) {
        let mut binding = self.0.borrow_mut();

        binding.element.get_mut().map(|e| e.remove_attribute(&attr));
    }

    fn attributes() {}

    fn prepend(_x: isize, _y: isize) {}
}

pub fn init(c_html: RClass) -> Result<(), Error> {
    let c_element = c_html
        .define_class("Element", Default::default())
        .expect("cannot find class Selma::Element");

    c_element.define_method("tag_name", function!(SelmaHTMLElement::tag_name, 0))?;
    c_element.define_method("[]", function!(SelmaHTMLElement::get_attribute, 1))?;
    c_element.define_method("[]=", function!(SelmaHTMLElement::set_attribute, 2))?;
    c_element.define_method(
        "remove_attribute",
        method!(SelmaHTMLElement::remove_attribute, 1),
    )?;
    c_element.define_method("attributes", function!(SelmaHTMLElement::attributes, 0))?;
    c_element.define_method("prepend", function!(SelmaHTMLElement::prepend, 2))?;

    Ok(())
}

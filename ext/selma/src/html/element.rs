use crate::native_ref_wrap::NativeRefWrap;
use lol_html::html_content::Element;
use magnus::{exception, function, method, Error, Module, RClass, RHash};

struct HTMLElement {
    element: NativeRefWrap<Element<'static, 'static>>,
}

#[magnus::wrap(class = "Selma::HTML::Element")]
pub struct SelmaHTMLElement(std::cell::RefCell<HTMLElement>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for SelmaHTMLElement {}

impl SelmaHTMLElement {
    pub fn new(element: &mut Element) -> Self {
        let (ref_wrap, _anchor) = NativeRefWrap::wrap_mut(element);

        Self(std::cell::RefCell::new(HTMLElement { element: ref_wrap }))
    }

    fn tag_name() {}

    fn get_attribute(&self, attr: String) -> Option<String> {
        let binding = self.0.borrow();
        let element = binding.element.get_ref();
        element.unwrap().get_attribute(&attr)
    }

    fn set_attribute(&self, attr: String, value: String) -> Result<String, Error> {
        let mut binding = self.0.borrow_mut();
        let element = binding.element.get_mut().unwrap();

        match element.set_attribute(&attr, &value) {
            Ok(_) => Ok(value),
            Err(err) => Err(Error::new(
                exception::runtime_error(),
                format!("AttributeNameError: {}", err),
            )),
        }
    }

    fn remove_attribute(&self, attr: String) {
        let mut binding = self.0.borrow_mut();

        if let Ok(e) = binding.element.get_mut() {
            e.remove_attribute(&attr)
        }
    }

    fn attributes(&self) -> Result<RHash, Error> {
        let binding = self.0.borrow();
        let hash = RHash::new();

        if let Ok(e) = binding.element.get_ref() {
            e.attributes()
                .iter()
                .for_each(|attr| match hash.aset(attr.name(), attr.value()) {
                    Ok(_) => {}
                    Err(err) => Err(Error::new(
                        exception::runtime_error(),
                        format!("AttributeNameError: {}", err),
                    ))
                    .unwrap(),
                });
        }
        Ok(hash)
    }

    fn prepend(_x: isize, _y: isize) {}
}

pub fn init(c_html: RClass) -> Result<(), Error> {
    let c_element = c_html
        .define_class("Element", Default::default())
        .expect("cannot find class Selma::Element");

    c_element.define_method("tag_name", function!(SelmaHTMLElement::tag_name, 0))?;
    c_element.define_method("[]", method!(SelmaHTMLElement::get_attribute, 1))?;
    c_element.define_method("[]=", method!(SelmaHTMLElement::set_attribute, 2))?;
    c_element.define_method(
        "remove_attribute",
        method!(SelmaHTMLElement::remove_attribute, 1),
    )?;
    c_element.define_method("attributes", method!(SelmaHTMLElement::attributes, 0))?;
    c_element.define_method("prepend", function!(SelmaHTMLElement::prepend, 2))?;

    Ok(())
}

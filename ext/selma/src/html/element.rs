use std::cell::RefCell;

use crate::native_ref_wrap::NativeRefWrap;
use lol_html::html_content::Element;
use magnus::{method, Error, Module, RArray, RClass, RHash, Ruby, Value};

struct HTMLElement {
    element: NativeRefWrap<Element<'static, 'static>>,
    ancestors: Vec<String>,
}

#[magnus::wrap(class = "Selma::HTML::Element")]
pub struct SelmaHTMLElement(RefCell<HTMLElement>);

/// SAFETY: This is safe because we only access this data when the GVL is held.
unsafe impl Send for SelmaHTMLElement {}

impl SelmaHTMLElement {
    pub fn new(ref_wrap: NativeRefWrap<Element<'static, 'static>>, ancestors: &[String]) -> Self {
        Self(RefCell::new(HTMLElement {
            element: ref_wrap,
            ancestors: ancestors.to_owned(),
        }))
    }

    fn tag_name(&self) -> Result<String, Error> {
        let binding = self.0.borrow();

        match binding.element.get() {
            Ok(e) => Ok(e.tag_name().to_string()),
            Err(_) => Err(Error::new(
                Ruby::get().unwrap().exception_runtime_error(),
                "`tag_name` is not available",
            )),
        }
    }

    fn set_tag_name(&self, name: String) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let ruby = Ruby::get().unwrap();

        if let Ok(element) = binding.element.get_mut() {
            match element.set_tag_name(&name) {
                Ok(_) => Ok(()),
                Err(err) => Err(Error::new(
                    ruby.exception_runtime_error(),
                    format!("{err:?}"),
                )),
            }
        } else {
            Err(Error::new(
                ruby.exception_runtime_error(),
                "`set_tag_name` is not available",
            ))
        }
    }

    fn is_self_closing(&self) -> Result<bool, Error> {
        let binding = self.0.borrow();

        if let Ok(e) = binding.element.get() {
            Ok(e.is_self_closing())
        } else {
            Err(Error::new(
                Ruby::get().unwrap().exception_runtime_error(),
                "`is_self_closing` is not available",
            ))
        }
    }

    fn has_attribute(&self, attr: String) -> Result<bool, Error> {
        let binding = self.0.borrow();

        if let Ok(e) = binding.element.get() {
            Ok(e.has_attribute(&attr))
        } else {
            Err(Error::new(
                Ruby::get().unwrap().exception_runtime_error(),
                "`is_self_closing` is not available",
            ))
        }
    }

    fn get_attribute(&self, attr: String) -> Option<String> {
        let binding = self.0.borrow();
        let element = binding.element.get();
        element.unwrap().get_attribute(&attr)
    }

    fn set_attribute(&self, attr: String, value: String) -> Result<String, Error> {
        let mut binding = self.0.borrow_mut();
        let ruby = Ruby::get().unwrap();
        if let Ok(element) = binding.element.get_mut() {
            match element.set_attribute(&attr, &value) {
                Ok(_) => Ok(value),
                Err(err) => Err(Error::new(
                    ruby.exception_runtime_error(),
                    format!("AttributeNameError: {err:?}"),
                )),
            }
        } else {
            Err(Error::new(
                ruby.exception_runtime_error(),
                "`tag_name` is not available",
            ))
        }
    }

    fn remove_attribute(&self, attr: String) {
        let mut binding = self.0.borrow_mut();

        if let Ok(e) = binding.element.get_mut() {
            e.remove_attribute(&attr)
        }
    }

    fn get_attribute_source_location(&self, attr: String) -> Result<Option<RHash>, Error> {
        let binding = self.0.borrow();
        let ruby = Ruby::get().unwrap();

        let Ok(e) = binding.element.get() else {
            return Ok(None);
        };

        let lowered = attr.to_lowercase();
        let attrs = e.attributes();
        let Some(attribute) = attrs.iter().find(|a| a.name() == lowered) else {
            return Ok(None);
        };

        let Some(name_loc) = attribute.name_source_location() else {
            return Ok(None);
        };

        let hash = ruby.hash_new();
        let name_range = name_loc.bytes();
        hash.aset(
            ruby.to_symbol("name"),
            ruby.range_new(name_range.start, name_range.end, true)?,
        )?;

        match attribute.value_source_location() {
            Some(loc) => {
                let r = loc.bytes();
                hash.aset(
                    ruby.to_symbol("value"),
                    ruby.range_new(r.start, r.end, true)?,
                )?;
            }
            None => {
                hash.aset(ruby.to_symbol("value"), ruby.qnil())?;
            }
        }

        Ok(Some(hash))
    }

    fn get_attributes(&self) -> Result<RHash, Error> {
        let binding = self.0.borrow();
        let ruby = Ruby::get().unwrap();
        let hash = ruby.hash_new();

        if let Ok(e) = binding.element.get() {
            e.attributes()
                .iter()
                .for_each(|attr| match hash.aset(attr.name(), attr.value()) {
                    Ok(_) => {}
                    Err(err) => panic!(
                        "{:?}",
                        Error::new(
                            ruby.exception_runtime_error(),
                            format!("AttributeNameError: {err:?}"),
                        )
                    ),
                });
        }
        Ok(hash)
    }

    fn get_ancestors(&self) -> Result<RArray, Error> {
        let binding = self.0.borrow();
        let ruby = Ruby::get().unwrap();
        let array = ruby.ary_new();

        binding
            .ancestors
            .iter()
            .for_each(|ancestor| match array.push(ruby.str_new(ancestor)) {
                Ok(_) => {}
                Err(err) => {
                    panic!(
                        "{:?}",
                        Error::new(ruby.exception_runtime_error(), format!("{err:?}"))
                    )
                }
            });

        Ok(array)
    }

    fn before(&self, args: &[Value]) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let element = binding.element.get_mut().unwrap();

        let (text_str, content_type) = match crate::scan_text_args(args) {
            Ok((text_str, content_type)) => (text_str, content_type),
            Err(err) => return Err(err),
        };

        element.before(&text_str, content_type);

        Ok(())
    }

    fn after(&self, args: &[Value]) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let element = binding.element.get_mut().unwrap();

        let (text_str, content_type) = match crate::scan_text_args(args) {
            Ok((text_str, content_type)) => (text_str, content_type),
            Err(err) => return Err(err),
        };

        element.after(&text_str, content_type);

        Ok(())
    }

    fn prepend(&self, args: &[Value]) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let element = binding.element.get_mut().unwrap();

        let (text_str, content_type) = match crate::scan_text_args(args) {
            Ok((text_str, content_type)) => (text_str, content_type),
            Err(err) => return Err(err),
        };

        element.prepend(&text_str, content_type);

        Ok(())
    }

    fn append(&self, args: &[Value]) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let element = binding.element.get_mut().unwrap();

        let (text_str, content_type) = match crate::scan_text_args(args) {
            Ok((text_str, content_type)) => (text_str, content_type),
            Err(err) => return Err(err),
        };

        element.append(&text_str, content_type);

        Ok(())
    }

    fn set_inner_content(&self, args: &[Value]) -> Result<(), Error> {
        let mut binding = self.0.borrow_mut();
        let element = binding.element.get_mut().unwrap();

        let (inner_content, content_type) = match crate::scan_text_args(args) {
            Ok((inner_content, content_type)) => (inner_content, content_type),
            Err(err) => return Err(err),
        };

        element.set_inner_content(&inner_content, content_type);

        Ok(())
    }

    fn remove(&self) {
        let mut binding = self.0.borrow_mut();

        if let Ok(e) = binding.element.get_mut() {
            e.remove()
        }
    }

    fn remove_and_keep_content(&self) -> Result<(), Error> {
        self.0
            .borrow_mut()
            .element
            .get_mut()
            .unwrap()
            .remove_and_keep_content();
        Ok(())
    }

    fn is_removed(&self) -> Result<bool, Error> {
        let binding = self.0.borrow();

        match binding.element.get() {
            Ok(e) => Ok(e.removed()),
            Err(_) => Err(Error::new(
                Ruby::get().unwrap().exception_runtime_error(),
                "`is_removed` is not available",
            )),
        }
    }
}

pub fn init(c_html: RClass) -> Result<(), Error> {
    let ruby = Ruby::get().unwrap();
    let c_element = c_html
        .define_class("Element", ruby.class_object())
        .expect("cannot define class Selma::HTML::Element");

    c_element.define_method("tag_name", method!(SelmaHTMLElement::tag_name, 0))?;
    c_element.define_method("tag_name=", method!(SelmaHTMLElement::set_tag_name, 1))?;
    c_element.define_method(
        "self_closing?",
        method!(SelmaHTMLElement::is_self_closing, 0),
    )?;
    c_element.define_method("[]", method!(SelmaHTMLElement::get_attribute, 1))?;
    c_element.define_method("[]=", method!(SelmaHTMLElement::set_attribute, 2))?;
    c_element.define_method(
        "remove_attribute",
        method!(SelmaHTMLElement::remove_attribute, 1),
    )?;
    c_element.define_method(
        "has_attribute?",
        method!(SelmaHTMLElement::has_attribute, 1),
    )?;
    c_element.define_method("attributes", method!(SelmaHTMLElement::get_attributes, 0))?;
    c_element.define_method(
        "attribute_source_location",
        method!(SelmaHTMLElement::get_attribute_source_location, 1),
    )?;
    c_element.define_method("ancestors", method!(SelmaHTMLElement::get_ancestors, 0))?;

    c_element.define_method("before", method!(SelmaHTMLElement::before, -1))?;
    c_element.define_method("after", method!(SelmaHTMLElement::after, -1))?;
    c_element.define_method("prepend", method!(SelmaHTMLElement::prepend, -1))?;
    c_element.define_method("append", method!(SelmaHTMLElement::append, -1))?;
    c_element.define_method(
        "set_inner_content",
        method!(SelmaHTMLElement::set_inner_content, -1),
    )?;

    c_element.define_method("remove", method!(SelmaHTMLElement::remove, 0))?;
    c_element.define_method(
        "remove_and_keep_content",
        method!(SelmaHTMLElement::remove_and_keep_content, 0),
    )?;
    c_element.define_method("removed?", method!(SelmaHTMLElement::is_removed, 0))?;

    Ok(())
}

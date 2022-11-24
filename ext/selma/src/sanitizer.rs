use std::{borrow::BorrowMut, cell::RefMut, collections::HashMap};

use html_escape::encode_unquoted_attribute;
use lol_html::html_content::{Comment, ContentType, Doctype, Element, EndTag};
use magnus::{
    class, function, method, scan_args, Error, Module, Object, RArray, RHash, RModule, Symbol,
    Value,
};

use crate::tags::{HTMLTag, Tag};

#[derive(Clone, Debug)]
struct ElementSanitizer {
    allowed_attrs: Vec<String>,
    required_attrs: Vec<String>,
    allowed_classes: Vec<String>,
    protocol_sanitizers: HashMap<String, Vec<String>>,
}

#[derive(Clone, Debug)]
pub struct Sanitizer {
    flags: [u8; HTMLTag::LAST as usize],
    allowed_attrs: Vec<String>,
    allowed_classes: Vec<String>,
    element_sanitizers: HashMap<String, ElementSanitizer>,
    name_prefix: String,
    pub allow_comments: bool,
    pub allow_doctype: bool,
    config: RHash,
}

#[derive(Clone, Debug)]
#[magnus::wrap(class = "Selma::Sanitizer")]
pub struct SelmaSanitizer(std::cell::RefCell<Sanitizer>);

#[magnus::wrap(class = "Selma::Sanitizer::ListTypes")]
enum SelmaListTypes {
    String(String),
    Symbol(Symbol),
}

impl SelmaSanitizer {
    const SELMA_SANITIZER_ALLOW: u8 = (1 << 0);
    const SELMA_SANITIZER_REMOVE_CONTENTS: u8 = (1 << 1);
    const SELMA_SANITIZER_WRAP_WHITESPACE: u8 = (1 << 2);

    pub fn new(arguments: &[Value]) -> Result<Self, Error> {
        let args = scan_args::scan_args::<(), (Option<RHash>,), (), (), (), ()>(arguments)?;
        let (opt_config,): (Option<RHash>,) = args.optional;

        let config = match opt_config {
            Some(config) => config,
            None => magnus::eval::<RHash>(r#"Selma::Sanitizer::Config::DEFAULT"#).unwrap(),
        };

        let mut element_sanitizers = HashMap::new();
        Tag::html_tags().iter().for_each(|html_tag| {
            let es = ElementSanitizer {
                allowed_attrs: vec![],
                allowed_classes: vec![],
                required_attrs: vec![],

                protocol_sanitizers: HashMap::new(),
            };
            element_sanitizers.insert(Tag::element_name_from_enum(html_tag).to_string(), es);
        });

        Ok(Self(std::cell::RefCell::new(Sanitizer {
            flags: [0; HTMLTag::LAST as usize],
            allowed_attrs: vec![],
            allowed_classes: vec![],
            element_sanitizers,
            name_prefix: "".to_string(),
            allow_comments: false,
            allow_doctype: false,
            config,
        })))
    }

    fn config(&self) -> RHash {
        self.0.borrow().config
    }

    /// Toggle a sanitizer option on or off.
    fn set_flag(&self, element: String, flag: u8, set: bool) {
        let tag = Tag::tag_from_element_name(&element);
        if set {
            self.0.borrow_mut().flags[tag.index] |= flag;
        } else {
            self.0.borrow_mut().flags[tag.index] &= !flag;
        }
    }

    /// Toggles all sanitization options on or off.
    fn set_all_flags(&self, flag: u8, set: bool) {
        if set {
            Tag::html_tags().iter().enumerate().for_each(|(iter, _)| {
                self.0.borrow_mut().flags[iter] |= flag;
            });
        } else {
            Tag::html_tags().iter().enumerate().for_each(|(iter, _)| {
                self.0.borrow_mut().flags[iter] &= flag;
            });
        }
    }

    /// Whether or not to keep HTML comments.
    fn set_allow_comments(&self, allow: bool) -> bool {
        self.0.borrow_mut().allow_comments = allow;
        allow
    }

    pub fn sanitize_comment(&self, c: &mut Comment) {
        if !self.0.borrow().allow_comments {
            c.remove();
        }
    }

    /// Whether or not to keep HTML doctype.
    fn set_allow_doctype(&self, allow: bool) -> bool {
        self.0.borrow_mut().allow_doctype = allow;
        allow
    }

    pub fn sanitize_doctype(&self, d: &mut Doctype) {
        if !self.0.borrow().allow_doctype {
            d.remove();
        }
    }

    fn set_allowed_attribute(&self, eln: Value, attr_name: String, allow: bool) -> bool {
        let mut binding = self.0.borrow_mut();

        let element_name = eln.to_r_string().unwrap().to_string().unwrap();
        if element_name == "all" {
            let allowed_attrs = &mut binding.allowed_attrs;
            Self::set_allowed(allowed_attrs, &attr_name, allow);
        } else {
            let element_sanitizer = Self::get_mut_element_sanitizer(&mut binding, &element_name);

            element_sanitizer.allowed_attrs.push(attr_name);
        }

        allow
    }

    fn set_allowed_class(&self, element_name: String, class_name: String, allow: bool) -> bool {
        let mut binding = self.0.borrow_mut();
        if element_name == "all" {
            let allowed_classes = &mut binding.allowed_classes;
            Self::set_allowed(allowed_classes, &class_name, allow);
        } else {
            let element_sanitizer = Self::get_element_sanitizer(&mut binding, &element_name);

            let mut es = element_sanitizer.clone();

            let allowed_classes = es.allowed_classes.borrow_mut();
            Self::set_allowed(allowed_classes, &class_name, allow)
        }
        allow
    }

    fn set_allowed_protocols(&self, element_name: String, attr_name: String, allow_list: RArray) {
        let mut binding = self.0.borrow_mut();

        let element_sanitizer = Self::get_element_sanitizer(&mut binding, &element_name);

        let mut es = element_sanitizer.clone();
        let protocol_sanitizers = es.protocol_sanitizers.borrow_mut();

        for opt_allowed_protocol in allow_list.each() {
            let allowed_protocol = opt_allowed_protocol.unwrap();
            if allowed_protocol.is_kind_of(class::string()) {
                protocol_sanitizers.insert(attr_name.clone(), vec![allowed_protocol.to_string()]);
            } else if allowed_protocol.is_kind_of(class::symbol())
                && allowed_protocol.inspect() == ":relative"
            {
                protocol_sanitizers
                    .insert(attr_name.clone(), vec!["#".to_string(), "/".to_string()]);
            }
        }
    }

    fn set_allowed(set: &mut Vec<String>, attr_name: &String, allow: bool) {
        if allow {
            set.push(attr_name.clone());
        } else if set.contains(attr_name) {
            set.swap_remove(set.iter().position(|x| x == attr_name).unwrap());
        }
    }

    pub fn sanitize_attributes(&self, element: &mut Element) {
        let keep_element: bool = Self::try_remove_element(self, element);

        if keep_element {
            return;
        }

        let mut binding = self.0.borrow_mut();
        let tag = Tag::tag_from_element_name(&element.tag_name().to_lowercase());
        let element_sanitizer = Self::get_element_sanitizer(&binding, &element.tag_name());

        // FIXME: This is a hack to get around the fact that we can't borrow
        let attribute_map: HashMap<String, String> = element
            .attributes()
            .iter()
            .map(|a| (a.name(), a.value()))
            .collect();

        for (attr_name, attr_val) in attribute_map.iter() {
            // you can actually embed <!-- ... --> inside
            // an HTML tag to pass malicious data. If this is
            // encountered, remove the entire element to be safe.
            if attr_name.starts_with("<!--") {
                let tag = Tag::tag_from_element_name(&element.tag_name().to_lowercase());
                let flags: u8 = self.0.borrow().flags[tag.index];

                Self::force_remove_element(self, element, tag, flags);
                return;
            }

            if !attr_val.is_empty() {
                // first, unescape any encodings and trim leading spaces
                let encoded_attribute = encode_unquoted_attribute(&attr_val);
                let unescaped = encoded_attribute.trim_start();

                // TODO: ???
                // element.set_attribute(attr_name, unescaped);

                if !Self::should_keep_attribute(
                    &binding,
                    element,
                    element_sanitizer,
                    attr_name,
                    attr_val,
                ) {
                    element.remove_attribute(attr_name);
                } else {
                    // Prevent the use of `<meta>` elements that set a charset other than UTF-8,
                    // since output is always UTF-8.
                    if Tag::is_meta(tag) {
                        if attr_name == "charset" && unescaped != "utf-8" {
                            element.set_attribute(attr_name, "utf-8");
                        }
                    } else {
                        // TODO: check if this is needed
                        // ...then, encode any special characters, for security
                        // if attr_name == "href" {
                        // hrefs have different escaping rules, apparently
                        // unescaped = encode_unquoted_attribute(unescaped);
                        // houdini_escape_href(escaped_attr_value, unescaped, strlen(unescaped));
                        // } else {
                        // houdini_escape_html(escaped_attr_value, unescaped, strlen(unescaped));
                        // }
                        // escaped = utstring_body(escaped_attr_value);

                        // element.set_attribute(attr_name, unescaped);
                    }
                }
            } else {
                // no value? remove the attribute
                element.remove_attribute(attr_name);
            }
        }

        let required = &element_sanitizer.required_attrs;
        if required.contains(&"*".to_string()) {
            return;
        }
        for attr in element.attributes().iter() {
            let attr_name = &attr.name();
            if required.contains(attr_name) {
                return;
            }
        }
    }

    fn should_keep_attribute(
        binding: &RefMut<Sanitizer>,
        element: &mut Element,
        element_sanitizer: &ElementSanitizer,
        attr_name: &String,
        attr_val: &String,
    ) -> bool {
        let mut allowed = element_sanitizer.allowed_attrs.contains(attr_name);

        if !allowed && binding.allowed_attrs.contains(attr_name) {
            allowed = true;
        }

        if !allowed {
            return false;
        }

        let protocol_sanitizer_values = element_sanitizer.protocol_sanitizers.get(attr_name);
        match protocol_sanitizer_values {
            None => {
                return false;
            }
            Some(protocol_sanitizer_values) => {
                if !Self::has_allowed_protocol(protocol_sanitizer_values, attr_val) {
                    return false;
                }
            }
        }

        if attr_name == "class"
            && !Self::sanitize_class_attribute(
                binding,
                element,
                element_sanitizer,
                attr_name,
                attr_val,
            )
        {
            return false;
        }

        true
    }

    fn has_allowed_protocol(protocols_allowed: &Vec<String>, attr_val: &String) -> bool {
        if attr_val == "/" {
            return protocols_allowed.contains(&"/".to_string());
        }

        if attr_val == "#" {
            return protocols_allowed.contains(&"#".to_string());
        }

        // Allow protocol name to be case-insensitive
        protocols_allowed.contains(&attr_val.to_lowercase())
    }

    fn sanitize_class_attribute(
        binding: &RefMut<Sanitizer>,
        element: &mut Element,
        element_sanitizer: &ElementSanitizer,
        attr_name: &String,
        attr_val: &String,
    ) -> bool {
        let allowed_global = &binding.allowed_classes;

        let mut valid_classes: Vec<String> = vec![];

        let allowed_local: Vec<String> = element_sanitizer.allowed_classes.clone();

        // No class filters, so everything goes through
        if allowed_global.is_empty() && allowed_local.is_empty() {
            return true;
        }

        let attr_value = attr_val.trim_start();
        attr_value
            .split_whitespace()
            .map(|s| s.to_string())
            .for_each(|class| {
                if allowed_global.contains(&class) || allowed_local.contains(&class) {
                    valid_classes.push(class);
                }
            });

        if valid_classes.is_empty() {
            return false;
        }

        element.set_attribute(attr_name, valid_classes.join(" ").as_str());

        true
    }

    pub fn try_remove_element(&self, element: &mut Element) -> bool {
        let tag = Tag::tag_from_element_name(&element.tag_name().to_lowercase());
        let flags: u8 = self.0.borrow().flags[tag.index];

        let should_remove: bool = (flags & Self::SELMA_SANITIZER_ALLOW) == 0;

        if should_remove {
            if Tag::has_text_content(tag) {
                Self::remove_element(element, tag, Self::SELMA_SANITIZER_REMOVE_CONTENTS);
            } else {
                Self::remove_element(element, tag, flags);
            }

            Self::check_if_end_tag_needs_removal(element);
        } else {
            // anything in <iframe> must be removed, if it's kept
            if Tag::is_iframe(tag) {
                if self.0.borrow().flags[tag.index] != 0 {
                    element.set_inner_content(" ", ContentType::Text);
                } else {
                    element.set_inner_content("", ContentType::Text);
                }
            }
        }

        should_remove
    }

    fn remove_element(element: &mut Element, tag: Tag, flags: u8) {
        let wrap_whitespace = (flags & Self::SELMA_SANITIZER_WRAP_WHITESPACE) != 0;
        let remove_contents = (flags & Self::SELMA_SANITIZER_REMOVE_CONTENTS) != 0;

        if remove_contents {
            element.remove();
        } else {
            if wrap_whitespace {
                if tag.self_closing {
                    element.after(" ", ContentType::Text);
                } else {
                    element.before(" ", ContentType::Text);
                    element.after(" ", ContentType::Text);
                }
            }
            element.remove_and_keep_content();
        }
    }

    fn force_remove_element(&self, element: &mut Element, tag: Tag, flags: u8) {
        Self::remove_element(element, tag, flags);
        Self::check_if_end_tag_needs_removal(element);
    }

    fn check_if_end_tag_needs_removal(element: &mut Element) {
        if element.removed()
            && !Tag::tag_from_element_name(&element.tag_name().to_lowercase()).self_closing
        {
            element
                .on_end_tag(move |end| {
                    Self::remove_end_tag(end);
                    Ok(())
                })
                .unwrap();
        }
    }

    fn remove_end_tag(end_tag: &mut EndTag) {
        end_tag.remove();
    }

    fn get_element_sanitizer<'a>(
        binding: &'a RefMut<Sanitizer>,
        element_name: &str,
    ) -> &'a ElementSanitizer {
        binding.element_sanitizers.get(element_name).unwrap()
    }

    fn get_mut_element_sanitizer<'a>(
        binding: &'a mut RefMut<Sanitizer>,
        element_name: &str,
    ) -> &'a mut ElementSanitizer {
        binding.element_sanitizers.get_mut(element_name).unwrap()
    }
}

pub fn init(m_selma: RModule) -> Result<(), Error> {
    let c_sanitizer = m_selma.define_class("Sanitizer", Default::default())?;

    c_sanitizer.define_singleton_method("new", function!(SelmaSanitizer::new, -1))?;
    c_sanitizer.define_method("config", method!(SelmaSanitizer::config, 0))?;

    c_sanitizer.define_method("set_flag", method!(SelmaSanitizer::set_flag, 3))?;
    c_sanitizer.define_method("set_all_flags", method!(SelmaSanitizer::set_all_flags, 2))?;

    c_sanitizer.define_method(
        "set_allow_comments",
        method!(SelmaSanitizer::set_allow_comments, 1),
    )?;
    c_sanitizer.define_method(
        "set_allow_doctype",
        method!(SelmaSanitizer::set_allow_doctype, 1),
    )?;

    c_sanitizer.define_method(
        "set_allowed_attribute",
        method!(SelmaSanitizer::set_allowed_attribute, 3),
    )?;

    c_sanitizer.define_method(
        "set_allowed_class",
        method!(SelmaSanitizer::set_allowed_class, 3),
    )?;

    c_sanitizer.define_method(
        "set_allowed_protocols",
        method!(SelmaSanitizer::set_allowed_protocols, 3),
    )?;

    Ok(())
}

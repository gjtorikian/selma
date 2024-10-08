use std::{borrow::BorrowMut, collections::HashMap};

use lol_html::{
    errors::AttributeNameError,
    html_content::{Comment, ContentType, Doctype, Element, EndTag},
};
use magnus::{
    class, eval, exception, function, method,
    r_hash::ForEach,
    scan_args,
    typed_data::Hash,
    value::{Opaque, ReprValue},
    Module, Object, RArray, RHash, RModule, RString, Ruby, Symbol, Value,
};

#[derive(Clone, Debug, Default)]
struct ElementSanitizer {
    allowed_attrs: Vec<String>,
    required_attrs: Vec<String>,
    allowed_classes: Vec<String>,
    protocol_sanitizers: HashMap<String, Vec<String>>,
}

#[derive(Clone)]
pub struct Sanitizer {
    flags: [u8; crate::tags::Tag::TAG_COUNT],
    allowed_attrs: Vec<String>,
    allowed_classes: Vec<String>,
    element_sanitizers: HashMap<String, ElementSanitizer>,

    pub escape_tagfilter: bool,
    pub allow_comments: bool,
    pub allow_doctype: bool,
    config: Opaque<RHash>,
}

#[derive(Clone)]
#[magnus::wrap(class = "Selma::Sanitizer")]
pub struct SelmaSanitizer(std::cell::RefCell<Sanitizer>);

impl SelmaSanitizer {
    const SELMA_SANITIZER_ALLOW: u8 = (1 << 0);
    // const SELMA_SANITIZER_ESCAPE_TAGFILTER: u8 = (1 << 1);
    const SELMA_SANITIZER_REMOVE_CONTENTS: u8 = (1 << 2);
    const SELMA_SANITIZER_WRAP_WHITESPACE: u8 = (1 << 3);

    pub fn new(arguments: &[Value]) -> Result<Self, magnus::Error> {
        let args = scan_args::scan_args::<(), (Option<RHash>,), (), (), (), ()>(arguments)?;
        let (opt_config,): (Option<RHash>,) = args.optional;

        let ruby = Ruby::get().unwrap();

        let config = match opt_config {
            Some(config) => config,
            // TODO: this seems like a hack to fix?
            None => magnus::eval::<RHash>(r#"Selma::Sanitizer::Config::DEFAULT"#).unwrap(),
        };

        let mut flags = [0; crate::tags::Tag::TAG_COUNT];
        let mut sanitizer_allowed_attrs = vec![];
        let sanitizer_allowed_classes = vec![];
        match Self::setup_config(&mut flags, config) {
            Ok(_) => {}
            Err(e) => {
                return Err(e);
            }
        };

        let mut element_sanitizers = HashMap::new();

        crate::tags::Tag::html_tags().iter().for_each(|html_tag| {
            let mut es_allowed_attrs = vec![];
            let element_name = crate::tags::Tag::element_name_from_enum(html_tag).to_string();

            let mut protocol_sanitizers = HashMap::new();
            // def allow_protocol(element, attr, protos)
            //  if protos.is_a?(Array)
            //    raise ArgumentError, "`:all` must be passed outside of an array" if protos.include?(:all)
            //  else
            //    protos = [protos]
            //  end
            //  set_allowed_protocols(element, attr, protos)
            // end
            match config.get(ruby.to_symbol("protocols")) {
                Some(value) => match RHash::from_value(value) {
                    None => {}
                    Some(allowed_protocols) => {
                        allowed_protocols.foreach(|element_name: String, protocols: RHash| {
                            protocols.foreach(|attribute_name: String, protocol_list: Value| {
                                let protocols: RArray;
                                if protocol_list.is_kind_of(class::array()) {
                                    protocols = RArray::from_value(protocol_list).unwrap();
                                    if protocols.includes(ruby.to_symbol("all")) {
                                        return Err(magnus::Error::new(
                                            exception::arg_error(),
                                            "`:all` must be passed outside of an array".to_string(),
                                        ));
                                    }
                                } else if protocol_list.is_kind_of(class::symbol())
                                    && Symbol::from_value(protocol_list) == eval(":all").unwrap()
                                {
                                    protocols = RArray::new();
                                    protocols.push(ruby.to_symbol("all"));
                                } else {
                                    return Err(magnus::Error::new(
                                        exception::arg_error(),
                                        "Protocol list must be an array, or just `:all`"
                                            .to_string(),
                                    ));
                                }
                                Self::set_allowed_protocols(
                                    element_name.clone(),
                                    attribute_name,
                                    &mut protocol_sanitizers,
                                    protocols,
                                );
                                Ok(ForEach::Continue)
                            });

                            Ok(ForEach::Continue)
                        });
                    }
                },
                None => {}
            };

            let element_sanitizer = ElementSanitizer {
                allowed_attrs: es_allowed_attrs,
                required_attrs: vec![],
                allowed_classes: vec![],
                protocol_sanitizers,
            };
            element_sanitizers.insert(element_name, element_sanitizer);
        });

        // def allow_attribute(element, attrs)
        //   attrs.flatten.each { |attr| set_allowed_attribute(element, attr, true) }
        // end
        match config.get(ruby.to_symbol("attributes")) {
            Some(value) => match RHash::from_value(value) {
                None => {}
                Some(allowed_attributes) => {
                    allowed_attributes.foreach(|element_value: Value, attributes: RArray| {
                        attributes.into_iter().for_each(|attr: Value| {
                            match RString::from_value(attr) {
                                None => {}
                                Some(attribute_name) => {
                                    let attr_name = attribute_name.to_string().unwrap();
                                    let element = match element_value.to_r_string() {
                                        Err(_) => "".to_string(),
                                        Ok(element_name) => element_name.to_string().unwrap(),
                                    };
                                    if element == "all" {
                                        Self::set_allowed(
                                            &mut sanitizer_allowed_attrs,
                                            &attr_name,
                                            true,
                                        );
                                    } else {
                                        let element_sanitizer = Self::get_element_sanitizer(
                                            &mut element_sanitizers,
                                            &element,
                                        );
                                        element_sanitizer.allowed_attrs.push(attr_name);
                                    }
                                }
                            }
                        });

                        Ok(ForEach::Continue)
                    });
                }
            },
            None => {}
        };

        let escape_tagfilter = match config.get(ruby.to_symbol("escape_tagfilter")) {
            Some(value) => value.to_bool(),
            None => true,
        };

        let allow_comments = match config.get(ruby.to_symbol("allow_comments")) {
            Some(value) => value.to_bool(),
            None => false,
        };

        let allow_doctype = match config.get(ruby.to_symbol("allow_doctype")) {
            Some(value) => value.to_bool(),
            None => true,
        };

        Ok(Self(std::cell::RefCell::new(Sanitizer {
            flags,
            allowed_attrs: sanitizer_allowed_attrs,
            allowed_classes: sanitizer_allowed_classes,
            element_sanitizers,

            escape_tagfilter,
            allow_comments,
            allow_doctype,
            config: config.into(),
        })))
    }

    fn setup_config(
        flags: &mut [u8; crate::tags::Tag::TAG_COUNT],
        config: RHash,
    ) -> Result<(), magnus::Error> {
        let ruby = Ruby::get().unwrap();

        // def allow_element(elements)
        //   elements.flatten.each { |e| set_flag(e, ALLOW, true) }
        // end
        match config.get(ruby.to_symbol("elements")) {
            Some(value) => match RArray::from_value(value) {
                None => {}
                Some(elements) => {
                    elements
                        .into_iter()
                        .for_each(|element| match RString::from_value(element) {
                            None => {}
                            Some(element_name) => {
                                Self::set_flag(
                                    element_name.to_string().unwrap(),
                                    flags,
                                    Self::SELMA_SANITIZER_ALLOW,
                                    true,
                                );
                            }
                        });
                }
            },
            None => {}
        };

        // def remove_contents(elements)
        //  if elements.is_a?(TrueClass) || elements.is_a?(FalseClass)
        //    set_all_flags(REMOVE_CONTENTS, elements)
        //  else
        //    elements.flatten.each { |e| set_flag(e, REMOVE_CONTENTS, true) }
        //  end
        // end
        match config.get(ruby.to_symbol("remove_contents")) {
            Some(remove_contents) => {
                if remove_contents.is_kind_of(class::true_class())
                    || remove_contents.is_kind_of(class::false_class())
                {
                    Self::set_all_flags(
                        flags,
                        Self::SELMA_SANITIZER_REMOVE_CONTENTS,
                        remove_contents.to_bool(),
                    );
                } else if remove_contents.is_kind_of(class::array()) {
                    let elements = RArray::from_value(remove_contents).unwrap();
                    elements
                        .into_iter()
                        .for_each(|element| match RString::from_value(element) {
                            None => {}
                            Some(element_name) => {
                                Self::set_flag(
                                    element_name.to_string().unwrap(),
                                    flags,
                                    Self::SELMA_SANITIZER_REMOVE_CONTENTS,
                                    true,
                                );
                            }
                        });
                } else {
                    return Err(magnus::Error::new(
                        exception::arg_error(),
                        "remove_contents must be `true`, `false`, or an array".to_string(),
                    ));
                }
            }

            None => {}
        };

        // def wrap_with_whitespace(elements)
        //  elements.flatten.each { |e| set_flag(e, WRAP_WHITESPACE, true) }
        // end
        match config.get(ruby.to_symbol("whitespace_elements")) {
            Some(value) => match RArray::from_value(value) {
                None => {}
                Some(elements) => {
                    elements
                        .into_iter()
                        .for_each(|element| match RString::from_value(element) {
                            None => {}
                            Some(element_name) => {
                                Self::set_flag(
                                    element_name.to_string().unwrap(),
                                    flags,
                                    Self::SELMA_SANITIZER_WRAP_WHITESPACE,
                                    true,
                                );
                            }
                        });
                }
            },
            None => {}
        };

        Ok(())
    }

    fn get_config(&self) -> Result<RHash, magnus::Error> {
        let binding = self.0.borrow();
        let ruby = Ruby::get().unwrap();

        Ok(ruby.get_inner(binding.config))
    }

    /// Toggle a sanitizer option on or off.
    fn set_flag(
        tag_name: String,
        flags: &mut [u8; crate::tags::Tag::TAG_COUNT],
        flag: u8,
        set: bool,
    ) {
        let tag = crate::tags::Tag::tag_from_tag_name(tag_name.as_str());
        if set {
            flags[tag.index] |= flag;
        } else {
            flags[tag.index] &= !flag;
        }
    }

    /// Toggles all sanitization options on or off.
    fn set_all_flags(flags: &mut [u8; crate::tags::Tag::TAG_COUNT], flag: u8, set: bool) {
        if set {
            crate::tags::Tag::html_tags()
                .iter()
                .enumerate()
                .for_each(|(iter, _)| {
                    flags[iter] |= flag;
                });
        } else {
            crate::tags::Tag::html_tags()
                .iter()
                .enumerate()
                .for_each(|(iter, _)| {
                    flags[iter] &= flag;
                });
        }
    }

    /// Whether or not to keep dangerous HTML tags.
    fn set_escape_tagfilter(&self, allow: bool) -> bool {
        self.0.borrow_mut().escape_tagfilter = allow;
        allow
    }

    pub fn escape_tagfilter(&self, e: &mut Element) -> bool {
        if self.0.borrow().escape_tagfilter {
            let tag = crate::tags::Tag::tag_from_element(e);
            if crate::tags::Tag::is_tag_escapeworthy(tag) {
                e.remove();
                return true;
            }
        }

        false
    }

    pub fn get_escape_tagfilter(&self) -> bool {
        self.0.borrow().escape_tagfilter
    }

    /// Whether or not to keep HTML comments.
    fn set_allow_comments(&self, allow: bool) -> bool {
        self.0.borrow_mut().allow_comments = allow;
        allow
    }

    pub fn get_allow_comments(&self) -> bool {
        self.0.borrow().allow_comments
    }

    pub fn remove_comment(&self, c: &mut Comment) {
        c.remove();
    }

    /// Whether or not to keep HTML doctype.
    fn set_allow_doctype(&self, allow: bool) -> bool {
        self.0.borrow_mut().allow_doctype = allow;
        allow
    }

    /// Whether or not to keep HTML doctype.
    pub fn get_allow_doctype(&self) -> bool {
        self.0.borrow().allow_doctype
    }

    pub fn remove_doctype(&self, d: &mut Doctype) {
        d.remove();
    }

    fn set_allowed_protocols(
        element_name: String,
        attr_name: String,
        protocol_sanitizers: &mut HashMap<String, Vec<String>>,
        allow_list: RArray,
    ) {
        for allowed_protocol in allow_list.into_iter() {
            let protocol_list = protocol_sanitizers.get_mut(&attr_name);
            if allowed_protocol.is_kind_of(class::string()) {
                match protocol_list {
                    None => {
                        protocol_sanitizers
                            .insert(attr_name.to_string(), vec![allowed_protocol.to_string()]);
                    }
                    Some(protocol_list) => protocol_list.push(allowed_protocol.to_string()),
                }
            } else if allowed_protocol.is_kind_of(class::symbol()) {
                let protocol_config = allowed_protocol.inspect();
                if protocol_config == ":relative" {
                    match protocol_list {
                        None => {
                            protocol_sanitizers.insert(
                                attr_name.to_string(),
                                vec!["#".to_string(), "/".to_string()],
                            );
                        }
                        Some(protocol_list) => {
                            protocol_list.push("#".to_string());
                            protocol_list.push("/".to_string());
                        }
                    }
                } else if protocol_config == ":all" {
                    protocol_sanitizers.insert(attr_name.to_string(), vec!["all".to_string()]);
                }
            }
        }
    }

    fn set_allowed(set: &mut Vec<String>, attr_name: &String, allow: bool) {
        if allow {
            set.push(attr_name.to_string());
        } else if set.contains(attr_name) {
            set.swap_remove(set.iter().position(|x| x == attr_name).unwrap());
        }
    }

    pub fn sanitize_attributes(&self, element: &mut Element) -> Result<(), AttributeNameError> {
        let tag = crate::tags::Tag::tag_from_element(element);
        let tag_name = &element.tag_name();
        let element_sanitizer = {
            let mut binding = self.0.borrow_mut();
            let element_sanitizers = &mut binding.element_sanitizers;
            Self::get_element_sanitizer(element_sanitizers, tag_name).clone()
        };

        let binding = self.0.borrow();

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
                Self::force_remove_element(self, element);
                return Ok(());
            }

            // first, trim leading spaces and unescape any encodings
            let trimmed = attr_val.trim_start();
            let x = escapist::unescape_html(trimmed.as_bytes());
            let unescaped_attr_val = String::from_utf8_lossy(&x).to_string();

            let should_keep_attrubute = match Self::should_keep_attribute(
                &binding,
                element,
                &element_sanitizer,
                attr_name,
                &unescaped_attr_val,
            ) {
                Ok(should_keep) => should_keep,
                Err(e) => {
                    return Err(e);
                }
            };

            if !should_keep_attrubute {
                element.remove_attribute(attr_name);
            } else {
                // Prevent the use of `<meta>` elements that set a charset other than UTF-8,
                // since output is always UTF-8.
                if crate::tags::Tag::is_meta(tag) {
                    if attr_name == "charset" && unescaped_attr_val != "utf-8" {
                        match element.set_attribute(attr_name, "utf-8") {
                            Ok(_) => {}
                            Err(err) => {
                                return Err(err);
                            }
                        }
                    }
                } else if !unescaped_attr_val.is_empty() {
                    let mut buf = String::new();
                    // ...then, escape any special characters, for security
                    if attr_name == "href" {
                        escapist::escape_href(&mut buf, unescaped_attr_val.as_str()).unwrap();
                    } else {
                        escapist::escape_html(&mut buf, unescaped_attr_val.as_str()).unwrap();
                    };

                    match element.set_attribute(attr_name, &buf) {
                        Ok(_) => {}
                        Err(err) => {
                            return Err(err);
                        }
                    }
                }
            }
        }

        let required = &element_sanitizer.required_attrs;
        if required.contains(&"*".to_string()) {
            return Ok(());
        }
        for attr in element.attributes().iter() {
            let attr_name = &attr.name();
            if required.contains(attr_name) {
                return Ok(());
            }
        }

        Ok(())
    }

    fn should_keep_attribute(
        binding: &Sanitizer,
        element: &mut Element,
        element_sanitizer: &ElementSanitizer,
        attr_name: &String,
        attr_val: &str,
    ) -> Result<bool, AttributeNameError> {
        let mut allowed: bool = false;
        let element_allowed_attrs = element_sanitizer.allowed_attrs.contains(attr_name);
        let sanitizer_allowed_attrs = binding.allowed_attrs.contains(attr_name);

        if element_allowed_attrs {
            allowed = true;
        }

        if !allowed && sanitizer_allowed_attrs {
            allowed = true;
        }

        if !allowed {
            return Ok(false);
        }

        let protocol_sanitizer_values = element_sanitizer.protocol_sanitizers.get(attr_name);
        match protocol_sanitizer_values {
            None => {
                // has a protocol, but no sanitization list
                if !attr_val.is_empty() && Self::has_protocol(attr_val) {
                    return Ok(false);
                }
            }
            Some(protocol_sanitizer_values) => {
                if !attr_val.is_empty()
                    && !Self::has_allowed_protocol(protocol_sanitizer_values, attr_val)
                {
                    return Ok(false);
                }
            }
        }

        if attr_name == "class" {
            return Self::sanitize_class_attribute(
                binding,
                element,
                element_sanitizer,
                attr_name,
                attr_val,
            );
        }

        Ok(true)
    }

    fn has_protocol(attr_val: &str) -> bool {
        attr_val.contains("://")
    }

    fn has_allowed_protocol(protocols_allowed: &[String], attr_val: &str) -> bool {
        if protocols_allowed.contains(&"all".to_string()) {
            return true;
        }

        // FIXME: is there a more idiomatic way to do this?
        let mut pos: usize = 0;
        let mut chars = attr_val.chars();
        let len = attr_val.len();

        for (i, c) in attr_val.chars().enumerate() {
            if c != ':' && c != '/' && c != '#' && pos + 1 < len {
                pos = i + 1;
            } else {
                break;
            }
        }

        let char = chars.nth(pos).unwrap();

        if char == '/' {
            return protocols_allowed.contains(&"/".to_string());
        }

        if char == '#' {
            return protocols_allowed.contains(&"#".to_string());
        }

        // Allow protocol name to be case-insensitive
        let protocol = attr_val[0..pos].to_lowercase();

        protocols_allowed.contains(&protocol.to_lowercase())
    }

    fn sanitize_class_attribute(
        binding: &Sanitizer,
        element: &mut Element,
        element_sanitizer: &ElementSanitizer,
        attr_name: &str,
        attr_val: &str,
    ) -> Result<bool, lol_html::errors::AttributeNameError> {
        let allowed_global = &binding.allowed_classes;

        let mut valid_classes: Vec<String> = vec![];

        let allowed_local = &element_sanitizer.allowed_classes;

        // No class filters, so everything goes through
        if allowed_global.is_empty() && allowed_local.is_empty() {
            return Ok(true);
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
            return Ok(false);
        }

        match element.set_attribute(attr_name, valid_classes.join(" ").as_str()) {
            Ok(_) => Ok(true),
            Err(err) => Err(err),
        }
    }

    pub fn allow_element(&self, element: &mut Element) -> bool {
        let tag = crate::tags::Tag::tag_from_element(element);
        let flags: u8 = self.0.borrow().flags[tag.index];

        (flags & Self::SELMA_SANITIZER_ALLOW) == 0
    }

    pub fn try_remove_element(&self, element: &mut Element) -> bool {
        let tag = crate::tags::Tag::tag_from_element(element);
        let flags: u8 = self.0.borrow().flags[tag.index];

        let should_remove = !element.removed() && self.allow_element(element);

        if should_remove {
            if crate::tags::Tag::has_text_content(tag) {
                Self::remove_element(
                    element,
                    tag.self_closing,
                    Self::SELMA_SANITIZER_REMOVE_CONTENTS,
                );
            } else {
                Self::remove_element(element, tag.self_closing, flags);
            }

            Self::check_if_end_tag_needs_removal(element);
        } else {
            // anything in <iframe> must be removed, if it's kept
            if crate::tags::Tag::is_iframe(tag) {
                if self.0.borrow().flags[tag.index] != 0 {
                    element.set_inner_content(" ", ContentType::Text);
                } else {
                    element.set_inner_content("", ContentType::Text);
                }
            }
        }

        should_remove
    }

    fn remove_element(element: &mut Element, self_closing: bool, flags: u8) {
        let wrap_whitespace = (flags & Self::SELMA_SANITIZER_WRAP_WHITESPACE) != 0;
        let remove_contents = (flags & Self::SELMA_SANITIZER_REMOVE_CONTENTS) != 0;

        if remove_contents {
            element.remove();
        } else {
            if wrap_whitespace {
                if self_closing {
                    element.after(" ", ContentType::Text);
                } else {
                    element.before(" ", ContentType::Text);
                    element.after(" ", ContentType::Text);
                }
            }

            element.remove_and_keep_content();
        }
    }

    pub fn force_remove_element(&self, element: &mut Element) {
        let tag = crate::tags::Tag::tag_from_element(element);
        let self_closing = tag.self_closing;
        Self::remove_element(element, self_closing, Self::SELMA_SANITIZER_REMOVE_CONTENTS);
        Self::check_if_end_tag_needs_removal(element);
    }

    fn check_if_end_tag_needs_removal(element: &mut Element) {
        if element.removed() && !crate::tags::Tag::tag_from_element(element).self_closing {
            element
                .end_tag_handlers()
                .unwrap()
                .push(Box::new(move |end| {
                    Self::remove_end_tag(end);
                    Ok(())
                }));
        }
    }

    fn remove_end_tag(end_tag: &mut EndTag) {
        end_tag.remove();
    }

    fn get_element_sanitizer<'a>(
        element_sanitizers: &'a mut HashMap<String, ElementSanitizer>,
        element_name: &str,
    ) -> &'a mut ElementSanitizer {
        element_sanitizers
            .entry(element_name.to_string())
            .or_default()
    }
}

pub fn init(m_selma: RModule) -> Result<(), magnus::Error> {
    let c_sanitizer = m_selma
        .define_class("Sanitizer", magnus::class::object())
        .expect("cannot define class Selma::Sanitizer");

    c_sanitizer.define_singleton_method("new", function!(SelmaSanitizer::new, -1))?;
    c_sanitizer.define_method("config", method!(SelmaSanitizer::get_config, 0))?;

    Ok(())
}

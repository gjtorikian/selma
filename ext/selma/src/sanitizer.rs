use std::{borrow::Cow, collections::HashMap, sync::OnceLock};

use lol_html::{
    errors::AttributeNameError,
    html_content::{Comment, ContentType, Doctype, Element, EndTag, TextChunk},
};
use magnus::{
    eval, function, method,
    r_hash::ForEach,
    scan_args,
    value::{Opaque, ReprValue},
    Module, Object, RArray, RHash, RModule, RString, Ruby, Symbol, Value,
};

#[derive(Clone, Debug, Default)]
struct ElementSanitizer {
    allowed_attrs: Vec<String>,
    allowed_classes: Vec<String>,
    protocol_sanitizers: HashMap<String, Vec<String>>,
}

impl ElementSanitizer {
    /// Shared stand-in for elements the config never mentions, so lookups at rewrite
    /// time never insert anything and the config stays immutable once built.
    fn empty() -> &'static ElementSanitizer {
        static EMPTY: OnceLock<ElementSanitizer> = OnceLock::new();
        EMPTY.get_or_init(ElementSanitizer::default)
    }
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

/// The config is fully built in `new` and never changes afterwards, so there is no
/// interior mutability here: every rewrite-time method only reads.
#[derive(Clone)]
#[magnus::wrap(class = "Selma::Sanitizer")]
pub struct SelmaSanitizer(Sanitizer);

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

        // only elements the config actually mentions get an entry; everything else
        // resolves to `ElementSanitizer::empty()` at rewrite time
        let mut element_sanitizers = HashMap::new();

        // def allow_attribute(element, attrs)
        //   attrs.flatten.each { |attr| set_allowed_attribute(element, attr, true) }
        // end
        if let Some(value) = config.get(ruby.to_symbol("attributes")) {
            if let Some(allowed_attributes) = RHash::from_value(value) {
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
                })?;
            }
        };

        // def allow_protocol(element, attr, protos)
        //  if protos.is_a?(Array)
        //    raise ArgumentError, "`:all` must be passed outside of an array" if protos.include?(:all)
        //  else
        //    protos = [protos]
        //  end
        //  set_allowed_protocols(element, attr, protos)
        // end
        if let Some(value) = config.get(ruby.to_symbol("protocols")) {
            if let Some(allowed_protocols) = RHash::from_value(value) {
                allowed_protocols.foreach(|element_name: String, protocols: RHash| {
                    protocols.foreach(|attribute_name: String, protocol_list: Value| {
                        let protocols: RArray;
                        if protocol_list.is_kind_of(ruby.class_array()) {
                            protocols = RArray::from_value(protocol_list).unwrap();
                            if protocols.includes(ruby.to_symbol("all")) {
                                return Err(magnus::Error::new(
                                    ruby.exception_arg_error(),
                                    "`:all` must be passed outside of an array".to_string(),
                                ));
                            }
                        } else if protocol_list.is_kind_of(ruby.class_symbol())
                            && Symbol::from_value(protocol_list) == eval(":all").unwrap()
                        {
                            protocols = ruby.ary_new();
                            protocols.push(ruby.to_symbol("all"))?;
                        } else {
                            return Err(magnus::Error::new(
                                ruby.exception_arg_error(),
                                "Protocol list must be an array, or just `:all`".to_string(),
                            ));
                        }

                        let element_sanitizer =
                            Self::get_element_sanitizer(&mut element_sanitizers, &element_name);

                        Self::set_allowed_protocols(element_sanitizer, attribute_name, protocols);
                        Ok(ForEach::Continue)
                    })?;

                    Ok(ForEach::Continue)
                })?;
            }
        }

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

        Ok(Self(Sanitizer {
            flags,
            allowed_attrs: sanitizer_allowed_attrs,
            allowed_classes: sanitizer_allowed_classes,
            element_sanitizers,

            escape_tagfilter,
            allow_comments,
            allow_doctype,
            config: config.into(),
        }))
    }

    fn setup_config(
        flags: &mut [u8; crate::tags::Tag::TAG_COUNT],
        config: RHash,
    ) -> Result<(), magnus::Error> {
        let ruby = Ruby::get().unwrap();

        // def allow_element(elements)
        //   elements.flatten.each { |e| set_flag(e, ALLOW, true) }
        // end
        if let Some(value) = config.get(ruby.to_symbol("elements")) {
            if let Some(elements) = RArray::from_value(value) {
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
        }

        // def remove_contents(elements)
        //  if elements.is_a?(TrueClass) || elements.is_a?(FalseClass)
        //    set_all_flags(REMOVE_CONTENTS, elements)
        //  else
        //    elements.flatten.each { |e| set_flag(e, REMOVE_CONTENTS, true) }
        //  end
        // end
        if let Some(remove_contents) = config.get(ruby.to_symbol("remove_contents")) {
            if remove_contents.is_kind_of(ruby.class_true_class())
                || remove_contents.is_kind_of(ruby.class_false_class())
            {
                Self::set_all_flags(
                    flags,
                    Self::SELMA_SANITIZER_REMOVE_CONTENTS,
                    remove_contents.to_bool(),
                );
            } else if remove_contents.is_kind_of(ruby.class_array()) {
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
                    ruby.exception_arg_error(),
                    "remove_contents must be `true`, `false`, or an array".to_string(),
                ));
            }
        }

        // def wrap_with_whitespace(elements)
        //  elements.flatten.each { |e| set_flag(e, WRAP_WHITESPACE, true) }
        // end
        if let Some(value) = config.get(ruby.to_symbol("whitespace_elements")) {
            if let Some(elements) = RArray::from_value(value) {
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
        };

        Ok(())
    }

    fn get_config(&self) -> Result<RHash, magnus::Error> {
        let ruby = Ruby::get().unwrap();

        Ok(ruby.get_inner(self.0.config))
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

    pub fn escape_tagfilter(&self, e: &mut Element) -> bool {
        if self.0.escape_tagfilter {
            let tag = crate::tags::Tag::tag_from_element(e);
            if crate::tags::Tag::is_tag_escapeworthy(tag) {
                e.remove();
                return true;
            }
        }

        false
    }

    pub fn get_escape_tagfilter(&self) -> bool {
        self.0.escape_tagfilter
    }

    pub fn get_allow_comments(&self) -> bool {
        self.0.allow_comments
    }

    /// A `<` that the tokenizer classified as text (because the character after it
    /// cannot start a tag, e.g. `<<b>` or `< b`) is otherwise passed through verbatim.
    /// If the sanitizer then removes the node that follows it, the text on either side
    /// joins up and re-tokenizes as markup.
    /// Escaping `<` in every context that decodes entities keeps
    /// text as text regardless of what gets removed around it. Raw-text contexts
    /// (`<script>`, `<style>`, ...) are skipped: entities are not decoded there, so
    /// escaping would corrupt the content rather than protect it.
    pub fn escape_text_chunk(text_chunk: &mut TextChunk) {
        if !text_chunk.text_type().allows_html_entities() {
            return;
        }

        if text_chunk.as_str().contains('<') {
            let escaped = text_chunk.as_str().replace('<', "&lt;");
            text_chunk.set_str(escaped);
        }
    }

    pub fn remove_comment(&self, c: &mut Comment) {
        c.remove();
    }

    /// Whether or not to keep HTML doctype.
    pub fn get_allow_doctype(&self) -> bool {
        self.0.allow_doctype
    }

    pub fn remove_doctype(&self, d: &mut Doctype) {
        d.remove();
    }

    fn set_allowed_protocols(
        element_sanitizer: &mut ElementSanitizer,
        attr_name: String,
        allow_list: RArray,
    ) {
        let ruby = Ruby::get().unwrap();
        let protocol_sanitizers = &mut element_sanitizer.protocol_sanitizers;

        for allowed_protocol in allow_list.into_iter() {
            let protocol_list = protocol_sanitizers.get_mut(&attr_name);
            if allowed_protocol.is_kind_of(ruby.class_string()) {
                match protocol_list {
                    None => {
                        protocol_sanitizers
                            .insert(attr_name.to_string(), vec![allowed_protocol.to_string()]);
                    }
                    Some(protocol_list) => protocol_list.push(allowed_protocol.to_string()),
                }
            } else if allowed_protocol.is_kind_of(ruby.class_symbol()) {
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

    /// Everything the sanitizer does to one element, with a single tag lookup: remove it
    /// (and, depending on the config, its contents) when it is not allowed, otherwise
    /// filter and re-escape its attributes.
    pub fn sanitize_element(&self, element: &mut Element) -> Result<(), AttributeNameError> {
        // `tag_name()` allocates, so take it once and derive everything else from it
        let name = element.tag_name();
        let tag = crate::tags::Tag::tag_from_tag_name(&name);

        self.try_remove_element(element, tag);
        if element.removed() {
            // nothing left to sanitize
            return Ok(());
        }

        self.sanitize_attributes(element, tag, &name)
    }

    fn sanitize_attributes(
        &self,
        element: &mut Element,
        tag: crate::tags::Tag,
        tag_name: &str,
    ) -> Result<(), AttributeNameError> {
        let sanitizer = &self.0;
        let element_sanitizer = sanitizer
            .element_sanitizers
            .get(tag_name)
            .unwrap_or_else(|| ElementSanitizer::empty());

        // the attribute list cannot be iterated while the element is being mutated, so
        // take a snapshot. Every occurrence of a duplicated name is evaluated in order;
        // a rejected occurrence removes the attribute outright.
        let attributes: Vec<(String, String)> = element
            .attributes()
            .iter()
            .map(|a| (a.name(), a.value()))
            .collect();

        for (attr_name, attr_val) in &attributes {
            // you can actually embed <!-- ... --> inside
            // an HTML tag to pass malicious data. If this is
            // encountered, remove the entire element to be safe.
            if attr_name.starts_with("<!--") {
                Self::force_remove_element(element, tag);
                return Ok(());
            }

            // first, trim leading spaces and unescape any encodings (an entity always
            // starts with `&`, so a value without one is already unescaped)
            let trimmed = attr_val.trim_start();
            let unescaped_attr_val: Cow<str> = if trimmed.contains('&') {
                let bytes = escapist::unescape_html(trimmed.as_bytes());
                Cow::Owned(
                    String::from_utf8(bytes)
                        .unwrap_or_else(|err| String::from_utf8_lossy(err.as_bytes()).into_owned()),
                )
            } else {
                Cow::Borrowed(trimmed)
            };

            let keep = Self::should_keep_attribute(
                sanitizer,
                element,
                element_sanitizer,
                attr_name,
                &unescaped_attr_val,
            )?;

            if !keep {
                element.remove_attribute(attr_name);
                continue;
            }

            // Prevent the use of `<meta>` elements that set a charset other than UTF-8,
            // since output is always UTF-8.
            if crate::tags::Tag::is_meta(tag) {
                if attr_name == "charset" && unescaped_attr_val != "utf-8" {
                    element.set_attribute(attr_name, "utf-8")?;
                }
            } else if !unescaped_attr_val.is_empty() {
                // ...then, escape any special characters, for security
                let mut buf = String::with_capacity(unescaped_attr_val.len());
                if attr_name == "href" {
                    escapist::escape_href(&mut buf, &unescaped_attr_val).unwrap();
                } else {
                    escapist::escape_html(&mut buf, &unescaped_attr_val).unwrap();
                };

                element.set_attribute(attr_name, &buf)?;
            }
        }

        Ok(())
    }

    fn should_keep_attribute(
        binding: &Sanitizer,
        element: &mut Element,
        element_sanitizer: &ElementSanitizer,
        attr_name: &str,
        attr_val: &str,
    ) -> Result<bool, AttributeNameError> {
        let mut allowed: bool = false;
        let element_allowed_attrs = element_sanitizer
            .allowed_attrs
            .iter()
            .any(|a| a == attr_name);
        let sanitizer_allowed_attrs = binding.allowed_attrs.iter().any(|a| a == attr_name);

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
        if protocols_allowed.iter().any(|p| p == "all") {
            return true;
        }

        // The protocol is everything before the first `:`; a `/` or `#` before
        // that means there is no protocol and the URL is relative.
        let Some(idx) = attr_val.find([':', '/', '#']) else {
            return false;
        };

        match attr_val.as_bytes()[idx] {
            b'/' => protocols_allowed.iter().any(|p| p == "/"),
            b'#' => protocols_allowed.iter().any(|p| p == "#"),
            // Allow protocol name to be case-insensitive (the config side is taken as-is)
            _ => {
                let protocol = &attr_val.as_bytes()[..idx];
                protocols_allowed.iter().any(|p| {
                    p.len() == protocol.len()
                        && p.bytes()
                            .zip(protocol)
                            .all(|(allowed, given)| allowed == given.to_ascii_lowercase())
                })
            }
        }
    }

    fn sanitize_class_attribute(
        binding: &Sanitizer,
        element: &mut Element,
        element_sanitizer: &ElementSanitizer,
        attr_name: &str,
        attr_val: &str,
    ) -> Result<bool, lol_html::errors::AttributeNameError> {
        let allowed_global = &binding.allowed_classes;

        let allowed_local = &element_sanitizer.allowed_classes;

        // No class filters, so everything goes through
        if allowed_global.is_empty() && allowed_local.is_empty() {
            return Ok(true);
        }

        let valid_classes: Vec<&str> = attr_val
            .split_whitespace()
            .filter(|class| {
                allowed_global.iter().any(|a| a == class)
                    || allowed_local.iter().any(|a| a == class)
            })
            .collect();

        if valid_classes.is_empty() {
            return Ok(false);
        }

        match element.set_attribute(attr_name, valid_classes.join(" ").as_str()) {
            Ok(_) => Ok(true),
            Err(err) => Err(err),
        }
    }

    fn is_disallowed(&self, tag: crate::tags::Tag) -> bool {
        (self.0.flags[tag.index] & Self::SELMA_SANITIZER_ALLOW) == 0
    }

    /// The final pass only needs to know whether a (possibly handler-inserted or fused)
    /// element from the tagfilter list is allowed, and remove it outright if not.
    pub fn remove_if_disallowed(&self, element: &mut Element) {
        let tag = crate::tags::Tag::tag_from_element(element);
        if self.is_disallowed(tag) {
            Self::force_remove_element(element, tag);
        }
    }

    fn try_remove_element(&self, element: &mut Element, tag: crate::tags::Tag) -> bool {
        let flags: u8 = self.0.flags[tag.index];

        let should_remove = !element.removed() && self.is_disallowed(tag);

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

            Self::check_if_end_tag_needs_removal(element, tag);
        } else {
            // anything in <iframe> must be removed, if it's kept
            if crate::tags::Tag::is_iframe(tag) {
                if flags != 0 {
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

    fn force_remove_element(element: &mut Element, tag: crate::tags::Tag) {
        Self::remove_element(
            element,
            tag.self_closing,
            Self::SELMA_SANITIZER_REMOVE_CONTENTS,
        );
        Self::check_if_end_tag_needs_removal(element, tag);
    }

    fn check_if_end_tag_needs_removal(element: &mut Element, tag: crate::tags::Tag) {
        if element.removed() && !tag.self_closing {
            // ignore void elements (lol_html's void list may differ from selma's `self_closing`)
            let _ = element.on_end_tag(Box::new(move |end| {
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
    let ruby = Ruby::get().unwrap();
    let c_sanitizer = m_selma
        .define_class("Sanitizer", ruby.class_object())
        .expect("cannot define class Selma::Sanitizer");

    c_sanitizer.define_singleton_method("new", function!(SelmaSanitizer::new, -1))?;
    c_sanitizer.define_method("config", method!(SelmaSanitizer::get_config, 0))?;

    Ok(())
}

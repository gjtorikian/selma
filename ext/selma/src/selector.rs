use magnus::{function, scan_args, Error, Module, Object, RModule, Ruby, Value};

#[derive(Clone, Debug)]
#[magnus::wrap(class = "Selma::Selector")]
pub struct SelmaSelector {
    // parsed once here, so `Rewriter#rewrite` does not re-parse the CSS on every call
    element_selector: Option<lol_html::Selector>,
    text_selector: Option<lol_html::Selector>,
    ignore_text_within: Option<Vec<String>>,
}

type SelectorMatches = (Option<String>, Option<String>, Option<Vec<String>>);

impl SelmaSelector {
    fn new(args: &[Value]) -> Result<Self, Error> {
        let (match_element, match_text_within, rb_ignore_text_within) =
            Self::scan_parse_args(args)?;
        let ruby = Ruby::get().unwrap();

        if match_element.is_none() && match_text_within.is_none() {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "Neither `match_element` nor `match_text_within` option given",
            ));
        }

        let element_selector = match &match_element {
            None => None,
            Some(css) => match css.parse::<lol_html::Selector>() {
                Ok(selector) => Some(selector),
                Err(_) => {
                    return Err(Error::new(
                        ruby.exception_arg_error(),
                        format!("Could not parse `match_element` (`{css:?}`) as valid CSS"),
                    ));
                }
            },
        };

        let text_selector = match &match_text_within {
            None => None,
            Some(css) => match css.parse::<lol_html::Selector>() {
                Ok(selector) => Some(selector),
                Err(_) => {
                    return Err(Error::new(
                        ruby.exception_arg_error(),
                        format!("Could not parse `match_text_within` (`{css:?}`) as valid CSS"),
                    ));
                }
            },
        };

        let ignore_text_within = match rb_ignore_text_within {
            None => None,
            Some(rb_ignore_text_within) => {
                let mut ignore_text_within = vec![];
                rb_ignore_text_within.iter().for_each(|i| {
                    // TODO: test this against malice
                    let ignore_text_within_tag_name = i.to_string();
                    ignore_text_within.push(ignore_text_within_tag_name);
                });
                Some(ignore_text_within)
            }
        };

        Ok(Self {
            element_selector,
            text_selector,
            ignore_text_within,
        })
    }

    #[allow(clippy::let_unit_value)]
    fn scan_parse_args(args: &[Value]) -> Result<SelectorMatches, Error> {
        let args = scan_args::scan_args(args)?;
        let _: () = args.required;
        let _: () = args.optional;
        let _: () = args.splat;
        let _: () = args.trailing;
        let _: () = args.block;

        let kw = scan_args::get_kwargs::<
            _,
            (),
            (Option<String>, Option<String>, Option<Vec<String>>),
            (),
        >(
            args.keywords,
            &[],
            &["match_element", "match_text_within", "ignore_text_within"],
        )?;
        let (match_element, match_text_within, rb_ignore_text_within) = kw.optional;

        Ok((match_element, match_text_within, rb_ignore_text_within))
    }

    pub fn element_selector(&self) -> Option<&lol_html::Selector> {
        self.element_selector.as_ref()
    }

    pub fn text_selector(&self) -> Option<&lol_html::Selector> {
        self.text_selector.as_ref()
    }

    pub fn ignore_text_within(&self) -> Option<&[String]> {
        self.ignore_text_within.as_deref()
    }
}

pub fn init(m_selma: RModule) -> Result<(), Error> {
    let ruby = Ruby::get().unwrap();
    let c_selector = m_selma
        .define_class("Selector", ruby.class_object())
        .expect("cannot define class Selma::Selector");

    c_selector.define_singleton_method("new", function!(SelmaSelector::new, -1))?;

    Ok(())
}

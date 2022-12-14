use magnus::{exception, function, scan_args, Error, Module, Object, RModule, Value};

#[derive(Clone, Debug)]
#[magnus::wrap(class = "Selma::Selector")]
pub struct SelmaSelector {
    match_element: Option<String>,
    match_text_within: Option<String>,
    ignore_text_within: Option<Vec<String>>,
}

impl SelmaSelector {
    fn new(args: &[Value]) -> Result<Self, Error> {
        let (match_element, match_text_within, rb_ignore_text_within) =
            Self::scan_parse_args(args)?;

        if match_element.is_none() && match_text_within.is_none() {
            return Err(Error::new(
                exception::arg_error(),
                "Neither `match_element` nor `match_text_within` option given",
            ));
        }

        // FIXME: not excited about this double parse work (`element!` does it too),
        // but at least we can bail ASAP if the CSS is invalid
        if match_element.is_some() {
            let css = match_element.as_ref().unwrap();
            if css.parse::<lol_html::Selector>().is_err() {
                return Err(Error::new(
                    exception::arg_error(),
                    format!("Could not parse `match_element` (`{}`) as valid CSS", css),
                ));
            }
        }

        if match_text_within.is_some() {
            let css = match_text_within.as_ref().unwrap();
            if css.parse::<lol_html::Selector>().is_err() {
                return Err(Error::new(
                    exception::arg_error(),
                    format!(
                        "Could not parse `match_text_within` (`{}`) as valid CSS",
                        css
                    ),
                ));
            }
        }

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
            match_element,
            match_text_within,
            ignore_text_within,
        })
    }

    #[allow(clippy::let_unit_value)]
    fn scan_parse_args(
        args: &[Value],
    ) -> Result<(Option<String>, Option<String>, Option<Vec<String>>), Error> {
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

    pub fn match_element(&self) -> Option<String> {
        self.match_element.clone()
    }

    pub fn match_text_within(&self) -> Option<String> {
        self.match_text_within.clone()
    }

    pub fn ignore_text_within(&self) -> Option<Vec<String>> {
        self.ignore_text_within.clone()
    }
}

pub fn init(m_selma: RModule) -> Result<(), Error> {
    let c_selector = m_selma
        .define_class("Selector", Default::default())
        .expect("cannot define class Selma::Selector");

    c_selector.define_singleton_method("new", function!(SelmaSelector::new, -1))?;

    Ok(())
}

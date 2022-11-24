use magnus::{
    exception, function, scan_args, DataTypeFunctions, Error, Module, Object, RArray, RHash,
    RModule, Symbol, TypedData, Value,
};

#[derive(Clone, Debug)]
#[magnus::wrap(class = "Selma::Selector")]
pub struct SelmaSelector {
    match_element: Option<String>,
    match_text_within: Option<String>,
    ignore_text_within: Vec<String>,
}

impl SelmaSelector {
    fn new(arguments: &[Value]) -> Result<Self, Error> {
        let args = scan_args::scan_args::<(), (), (), (), _, ()>(arguments)?;
        let kw =
            scan_args::get_kwargs::<_, (), (Option<String>, Option<String>, Option<RArray>), ()>(
                args.keywords,
                &[],
                &["match_element", "match_text_within", "ignore_text_within"],
            )?;

        let (match_element, match_text_within, rb_ignore_text_within) = kw.optional;

        if match_element.is_none() && match_text_within.is_none() {
            return Err(Error::new(
                exception::type_error(),
                "Neither `match_element` nor `match_text_within` option given",
            ));
        }

        let mut ignore_text_within: Vec<String> = vec![];
        if let Some(rb_ignore_text_within) = rb_ignore_text_within {
            for i in rb_ignore_text_within.each() {
                // TODO: test this against malice
                let ignore_text_within_tag_name = i.unwrap().to_string();
                ignore_text_within.push(ignore_text_within_tag_name);
            }
        }

        Ok(Self {
            match_element,
            match_text_within,
            ignore_text_within,
        })
    }

    pub fn match_element(&self) -> Option<String> {
        self.match_element.clone()
    }

    pub fn match_text_within(&self) -> Option<String> {
        self.match_text_within.clone()
    }

    pub fn ignore_text_within(&self) -> Vec<String> {
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

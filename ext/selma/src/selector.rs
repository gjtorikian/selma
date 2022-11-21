use magnus::{
    exception, function, DataTypeFunctions, Error, Module, Object, RArray, RHash, RModule, Symbol,
    TryConvert, TypedData, Value,
};

#[derive(Clone, Debug, DataTypeFunctions, TypedData)]
#[magnus(class = "Selma::Selector", size)]
pub struct SelmaSelector {
    match_element: String,
    text_element: String,
    ignore_text_within: Vec<String>,
}

impl SelmaSelector {
    fn new(selector: RHash) -> Self {
        let match_element = selector
            .lookup::<_, String>(Symbol::new("match_element"))
            .unwrap_or(String::new());

        let text_element = selector
            .lookup::<_, String>(Symbol::new("text_element"))
            .unwrap_or(String::new());

        if match_element.is_empty() && text_element.is_empty() {
            Error::new(exception::type_error(), format!("no implicit conversion"));
        }

        let rb_ignore_text_within = selector
            .lookup::<_, RArray>(Symbol::new("ignore_text_within"))
            .unwrap_or(RArray::new()); // TODO: test this against malice
        let mut ignore_text_within: Vec<String> = vec![];
        for i in rb_ignore_text_within.each() {
            // TODO: test this against malice
            let ignore_text_within_tag_name = i.unwrap().to_string();
            ignore_text_within.push(ignore_text_within_tag_name);
        }

        Self {
            match_element,
            text_element,
            ignore_text_within,
        }
    }

    pub fn match_element(&self) -> String {
        self.match_element.clone()
    }

    pub fn text_element(&self) -> String {
        self.text_element.clone()
    }

    pub fn ignore_text_within(&self) -> Vec<String> {
        self.ignore_text_within.clone()
    }

    // #[inline]
    // pub fn from_value(val: Value) -> Option<Self> {
    //     SelmaSelector::from_value(val)
    // }
}

// impl TryConvert for SelmaSelector {
//     fn try_convert(val: Value) -> Result<Self, Error> {
//         match Self::from_value(val) {
//             Some(v) => Ok(v),
//             None => Err(Error::new(
//                 exception::type_error(),
//                 format!("no implicit conversion of {} into Class", unsafe {
//                     val.classname()
//                 },),
//             )),
//         }
//     }
// }

pub fn init(m_selma: RModule) -> Result<(), Error> {
    let c_selector = m_selma
        .define_class("Selector", Default::default())
        .expect("cannot find class Selma::Selector");

    c_selector.define_singleton_method("new", function!(SelmaSelector::new, 1))?;

    Ok(())
}

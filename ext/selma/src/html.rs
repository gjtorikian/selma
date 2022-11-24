use magnus::{Error, Module, RModule};

#[derive(Clone, Debug)]
#[magnus::wrap(class = "Selma::HTML")]
pub(crate) struct SelmaHTML {}

pub fn init(m_selma: RModule) -> Result<(), Error> {
    let c_html = m_selma.define_class("HTML", Default::default()).unwrap();

    element::init(c_html).expect("cannot define Selma::HTML::Element class");
    end_tag::init(c_html).expect("cannot define Selma::HTML::EndTag class");

    Ok(())
}
pub mod element;
pub mod end_tag;

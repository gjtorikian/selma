extern crate core;

use magnus::{define_module, Error};

pub mod html;
pub mod native_ref_wrap;
pub mod rewriter;
pub mod sanitizer;
pub mod selector;
pub mod tags;
pub mod wrapped_struct;

#[magnus::init]
fn init() -> Result<(), Error> {
    let m_selma = define_module("Selma").expect("cannot define ::Selma module");

    sanitizer::init(m_selma).expect("cannot define Selma::Sanitizer class");
    rewriter::init(m_selma).expect("cannot define Selma::Rewriter class");
    html::init(m_selma).expect("cannot define Selma::HTML class");
    selector::init(m_selma).expect("cannot define Selma::Selector class");

    Ok(())
}

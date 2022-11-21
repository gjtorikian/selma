extern crate core;

use magnus::{define_module, Error};

pub mod html;

#[magnus::init]
fn init() -> Result<(), Error> {
    let m_selma = define_module("Selma").expect("cannot define ::Selma module");

    html::init(m_selma);
    sanitizer::init(m_selma);
    selector::init(m_selma);
    rewriter::init(m_selma);

    Ok(())
}

pub mod tags;

pub mod native_ref_wrap;
pub mod rewriter;
pub mod sanitizer;
pub mod selector;
pub mod wrapped_struct;

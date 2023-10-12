extern crate core;

use lol_html::html_content::ContentType;
use magnus::{define_module, exception, scan_args, Error, Symbol, Value};

pub mod html;
pub mod native_ref_wrap;
pub mod rewriter;
pub mod sanitizer;
pub mod selector;
pub mod tags;

#[allow(clippy::let_unit_value)]
fn scan_text_args(args: &[Value]) -> Result<(String, ContentType), magnus::Error> {
    let args = scan_args::scan_args(args)?;
    let (text,): (String,) = args.required;
    let _: () = args.optional;
    let _: () = args.splat;
    let _: () = args.trailing;
    let _: () = args.block;

    let kwargs = scan_args::get_kwargs::<_, (Symbol,), (), ()>(args.keywords, &["as"], &[])?;
    let as_sym = kwargs.required.0;
    let as_sym_str = as_sym.name().unwrap();
    let content_type = if as_sym_str == "text" {
        ContentType::Text
    } else if as_sym_str == "html" {
        ContentType::Html
    } else {
        return Err(Error::new(
            exception::runtime_error(),
            format!("unknown symbol `{as_sym_str:?}`"),
        ));
    };

    Ok((text, content_type))
}

#[magnus::init]
fn init() -> Result<(), Error> {
    let m_selma = define_module("Selma").expect("cannot define ::Selma module");

    sanitizer::init(m_selma).expect("cannot define Selma::Sanitizer class");
    rewriter::init(m_selma).expect("cannot define Selma::Rewriter class");
    html::init(m_selma).expect("cannot define Selma::HTML class");
    selector::init(m_selma).expect("cannot define Selma::Selector class");

    Ok(())
}

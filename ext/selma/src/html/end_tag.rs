use magnus::{function, Error, Module, RClass};

#[magnus::wrap(class = "EndTag")]
struct EndTag {}

impl EndTag {
    fn new() -> Self {
        Self {}
    }

    fn tag_name() {}
}

pub fn init(c_html: RClass) -> Result<(), Error> {
    let c_end_tag = c_html
        .define_class("EndTag", Default::default())
        .expect("cannot find class Selma::EndTag");

    c_end_tag.define_method("tag_name", function!(EndTag::tag_name, 0))?;

    Ok(())
}

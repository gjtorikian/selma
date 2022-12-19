# Selma

Selma **sel**ects and **ma**tches HTML nodes using CSS rules. (It can also reject/delete nodes, but then the name isn't as cool.) It's mostly an idiomatic wrapper around Cloudflare's [lol-html](https://github.com/cloudflare/lol-html) project.

![Principal Skinner asking Selma after their date: 'Isn't it nice we hate the same things?'](https://user-images.githubusercontent.com/64050/207155384-14e8bd40-780c-466f-bfff-31a8a8fc3d25.jpg)

Selma's strength (aside from being backed by Rust) is that HTML content is parsed _once_ and can be manipulated multiple times.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'selma'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install selma

## Usage

Selma can perform two different actions:

- Sanitize HTML, through a [Sanitize](https://github.com/rgrove/sanitize)-like allowlist syntax; and
- Select HTML using CSS rules, and manipulate elements and text

The basic API for Selma looks like this:

```ruby
rewriter = Selma::Rewriter.new(sanitizer: sanitizer_config, handlers: [MatchAttribute.new, TextRewrite.new])
rewriter(html)
```

Let's take a look at each part individually.

### Sanitization config

Selma sanitizes by default. That is, even if the `sanitizer` kwarg is not passed in, sanitization occurs. If you want to disable HTML sanitization (for some reason), pass `nil`:

```ruby
Selma::Rewriter.new(sanitizer: nil) # dangerous and ill-advised
```

The configuration for the sanitization process is based on the follow key-value hash allowlist:

```ruby
# Whether or not to allow HTML comments.
allow_comments: false,

# Whether or not to allow well-formed HTML doctype declarations such as
# "<!DOCTYPE html>" when sanitizing a document.
allow_doctype: false,

# HTML attributes to allow in specific elements. The key is the name of the element,
# and the value is an array of allowed attributes. By default, no attributes
# are allowed.
attributes: {
    "a" => ["href"],
    "img" => ["src"],
},

# HTML elements to allow. By default, no elements are allowed (which means
# that all HTML will be stripped).
elements: ["a", "b", "img", ],

# URL handling protocols to allow in specific attributes. By default, no
# protocols are allowed. Use :relative in place of a protocol if you want
# to allow relative URLs sans protocol.
 protocols: {
    "a" => { "href" => ["http", "https", "mailto", :relative] },
    "img" => { "href" => ["http", "https"] },
},

# An Array of element names whose contents will be removed. The contents
# of all other filtered elements will be left behind.
remove_contents: ["iframe", "math", "noembed", "noframes", "noscript"],

# Elements which, when removed, should have their contents surrounded by
# whitespace.
whitespace_elements: ["blockquote", "h1", "h2", "h3", "h4", "h5", "h6", ]
```

### Defining handlers

The real power in Selma comes in its use of handlers. A handler is simply an object with various methods:

- `selector`, a method which MUST return instance of `Selma::Selector` which defines the CSS classes to match
- `handle_element`, a method that's call on each matched element
- `handle_text`, a method that's called on each matched text node; this MUST return a string

Here's an example which rewrites the `href` attribute on `a` and the `src` attribute on `img` to be `https` rather than `http`.

```ruby
class MatchAttribute
  SELECTOR = Selma::Selector(match_element: "a, img")

  def handle_element(element)
    if element.tag_name == "a" && element["href"] =~ /^http:/
      element["href"] = rename_http(element["href"])
    elsif element.tag_name == "img" && element["src"] =~ /^http:/
      element["src"] = rename_http(element["src"])
    end
  end

  private def rename_http(link)
    link.sub("http", "https")
  end
end

rewriter = Selma::Rewriter.new(handlers: [MatchAttribute.new])
```

The `Selma::Selector` object has three possible kwargs:

- `match_element`: any element which matches this CSS rule will be passed on to `handle_element`
- `match_text_within`: any element which matches this CSS rule will be passed on to `handle_text`
- `ignore_text_within`: this is an array of element names whose text contents will be ignored

You've seen an example of `match_element`; here's one for `match_text` which changes strings in various elements which are _not_ `pre` or `code`:

```ruby

class MatchText
  SELECTOR = Selma::Selector.new(match_text_within: "*", ignore_text_within: ["pre", "code"])

  def selector
    SELECTOR
  end

  def handle_text(text)
    string.sub(/@.+/, "<a href=\"www.yetto.app/#{Regexp.last_match}\">")
  end
end

rewriter = Selma::Rewriter.new(handlers: [MatchText.new])
```

#### `element` methods

The `element` argument in `handle_element` has the following methods:

- `tag_name`: The element's name
- `[]`: get an attribute
- `[]=`: set an attribute
- `remove_attribute`: remove an attribute
- `attributes`: list all the attributes
- `ancestors`: list all the ancestors
- `append(content, content_type)`: appends `content` to the element's inner content, i.e. inserts content right before the element's end tag. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `wrap(start_text, end_text, content_type)`: adds `start_text` before an element and `end_text` after an element. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `set_inner_content`: replaces inner content of the element with `content`. `content_type` is either `:text` or `:html` and determines how the content will be applied.

## Benchmarks

TBD

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gjtorikian/selma. This project is a safe, welcoming space for collaboration.

## Acknowledgements

- https://github.com/flavorjones/ruby-c-extensions-explained#strategy-3-precompiled and [Nokogiri](https://github.com/sparklemotion/nokogiri) for hints on how to ship precompiled cross-platform gems
- @vmg for his work at GitHub on goomba, from which some design patterns were learned
- [sanitize](https://github.com/rgrove/sanitize) for a comprehensive configuration API and test suite

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

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

Selma can perform two different actions, either independently or together:

- Sanitize HTML, through a [Sanitize](https://github.com/rgrove/sanitize)-like allowlist syntax; and
- Select HTML using CSS rules, and manipulate elements and text nodes along the way.

It does this through two kwargs: `sanitizer` and `handlers`. The basic API for Selma looks like this:

```ruby
sanitizer_config = {
   elements: ["b", "em", "i", "strong", "u"],
}
sanitizer = Selma::Sanitizer.new(sanitizer_config)
rewriter = Selma::Rewriter.new(sanitizer: sanitizer, handlers: [MatchElementRewrite.new, MatchTextRewrite.new])
# removes any element that is not  ["b", "em", "i", "strong", "u"];
# then calls `MatchElementRewrite` and `MatchTextRewrite` on matching HTML elements
rewriter.rewrite(html)
```

Here's a look at each individual part.

### Sanitization config

Selma sanitizes by default. That is, even if the `sanitizer` kwarg is not passed in, sanitization occurs. If you truly want to disable HTML sanitization (for some reason), pass `nil`:

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

# HTML elements to allow. By default, no elements are allowed (which means
# that all HTML will be stripped).
elements: ["a", "b", "img", ],

# HTML attributes to allow in specific elements. The key is the name of the element,
# and the value is an array of allowed attributes. By default, no attributes
# are allowed.
attributes: {
    "a" => ["href"],
    "img" => ["src"],
},

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

The real power in Selma comes in its use of handlers. A handler is simply an object with various methods defined:

- `selector`, a method which MUST return instance of `Selma::Selector` which defines the CSS classes to match
- `handle_element`, a method that's call on each matched element
- `handle_text_chunk`, a method that's called on each matched text node

Here's an example which rewrites the `href` attribute on `a` and the `src` attribute on `img` to be `https` rather than `http`.

```ruby
class MatchAttribute
  SELECTOR = Selma::Selector(match_element: %(a[href^="http:"], img[src^="http:"]"))

  def handle_element(element)
    if element.tag_name == "a"
      element["href"] = rename_http(element["href"])
    elsif element.tag_name == "img"
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
- `match_text_within`: any text_chunk which matches this CSS rule will be passed on to `handle_text_chunk`
- `ignore_text_within`: this is an array of element names whose text contents will be ignored

Here's an example for `handle_text_chunk` which changes strings in various elements which are _not_ `pre` or `code`:

```ruby

class MatchText
  SELECTOR = Selma::Selector.new(match_text_within: "*", ignore_text_within: ["pre", "code"])

  def selector
    SELECTOR
  end

  def handle_text_chunk(text)
    string.sub(/@.+/, "<a href=\"www.yetto.app/#{Regexp.last_match}\">")
  end
end

rewriter = Selma::Rewriter.new(handlers: [MatchText.new])
```

#### `element` methods

The `element` argument in `handle_element` has the following methods:

- `tag_name`: Gets the element's name
- `tag_name=`: Sets the element's name
- `self_closing?`: A bool which identifies whether or not the element is self-closing
- `[]`: Get an attribute
- `[]=`: Set an attribute
- `remove_attribute`: Remove an attribute
- `has_attribute?`: A bool which identifies whether or not the element has an attribute
- `attributes`: List all the attributes
- `ancestors`: List all of an element's ancestors as an array of strings
- `before(content, as: content_type)`: Inserts `content` before the element. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `after(content, as: content_type)`: Inserts `content` after the element. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `prepend(content, as: content_type)`: prepends `content` to the element's inner content, i.e. inserts content right after the element's start tag. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `append(content, as: content_type)`: appends `content` to the element's inner content, i.e. inserts content right before the element's end tag. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `set_inner_content`: Replaces inner content of the element with `content`. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `remove`: Removes the element and its inner content.
- `remove_and_keep_content`: Removes the element, but keeps its content. I.e. remove start and end tags of the element.
- `removed?`: A bool which identifies if the element has been removed or replaced with some content.

#### `text_chunk` methods

- `to_s` / `.content`: Gets the text node's content
- `text_type`: identifies the type of text in the text node
- `before(content, as: content_type)`: Inserts `content` before the text. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `after(content, as: content_type)`: Inserts `content` after the text. `content_type` is either `:text` or `:html` and determines how the content will be applied.
- `replace(content, as: content_type)`: Replaces the text node with `content`. `content_type` is either `:text` or `:html` and determines how the content will be applied.

## Benchmarks

<details>
<pre>
ruby test/benchmark.rb
ruby test/benchmark.rb
Warming up --------------------------------------
sanitize-document-huge
                         1.000  i/100ms
 selma-document-huge     1.000  i/100ms
Calculating -------------------------------------
sanitize-document-huge
                          0.257  (± 0.0%) i/s -      2.000  in   7.783398s
 selma-document-huge      4.602  (± 0.0%) i/s -     23.000  in   5.002870s
Warming up --------------------------------------
sanitize-document-medium
                         2.000  i/100ms
selma-document-medium
                        22.000  i/100ms
Calculating -------------------------------------
sanitize-document-medium
                         28.676  (± 3.5%) i/s -    144.000  in   5.024669s
selma-document-medium
                        121.500  (±22.2%) i/s -    594.000  in   5.135410s
Warming up --------------------------------------
sanitize-document-small
                        10.000  i/100ms
selma-document-small    20.000  i/100ms
Calculating -------------------------------------
sanitize-document-small
                        107.280  (± 0.9%) i/s -    540.000  in   5.033850s
selma-document-small    118.867  (±31.1%) i/s -    540.000  in   5.080726s
</pre>
</details>

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gjtorikian/selma. This project is a safe, welcoming space for collaboration.

## Acknowledgements

- https://github.com/flavorjones/ruby-c-extensions-explained#strategy-3-precompiled and [Nokogiri](https://github.com/sparklemotion/nokogiri) for hints on how to ship precompiled cross-platform gems
- @vmg for his work at GitHub on goomba, from which some design patterns were learned
- [sanitize](https://github.com/rgrove/sanitize) for a comprehensive configuration API and test suite

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

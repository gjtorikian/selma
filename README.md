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
# to allow relative URLs sans protocol. Set to `:all` to allow any protocol.
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
  SELECTOR = Selma::Selector.new(match_element: %(a[href^="http:"], img[src^="http:"]"))

  def selector
    SELECTOR
  end

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

## Security

Theoretically, a malicious user can provide a very large document for processing, which can exhaust the memory of the host machine. To set a limit on how much string content is processed at once, you can provide two options into the `memory` namespace:

```ruby
memory: {
  max_allowed_memory_usage: 1000,
  preallocated_parsing_buffer_size: 100,
},
```

Note that `preallocated_parsing_buffer_size` must always be less than `max_allowed_memory_usage`. See [the`lol_html` project documentation](https://docs.rs/lol_html/1.2.1/lol_html/struct.MemorySettings.html) to learn more about the default values.

## Benchmarks

When `bundle exec rake benchmark`, two different benchmarks are calculated. Here are those results on my machine.

### Benchmarks for just the sanitization process

Comparing Selma against popular Ruby sanitization gems:

<!-- prettier-ignore-start -->
<details>
<pre>
input size = 25309 bytes, 0.03 MB

ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [arm64-darwin23]
Warming up --------------------------------------
         sanitize-sm    16.000 i/100ms
            selma-sm   214.000 i/100ms
Calculating -------------------------------------
         sanitize-sm    171.670 (± 1.2%) i/s -      5.152k in  30.017081s
            selma-sm      2.146k (± 3.0%) i/s -     64.414k in  30.058470s

Comparison:
            selma-sm:     2145.8 i/s
         sanitize-sm:      171.7 i/s - 12.50x  slower

input size = 86686 bytes, 0.09 MB

ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [arm64-darwin23]
Warming up --------------------------------------
         sanitize-md     4.000 i/100ms
            selma-md    56.000 i/100ms
Calculating -------------------------------------
         sanitize-md     44.397 (± 2.3%) i/s -      1.332k in  30.022430s
            selma-md    558.448 (± 1.4%) i/s -     16.800k in  30.089196s

Comparison:
            selma-md:      558.4 i/s
         sanitize-md:       44.4 i/s - 12.58x  slower

input size = 7172510 bytes, 7.17 MB

ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [arm64-darwin23]
Warming up --------------------------------------
         sanitize-lg     1.000 i/100ms
            selma-lg     1.000 i/100ms
Calculating -------------------------------------
         sanitize-lg      0.163 (± 0.0%) i/s -      6.000 in  37.375628s
            selma-lg      6.750 (± 0.0%) i/s -    203.000 in  30.080976s

Comparison:
            selma-lg:        6.7 i/s
         sanitize-lg:        0.2 i/s - 41.32x  slower
</pre>
</details>
<!-- prettier-ignore-end -->

### Benchmarks for just the rewriting process

Comparing Selma against popular Ruby HTML parsing gems:

<!-- prettier-ignore-start -->
<details>
<pre>input size = 25309 bytes, 0.03 MB

ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [arm64-darwin23]
Warming up --------------------------------------
         nokogiri-sm   107.000 i/100ms
       nokolexbor-sm   340.000 i/100ms
            selma-sm   380.000 i/100ms
Calculating -------------------------------------
         nokogiri-sm      1.073k (± 2.1%) i/s -     32.207k in  30.025474s
       nokolexbor-sm      3.300k (±13.2%) i/s -     27.540k in  36.788212s
            selma-sm      3.779k (± 3.4%) i/s -    113.240k in  30.013908s

Comparison:
            selma-sm:     3779.4 i/s
       nokolexbor-sm:     3300.1 i/s - same-ish: difference falls within error
         nokogiri-sm:     1073.1 i/s - 3.52x  slower

input size = 86686 bytes, 0.09 MB

ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [arm64-darwin23]
Warming up --------------------------------------
         nokogiri-md    11.000 i/100ms
       nokolexbor-md    48.000 i/100ms
            selma-md    53.000 i/100ms
Calculating -------------------------------------
         nokogiri-md    103.998 (± 5.8%) i/s -      3.113k in  30.029932s
       nokolexbor-md    428.928 (± 7.9%) i/s -     12.816k in  30.066662s
            selma-md    492.190 (± 6.9%) i/s -     14.734k in  30.082943s

Comparison:
            selma-md:      492.2 i/s
       nokolexbor-md:      428.9 i/s - same-ish: difference falls within error
         nokogiri-md:      104.0 i/s - 4.73x  slower

input size = 7172510 bytes, 7.17 MB

ruby 3.3.0 (2023-12-25 revision 5124f9ac75) [arm64-darwin23]
Warming up --------------------------------------
         nokogiri-lg     1.000 i/100ms
       nokolexbor-lg     1.000 i/100ms
            selma-lg     1.000 i/100ms
Calculating -------------------------------------
         nokogiri-lg      0.874 (± 0.0%) i/s -     27.000 in  30.921090s
       nokolexbor-lg      2.227 (± 0.0%) i/s -     67.000 in  30.137903s
            selma-lg      8.354 (± 0.0%) i/s -    251.000 in  30.075227s

Comparison:
            selma-lg:        8.4 i/s
       nokolexbor-lg:        2.2 i/s - 3.75x  slower
         nokogiri-lg:        0.9 i/s - 9.56x  slower
</pre>
</details>
<!-- prettier-ignore-end -->

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gjtorikian/selma. This project is a safe, welcoming space for collaboration.

## Acknowledgements

- https://github.com/flavorjones/ruby-c-extensions-explained#strategy-3-precompiled and [Nokogiri](https://github.com/sparklemotion/nokogiri) for hints on how to ship precompiled cross-platform gems
- @vmg for his work at GitHub on goomba, from which some design patterns were learned
- [sanitize](https://github.com/rgrove/sanitize) for a comprehensive configuration API and test suite

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

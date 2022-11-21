# frozen_string_literal: true

module Selma
  class Sanitizer
    module Config
      DEFAULT = freeze_config(
        # Whether or not to allow HTML comments. Allowing comments is strongly
        # discouraged, since IE allows script execution within conditional
        # comments.
        allow_comments: false,

        # Whether or not to allow well-formed HTML doctype declarations such as
        # "<!DOCTYPE html>" when sanitizing a document. This setting is ignored
        # when sanitizing fragments.
        allow_doctype: false,

        # HTML attributes to allow in specific elements. By default, no attributes
        # are allowed. Use the symbol :data to indicate that arbitrary HTML5
        # data-* attributes should be allowed.
        attributes: {},

        # HTML elements to allow. By default, no elements are allowed (which means
        # that all HTML will be stripped).
        elements: [],

        # HTML parsing options to pass to Nokogumbo.
        # https://github.com/rubys/nokogumbo/tree/v2.0.1#parsing-options
        parser_options: {},

        # URL handling protocols to allow in specific attributes. By default, no
        # protocols are allowed. Use :relative in place of a protocol if you want
        # to allow relative URLs sans protocol.
        protocols: {},

        # If this is true, Sanitize will remove the contents of any filtered
        # elements in addition to the elements themselves. By default, Sanitize
        # leaves the safe parts of an element's contents behind when the element
        # is removed.
        #
        # If this is an Array or Set of element names, then only the contents of
        # the specified elements (when filtered) will be removed, and the contents
        # of all other filtered elements will be left behind.
        remove_contents: ["iframe", "math", "noembed", "noframes", "noscript", "plaintext", "script", "style", "svg",
                          "xmp",],

        # Elements which, when removed, should have their contents surrounded by
        # values specified with `before` and `after` keys to preserve readability.
        # For example, `foo<div>bar</div>baz` will become foo bar baz when the
        # <div> is removed.
        whitespace_elements: ["address", "article", "aside", "blockquote", "br", "dd", "div", "dl", "dt", "footer",
                              "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "li", "nav", "ol", "p", "pre", "section", "ul",]
      )
    end
  end
end

# frozen_string_literal: true

module SelmaConfig
  class CamoHandler
    SELECTOR = Selma::Selector.new(match: "img")

    def call(element)
      original_src = element["src"]
      return unless original_src

      begin
        uri = URI.parse(original_src)
      rescue StandardError
        return
      end

      return if uri.host.nil?
      return if asset_host_allowed?(uri.host)

      element["src"] = asset_proxy_url(original_src)
      element["data-canonical-src"] = original_src
    end
  end

  class ImageMaxWidthHandler
    SELECTOR = Selma::Selector.new(match: "img")

    def call(element)
      # Skip if there's already a style attribute. Not sure how this
      # would happen but we can reconsider it in the future.
      return if element["style"]

      # Bail out if src doesn't look like a valid http url. trying to avoid weird
      # js injection via javascript: urls.
      return if /\Ajavascript/i.match?(element["src"].to_s.strip)

      element["style"] = "max-width:100%;"

      link_image(element) unless has_ancestor?(element, ["a"])
    end
  end

  class HttpsHandler
    SELECTOR = Selma::Selector.new(match: %(a[href^="http:"]))

    def call(element)
      element["href"] = element["href"].sub(/^http:/, "https:")
    end
  end

  class MentionHandler
  end

  class EmojiHandler
  end

  class SyntaxHighlightHandler
  end

  LISTS     = Set.new(["ul", "ol"].freeze)
  LIST_ITEM = "li"

  # List of table child elements. These must be contained by a <table> element
  # or they are not allowed through. Otherwise they can be used to break out
  # of places we're using tables to contain formatted user content (like pull
  # request review comments).
  TABLE_ITEMS = Set.new(["tr", "td", "th"].freeze)
  TABLE = "table"
  TABLE_SECTIONS = Set.new(["thead", "tbody", "tfoot"].freeze)

  # These schemes are the only ones allowed in <a href> attributes by default.
  ANCHOR_SCHEMES = ["http", "https", "mailto", "xmpp"].freeze

  # The main sanitization allowlist. Only these elements and attributes are
  # allowed through by default.
  ALLOWLIST = {
    elements: ["h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8", "br", "b", "i", "strong", "em", "a", "pre", "code",
               "img", "tt", "div", "ins", "del", "sup", "sub", "p", "ol", "ul", "table", "thead", "tbody", "tfoot", "blockquote", "dl", "dt", "dd", "kbd", "q", "samp", "var", "hr", "ruby", "rt", "rp", "li", "tr", "td", "th", "s", "strike", "summary", "details", "caption", "figure", "figcaption", "abbr", "bdo", "cite", "dfn", "mark", "small", "span", "time", "wbr",].freeze,
    remove_contents: ["script"].freeze,
    attributes: {
      "a" => ["href"].freeze,
      "img" => ["src", "longdesc"].freeze,
      "div" => ["itemscope", "itemtype"].freeze,
      "blockquote" => ["cite"].freeze,
      "del" => ["cite"].freeze,
      "ins" => ["cite"].freeze,
      "q" => ["cite"].freeze,
      all: ["abbr", "accept", "accept-charset", "accesskey", "action", "align", "alt", "aria-describedby",
            "aria-hidden", "aria-label", "aria-labelledby", "axis", "border", "cellpadding", "cellspacing", "char", "charoff", "charset", "checked", "clear", "cols", "colspan", "color", "compact", "coords", "datetime", "dir", "disabled", "enctype", "for", "frame", "headers", "height", "hreflang", "hspace", "ismap", "label", "lang", "maxlength", "media", "method", "multiple", "name", "nohref", "noshade", "nowrap", "open", "progress", "prompt", "readonly", "rel", "rev", "role", "rows", "rowspan", "rules", "scope", "selected", "shape", "size", "span", "start", "summary", "tabindex", "target", "title", "type", "usemap", "valign", "value", "vspace", "width", "itemprop",].freeze,
    }.freeze,
    protocols: {
      "a" => { "href" => ANCHOR_SCHEMES }.freeze,
      "blockquote" => { "cite" => ["http", "https", :relative].freeze },
      "del" => { "cite" => ["http", "https", :relative].freeze },
      "ins" => { "cite" => ["http", "https", :relative].freeze },
      "q" => { "cite" => ["http", "https", :relative].freeze },
      "img" => {
        "src" => ["http", "https", :relative].freeze,
        "longdesc" => ["http", "https", :relative].freeze,
      }.freeze,
    },
    transformers: [
      # Top-level <li> elements are removed because they can break out of
      # containing markup.
      lambda { |env|
        name = env[:node_name]
        element = env[:element]
        element.replace(element.children) if name == LIST_ITEM && element.ancestors.none? { |n| LISTS.include?(n.name) }
      },

      # Table child elements that are not contained by a <table> are removed.
      lambda { |env|
        name = env[:node_name]
        element = env[:element]
        element.replace(element.children) if (TABLE_SECTIONS.include?(name) || TABLE_ITEMS.include?(name)) && element.ancestors.none? do |n|
                                               n.name == TABLE
                                             end
      },
    ].freeze,
  }.freeze
end

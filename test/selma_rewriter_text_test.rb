# frozen_string_literal: true

require "test_helper"

class SelmaRewriterTextTest < Minitest::Test
  class TextRewriteAll
    SELECTOR = Selma::Selector.new(match_text_within: "*")

    def selector
      SELECTOR
    end

    def handle_text_chunk(text)
      text.replace(text.to_s.sub("Wow", "MEOW!"), as: :text)
    end
  end

  def test_that_it_works_for_all
    frag = "<div>Wow!</div><span>Wow!</span><a>Wow!</a>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextRewriteAll.new]).rewrite(frag)

    assert_equal("<div>MEOW!!</div><span>MEOW!!</span><a>MEOW!!</a>", modified_doc)
  end

  class GetTextContent < Minitest::Test
    SELECTOR = Selma::Selector.new(match_text_within: "*")

    # rubocop:disable Lint/MissingSuper
    def initialize
      @assertions = 0
    end
    # rubocop:enable Lint/MissingSuper

    def selector
      SELECTOR
    end

    def handle_text_chunk(text_chunk)
      assert_equal(:rc_data, text_chunk.text_type)
    end
  end

  def test_that_it_gets_text_content
    frag = "<title>Howdy</title>"
    Selma::Rewriter.new(sanitizer: nil, handlers: [GetTextContent.new]).rewrite(frag)
  end

  class TextRewriteElements
    SELECTOR = Selma::Selector.new(match_text_within: "a, div")

    def selector
      SELECTOR
    end

    def handle_text_chunk(text)
      text.replace(text.content.sub("Wow", "MEOW!"), as: :text)
    end
  end

  def test_that_it_works_for_multiple_elements
    frag = "<div>Wow!</div><span>Wow!</span><a>Wow!</a>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextRewriteElements.new]).rewrite(frag)

    assert_equal("<div>MEOW!!</div><span>Wow!</span><a>MEOW!!</a>", modified_doc)
  end

  class AddTextBefore
    SELECTOR = Selma::Selector.new(match_text_within: "div")

    def selector
      SELECTOR
    end

    def handle_text_chunk(text)
      text.before("MEOW! ", as: :text)
    end
  end

  def test_that_it_adds_text_before
    frag = "<div>Wow!</div>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [AddTextBefore.new]).rewrite(frag)

    assert_equal("<div>MEOW! Wow!</div>", modified_doc)
  end

  class AddTextAfter
    SELECTOR = Selma::Selector.new(match_text_within: "div")

    def selector
      SELECTOR
    end

    def handle_text_chunk(text)
      text.after(" MEOW!", as: :text)
    end
  end

  def test_that_it_adds_text_after
    frag = "<div>Wow!</div>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [AddTextAfter.new]).rewrite(frag)

    assert_equal("<div>Wow! MEOW!</div>", modified_doc)
  end

  class TextRewriteAndMatchElements
    SELECTOR = Selma::Selector.new(match_element: "div", match_text_within: "div, p, a")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element["class"] = "neato"
    end

    def handle_text_chunk(text)
      text.replace(text.to_s.sub("you", "y'all"), as: :html)
    end
  end

  def test_that_it_works_for_multiple_match_and_text_elements
    frag = "<div><p>Could you visit <a>this link and tell me what you think?</a> Thank you!</div>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextRewriteAndMatchElements.new]).rewrite(frag)

    assert_equal("<div class=\"neato\"><p>Could y'all visit <a>this link and tell me what y'all think?</a> Thank y'all!</div>", modified_doc)
  end

  class TextMatchAndRejectElements
    SELECTOR = Selma::Selector.new(match_text_within: "*", ignore_text_within: ["code", "pre"])

    def selector
      SELECTOR
    end

    def handle_text_chunk(text)
      text.replace(text.to_s.sub("@gjtorik", "@gjtorikian"), as: :text)
    end
  end

  def test_that_it_works_for_text_reject
    frag = "<div><p>Hello @gjtorik: <code>@gjtorik</code></p><br/> <pre>@gjtorik</pre></div>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextMatchAndRejectElements.new]).rewrite(frag)

    assert_equal("<div><p>Hello @gjtorikian: <code>@gjtorik</code></p><br/> <pre>@gjtorik</pre></div>", modified_doc)
  end

  class TextStringResizeHandler
    DEFAULT_IGNORED_ANCESTOR_TAGS = ["pre", "code", "tt"].freeze

    def selector
      Selma::Selector.new(match_text_within: "*", ignore_text_within: DEFAULT_IGNORED_ANCESTOR_TAGS)
    end

    def handle_text_chunk(text)
      return text unless text.to_s.include?(":")

      text.replace(emoji_image_filter(text.to_s), as: :html)
    end

    def emoji_image_filter(text)
      text.gsub(emoji_pattern) do
        emoji_image_tag(Regexp.last_match(1))
      end
    end

    def emoji_pattern
      @emoji_pattern ||= /:(#{emoji_names.map { |name| Regexp.escape(name) }.join("|")}):/
    end

    def emoji_names
      Gemojione::Index.new.all.map { |i| i[1]["name"] }.flatten.sort
    end

    # Default attributes for img tag
    private def default_img_attrs(name)
      {
        "class" => "emoji",
        "title" => ":#{name}:",
        "alt" => ":#{name}:",
        "src" => emoji_url(name).to_s,
        "height" => "20",
        "width" => "20",
        "align" => "absmiddle",
      }
    end

    private def emoji_url(name)
      File.join("emoji", emoji_filename(name))
    end

    private def emoji_filename(name)
      Gemojione.image_url_for_name(name).sub(Gemojione.asset_host, "")
    end

    # Build an emoji image tag
    private def emoji_image_tag(name)
      html_attrs = default_img_attrs(name).transform_keys(&:to_sym)
        .merge!({}).transform_keys(&:to_sym)
        .each_with_object([]) do |(attr, value), arr|
        next if value.nil?

        value = value.respond_to?(:call) && value.call(name) || value
        arr << %(#{attr}="#{value}")
      end.compact.join(" ")

      "<img #{html_attrs}>"
    end
  end

  def test_that_it_can_handle_text_chunk_with_emoji
    require "gemojione"

    frag = "<span>:flag_ar:</span>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextStringResizeHandler.new]).rewrite(frag)

    assert_equal(%(<span><img class="emoji" title=":flag_ar:" alt=":flag_ar:" src="emoji/1f1e6-1f1f7.png" height="20" width="20" align="absmiddle"></span>), modified_doc)
  end unless ENV["CI"] # TODO: why doesn't this work in CI?
end

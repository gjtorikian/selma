# frozen_string_literal: true

require "test_helper"

class SelmaMaliciousnessTest < Minitest::Test
  class NoSelector
    def initialize
    end

    def handle_element(element)
      element["class"] = "boldy"
    end
  end

  def test_that_it_does_hate_missing_selector
    frag = "<b>Wow!</b>"
    assert_raises(NoMethodError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [NoSelector.new]).rewrite(frag)
    end
  end

  class NoHandleElement
    SELECTOR = Selma::Selector.new(match_element: "b")

    def selector
      SELECTOR
    end
  end

  def test_that_it_does_not_hate_missing_handle_element
    frag = "<span>Wow!</span>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [NoHandleElement.new]).rewrite(frag)

    assert_equal(frag, modified_doc)
  end

  class NoHandleText
    SELECTOR = Selma::Selector.new(match_text_within: "strong")

    def selector
      SELECTOR
    end
  end

  def test_that_it_does_hate_missing_match_text_within
    frag = "<strong>Wow!</strong>"
    assert_raises(RuntimeError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [NoHandleText.new]).rewrite(frag)
    end
  end

  def test_that_it_does_hate_nil_sanitizer_and_blank_handlers
    frag = "<i>Wow!</i>"
    assert_raises(ArgumentError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: []).rewrite(frag)
    end
  end

  def test_that_it_raises_on_non_array_handlers
    frag = "<sup>Wow!</sup>"
    assert_raises(TypeError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: 818).rewrite(frag)
    end
  end

  def test_that_it_raises_on_array_handler_with_wrong_type
    frag = "<sub>Wow!</sub>"
    assert_raises(NoMethodError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [562]).rewrite(frag)
    end
  end

  class WrongSelectorArgument
    def selector
      Selma::Selector.new(55)
    end
  end

  def test_that_it_raises_on_wrong_selector_arg
    frag = "<strong>Wow!</strong>"
    assert_raises(TypeError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [WrongSelectorArgument.new]).rewrite(frag)
    end
  end

  class IncorrectSelectorType
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def selector
      3
    end
  end

  def test_that_it_raises_on_incorrect_selector_type
    frag = "<strong>Wow!</strong>"
    assert_raises(TypeError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [IncorrectSelectorType.new]).rewrite(frag)
    end
  end

  class IncorrectMatchType
    def selector
      Selma::Selector.new(match_element: 42)
    end
  end

  def test_that_it_raises_on_incorrect_match_type
    frag = "<abbr>Wow!</abbr>"
    assert_raises(TypeError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [IncorrectMatchType.new]).rewrite(frag)
    end
  end

  class IncorrectTextType
    def selector
      Selma::Selector.new(match_text_within: 42)
    end
  end

  def test_that_it_raises_on_incorrect_text_type
    frag = "<small>Wow!</small>"
    assert_raises(TypeError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [IncorrectTextType.new]).rewrite(frag)
    end
  end

  class NilOptions
    def selector
      Selma::Selector.new(match_element: nil, match_text_within: nil)
    end
  end

  def test_that_it_raises_on_both_options_being_nil
    frag = "<strong>Wow!</strong>"
    assert_raises(NoMethodError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [NilOptions]).rewrite(frag)
    end
  end

  class GarbageTextOptions
    def selector
      Selma::Selector.new(match_text_within: "time")
    end

    def handle_text_chunk(text)
      text.replace(text.sub("Wow!", as: :boop))
    end
  end

  def test_that_it_raises_on_handle_text_returning_non_string
    frag = "<time>Wow!</time>"
    assert_raises(RuntimeError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [GarbageTextOptions.new]).rewrite(frag)
    end
  end

  def test_sanitizer_expects_all_as_symbol
    assert_raises(ArgumentError) do
      Selma::Sanitizer.new({
        elements: ["a"],
        attributes: { "a" => ["href"] },
        protocols: { "a" => { "href" => [:all] } },
      })
    end
  end

  class ContentExtractor
    SELECTOR = Selma::Selector.new(match_element: "*", match_text_within: "title")

    attr_reader :title, :meta

    def initialize
      super
      @title = ""
      @meta = {}
      @within_title = false
    end

    def selector
      SELECTOR
    end

    def handle_element(element)
      if element.tag_name == "pre" ||
          element.tag_name == "code" ||
          element.tag_name == "form" ||
          element.tag_name == "style" ||
          element.tag_name == "noscript" ||
          element.tag_name == "script" ||
          element.tag_name == "svg"
        element.remove
      elsif element.tag_name == "title"
        @within_title = true
        element.remove
      elsif element.tag_name == "meta"
        return if element.attributes["name"].nil?

        @meta[element.attributes["name"]] = element.attributes["content"]
      else
        element.remove_and_keep_content
      end
    end

    def handle_text_chunk(text)
      if @within_title
        @within_title = false
        @title = text.to_s
      end
    end
  end

  def test_rewriter_does_not_halt_on_malformed_html
    html = load_fixture("docs.html")

    sanitizer_config = Selma::Sanitizer::Config::RELAXED.dup.merge({
      allow_doctype: false,
    })
    sanitizer = Selma::Sanitizer.new(sanitizer_config)

    Selma::Rewriter.new(sanitizer: sanitizer, handlers: [ContentExtractor.new]).rewrite(html)
  end

  class TagRemover
    SELECTOR = Selma::Selector.new(match_element: "*")

    def selector
      SELECTOR
    end

    UNNECESSARY_TAGS = [
      "pre",
    ]

    CONTENT_TO_KEEP = [
      "html",
      "body",
    ]

    def handle_element(element)
      if UNNECESSARY_TAGS.include?(element.tag_name)
        element.remove
      elsif CONTENT_TO_KEEP.include?(element.tag_name)
        element.remove_and_keep_content
      end
    end
  end

  class ContentBreaker
    SELECTOR = Selma::Selector.new(match_element: "*")

    def selector
      SELECTOR
    end

    def handle_element(element)
      if Selma::Sanitizer::Config::DEFAULT[:whitespace_elements].include?(element.tag_name) && !element.removed?
        element.append("\n", as: :text)
      end
      element.remove_and_keep_content
    end
  end

  def test_deleted_content_does_not_segfault
    html = load_fixture("deleting_content.html")

    sanitizer_config = Selma::Sanitizer::Config::RELAXED.dup.merge({
      allow_comments: false,
      allow_doctype: false,
    })
    sanitizer = Selma::Sanitizer.new(sanitizer_config)

    selma = Selma::Rewriter.new(sanitizer: sanitizer, handlers: [TagRemover.new, ContentBreaker.new])
    1000.times do
      selma.rewrite(html)
    end
  end if ci?
end

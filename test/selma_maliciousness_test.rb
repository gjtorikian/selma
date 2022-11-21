# frozen_string_literal: true

require "test_helper"

class SelmaMaliciousnessTest < Minitest::Test
  class NoSelector
    def handle_element(element)
      element["class"] = "boldy"
    end
  end

  def test_that_it_does_not_hate_missing_selector
    frag = "<b>Wow!</b>"
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [NoSelector.new]).rewrite
    assert_equal(frag, modified_doc)
  end

  class NoHandleElement
    SELECTOR = Selma::Selector.new(match_element: "b")

    def selector
      SELECTOR
    end
  end

  def test_that_it_does_not_hate_missing_handle_element
    frag = "<span>Wow!</span>"
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [NoHandleElement.new]).rewrite
    assert_equal(frag, modified_doc)
  end

  class NoHandleText
    SELECTOR = Selma::Selector.new(match_text: "span")

    def selector
      SELECTOR
    end
  end

  def test_that_it_does_not_hate_missing_handle_text
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [NoHandleText.new]).rewrite
    assert_equal(frag, modified_doc)
  end

  def test_that_it_does_not_hate_nil_handlers
    frag = "<i>Wow!</i>"
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: nil).rewrite
    assert_equal(frag, modified_doc)
  end

  def test_that_it_raises_on_non_array_handlers
    frag = "<sup>Wow!</sup>"
    assert_raises(TypeError) do
      Selma::HTML.new(frag, sanitizer: nil, handlers: 818).rewrite
    end
  end

  def test_that_it_raises_on_array_handler_with_wrong_type
    frag = "<sub>Wow!</sub>"
    assert_raises(TypeError) do
      Selma::HTML.new(frag, sanitizer: nil, handlers: [562]).rewrite
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
      Selma::HTML.new(frag, sanitizer: nil, handlers: [WrongSelectorArgument.new]).rewrite
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
      Selma::HTML.new(frag, sanitizer: nil, handlers: [IncorrectSelectorType.new]).rewrite
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
      Selma::HTML.new(frag, sanitizer: nil, handlers: [IncorrectMatchType.new]).rewrite
    end
  end

  class IncorrectTextType
    def selector
      Selma::Selector.new(match_text: 42)
    end
  end

  def test_that_it_raises_on_incorrect_text_type
    frag = "<small>Wow!</small>"
    assert_raises(TypeError) do
      Selma::HTML.new(frag, sanitizer: nil, handlers: [IncorrectTextType.new]).rewrite
    end
  end

  class NilOptions
    def selector
      Selma::Selector.new(match_element: nil, match_text: nil)
    end
  end

  def test_that_it_raises_on_both_options_being_nil
    frag = "<strong>Wow!</strong>"
    assert_raises(ArgumentError) do
      Selma::HTML.new(frag, sanitizer: nil, handlers: [NilOptions.new]).rewrite
    end
  end

  class GarbageTextReturn
    def selector
      Selma::Selector.new(match_text: "time")
    end

    def handle_text(text)
      400
    end
  end

  def test_that_it_raises_on_handle_text_returning_non_string
    frag = "<time>Wow!</time>"
    assert_raises(TypeError) do
      Selma::HTML.new(frag, sanitizer: nil, handlers: [GarbageTextReturn.new]).rewrite
    end
  end
end

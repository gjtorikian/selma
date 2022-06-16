# frozen_string_literal: true

require "test_helper"

class SelmaMaliciousnessTest < Minitest::Test
  class NoSelector
    def handle_element(element)
      element["class"] = "boldy"
    end
  end

  def test_that_it_does_not_hate_missing_selector
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [NoSelector.new]).rewrite
    assert_equal(frag, modified_doc)
  end

  class NoCall
    SELECTOR = Selma::Selector.new(match: "strong")

    def selector
      SELECTOR
    end
  end

  def test_that_it_does_not_hate_missing_process
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [NoCall.new]).rewrite
    assert_equal(frag, modified_doc)
  end

  class WrongSelectorArgument
    def selector
      Selma::Selector.new(55)
    end
  end

  def test_that_it_raises_on_wrong_selector_arg
    frag = "<strong>Wow!</strong>"
    assert_raises(TypeError) do
    Selma::HTML.new(frag, sanitizer: nil, handlers: [NoCall.new]).rewrite
    end
  end

  class IncorrectSelectorType
    SELECTOR = Selma::Selector.new(match: "strong")

    def selector
      3
    end
  end

  def test_that_it_raises_on_incorrect_selector_type
    assert_raises(TypeError) do
      Selma::HTML.new(frag, sanitizer: nil, handlers: [IncorrectSelectorType.new]).rewrite
    end
  end

  class IncorrectMatchType
    def selector
      Selma::Selector.new(match: 42)
    end
  end

  def test_that_it_raises_on_incorrect_selector_type
    frag = "<strong>Wow!</strong>"
    assert_raises(TypeError) do
      Selma::HTML.new(frag, sanitizer: nil, handlers: [IncorrectMatchType.new]).rewrite
    end
  end
end

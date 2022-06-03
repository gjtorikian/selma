# frozen_string_literal: true

require "test_helper"

class SelmaTest < Minitest::Test
  def setup
    @sanitizer = Selma::Sanitizer.new(Selma::Sanitizer::Config::RELAXED)
  end

  class Handler
    SELECTOR = Selma::Selector.new(match: "strong")

    def selector
      SELECTOR
    end

    def process(element)
      element["class"] = "boldy"
    end
  end

  def test_that_it_has_a_version_number
    refute_nil(::Selma::VERSION)
  end

  def test_that_it_works_with_fragment
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::HTML.new(frag, sanitizer: @sanitizer, handlers: [Handler.new]).rewrite
    assert_equal('<strong class="boldy">Wow!</strong>', modified_doc)
  end

  class NoSelector
    def call(element)
      element["class"] = "boldy"
    end
  end

  def test_that_it_does_not_hate_missing_selector
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::HTML.new(frag, sanitizer: @sanitizer, handlers: [NoSelector.new]).rewrite
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
    modified_doc = Selma::HTML.new(frag, sanitizer: @sanitizer, handlers: [NoCall.new]).rewrite
    assert_equal(frag, modified_doc)
  end

  class RemoveAttr
    SELECTOR = Selma::Selector.new(match: "a")

    def selector
      SELECTOR
    end

    def process(element)
      element.remove_attribute("foo")
    end
  end

  def test_that_it_removes_attributes
    frag = "<a foo='bleh'><span foo='keep'>Wow!</span></a>"
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [RemoveAttr.new]).rewrite
    assert_equal("<a><span foo='keep'>Wow!</span></a>", modified_doc)
  end

  class GetAttrs < Minitest::Test
    SELECTOR = Selma::Selector.new(match: "div")

    def selector
      SELECTOR
    end

    def process(element)
      hash = {
        "class" => "a b c 1 2 3",
        "data-foo" => "baz",
      }
      assert_equal(hash, element.attributes)
    end
  end

  def test_that_it_gets_attributes
    frag = "<article><div class='a b c 1 2 3' data-foo='baz'>Wow!</div></article>"
    Selma::HTML.new(frag, sanitizer: nil, handlers: [GetAttrs.new("GetAttrs")]).rewrite
  end
end

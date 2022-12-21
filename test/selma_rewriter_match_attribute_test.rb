# frozen_string_literal: true

require "test_helper"

class SelmaRewriterMatchAttributeTest < Minitest::Test
  class RemoveAttr
    SELECTOR = Selma::Selector.new(match_element: "a")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element.remove_attribute("foo")
    end
  end

  def test_that_it_removes_attributes
    frag = "<a foo='bleh'><span foo='keep'>Wow!</span></a>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [RemoveAttr.new]).rewrite(frag)

    assert_equal("<a><span foo='keep'>Wow!</span></a>", modified_doc)
  end

  class GetAttrs < Minitest::Test
    SELECTOR = Selma::Selector.new(match_element: "div")

    # rubocop:disable Lint/MissingSuper
    def initialize
      @assertions = 0
    end
    # rubocop:enable Lint/MissingSuper

    def selector
      SELECTOR
    end

    def handle_element(element)
      hash = {
        "class" => "a b c 1 2 3",
        "data-foo" => "baz",
      }

      assert_equal(hash, element.attributes)
    end
  end

  def test_that_it_gets_attributes
    frag = "<article><div class='a b c 1 2 3' data-foo='baz'>Wow!</div></article>"
    Selma::Rewriter.new(sanitizer: nil, handlers: [GetAttrs.new]).rewrite(frag)
  end
end

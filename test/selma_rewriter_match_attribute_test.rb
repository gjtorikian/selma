# frozen_string_literal: true

## frozen_string_literal: true

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

    def initialize # rubocop:disable Lint/MissingSuper
      @assertions = 0
    end

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

  class InvalidCSS
    SELECTOR = Selma::Selector.new(match_element: %(a[href=]))

    def selector
      SELECTOR
    end

    def handle_element(element) # never called
      element["href"] = element["href"].sub(/^http:/, "https:")
    end
  end

  def test_that_it_defends_against_invalid_css
    frag = %(<a href="http://github.com">github.com</a>)
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [InvalidCSS.new]).rewrite(frag)
    assert_equal(frag, modified_doc)
  end

  class EmptyCSS
    SELECTOR = Selma::Selector.new(match_element: "")

    def selector
      SELECTOR
    end

    def handle_element(element) # never called
      element["href"] = element["href"].sub(/^http:/, "https:")
    end
  end

  def test_that_it_reports_against_empty_css
    frag = %(<a href="http://github.com">github.com</a>)
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [EmptyCSS.new]).rewrite(frag)
    assert_equal(frag, modified_doc)
  end
end

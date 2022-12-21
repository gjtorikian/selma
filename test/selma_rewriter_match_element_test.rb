# frozen_string_literal: true

require "test_helper"

class SelmaRewriterMatchElementTest < Minitest::Test
  class Handler
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element["class"] = "boldy"
    end
  end

  def test_that_it_works
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [Handler.new]).rewrite(frag)
    assert_equal('<strong class="boldy">Wow!</strong>', modified_doc)
  end

  def test_that_it_works_with_sanitizer
    sanitizer = Selma::Sanitizer.new(Selma::Sanitizer::Config::RELAXED)
    frag = "<malarky><strong><junk>Wow!</junk></strong></malarky>"
    modified_doc = Selma::Rewriter.new(sanitizer: sanitizer, handlers: [Handler.new]).rewrite(frag)
    assert_equal('<strong class="boldy">Wow!</strong>', modified_doc)
  end

  class FirstRewrite
    SELECTOR = Selma::Selector.new(match_element: "div")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element["class"] = "boldy"
    end
  end

  class SecondRewrite
    SELECTOR = Selma::Selector.new(match_element: "div")

    def selector
      SELECTOR
    end

    def handle_element(element)
      if element["class"] == "boldy"
        element["class"] += " boldy2"
      end
    end
  end

  def test_that_it_performs_handlers_in_order
    frag = "<div>Wow!</div>"
    modified_doc = Selma::Rewriter.new(sanitizer: @sanitizer, handlers: [FirstRewrite.new]).rewrite(frag)
    assert_equal('<div class="boldy">Wow!</div>', modified_doc)

    modified_doc = Selma::Rewriter.new(sanitizer: @sanitizer, handlers: [SecondRewrite.new]).rewrite(frag)
    assert_equal(frag, modified_doc)

    modified_doc = Selma::Rewriter.new(sanitizer: @sanitizer, handlers: [FirstRewrite.new, SecondRewrite.new]).rewrite(frag)
    assert_equal('<div class="boldy boldy2">Wow!</div>', modified_doc)
  end

  class GetAncestors < Minitest::Test
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def initialize
      @assertions = 0
    end

    def selector
      SELECTOR
    end

    def handle_element(element)
      ancestors = ["div", "p", "foo"]
      assert_equal(ancestors, element.ancestors)
    end
  end

  def test_that_it_knows_ancestors
    frag = "<div><p><foo><strong>Wow!</strong></foo></p></div>"
    Selma::Rewriter.new(sanitizer: nil, handlers: [GetAncestors.new]).rewrite(frag)
  end

  class GetEmptyAncestors < Minitest::Test
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def initialize
      @assertions = 0
    end

    def selector
      SELECTOR
    end

    def handle_element(element)
      ancestors = []
      assert_equal("strong", element.tag_name)
      assert_equal(ancestors, element.ancestors)
    end
  end

  def test_that_it_knows_empty_ancestors
    frag = "<strong>Wow!</strong>"
    Selma::Rewriter.new(sanitizer: nil, handlers: [GetEmptyAncestors.new]).rewrite(frag)
  end

  class AppendHtml
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element.append("<em>Gee!</em>", :as_html)
    end
  end

  def test_that_it_appends_as_html
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [AppendHtml.new]).rewrite(frag)
    assert_equal("<strong>Wow!<em>Gee!</em></strong>", modified_doc)
  end

  class AppendText
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element.append("<em>Gee!</em>", :as_text)
    end
  end

  def test_that_it_appends_as_text
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [AppendText.new]).rewrite(frag)
    assert_equal("<strong>Wow!&lt;em&gt;Gee!&lt;/em&gt;</strong>", modified_doc)
  end

  class WrapText
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element.wrap(%(<a href="www.yetto.app.com">), "</a>", :as_html)
    end
  end

  def test_that_it_wraps_as_html
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [WrapText.new]).rewrite(frag)
    assert_equal(%(<a href="www.yetto.app.com"><strong>Wow!</strong></a>), modified_doc)
  end

  class SetInnerContent
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element.set_inner_content("Gee!", :as_text)
    end
  end

  def test_that_it_sets_inner_content
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [SetInnerContent.new]).rewrite(frag)
    assert_equal(%(<strong>Gee!</strong>), modified_doc)
  end

  class RaiseError
    SELECTOR = Selma::Selector.new(match_element: "strong")

    def selector
      SELECTOR
    end

    def handle_element(element)
      raise NoMethodError, "boom!"
    end
  end

  # TODO: note that this error does not match, because
  # it's difficult to pluck from magnus
  def test_that_it_can_raise_errors
    frag = "<strong>Wow!</strong>"
    assert_raises(RuntimeError) do
      Selma::Rewriter.new(sanitizer: nil, handlers: [RaiseError.new]).rewrite(frag)
    end
  end
end

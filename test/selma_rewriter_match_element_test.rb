# frozen_string_literal: true

require "test_helper"

class SelmaRewriterMatchElementTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil(::Selma::VERSION)
  end

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
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [Handler.new]).rewrite
    assert_equal('<strong class="boldy">Wow!</strong>', modified_doc)
  end

  def test_that_it_works_with_sanitizer
    sanitizer = Selma::Sanitizer.new(Selma::Sanitizer::Config::RELAXED)
    frag = "<malarky><strong><junk>Wow!</junk></strong></malarky>"
    modified_doc = Selma::HTML.new(frag, sanitizer: sanitizer, handlers: [Handler.new]).rewrite
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
    modified_doc = Selma::HTML.new(frag, sanitizer: @sanitizer, handlers: [FirstRewrite.new]).rewrite
    assert_equal('<div class="boldy">Wow!</div>', modified_doc)

    modified_doc = Selma::HTML.new(frag, sanitizer: @sanitizer, handlers: [SecondRewrite.new]).rewrite
    assert_equal(frag, modified_doc)

    modified_doc = Selma::HTML.new(frag, sanitizer: @sanitizer, handlers: [FirstRewrite.new, SecondRewrite.new]).rewrite
    assert_equal('<div class="boldy boldy2">Wow!</div>', modified_doc)
  end
end

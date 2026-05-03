# frozen_string_literal: true

require "test_helper"

class SelmaSelectorTest < Minitest::Test
  def test_that_it_raise_against_invalid_css
    assert_raises(ArgumentError) do
      Selma::Selector.new(match_element: %(a[href=]))
    end
  end

  def test_that_it_raises_against_empty_css
    assert_raises(ArgumentError) do
      Selma::Selector.new(match_element: "")
    end
  end

  def test_that_it_accepts_nested_not_with_simple_selector
    # supported as of lol_html 2.8
    Selma::Selector.new(match_element: "div:not(:not(.foo))")
    Selma::Selector.new(match_element: ":not(:not(:not(span)))")
  end

  class NestedNotHandler
    SELECTOR = Selma::Selector.new(match_element: "a:not(:not(.keep))")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element["data-matched"] = "true"
    end
  end

  def test_nested_not_selector_matches_expected_elements
    frag = %(<a class="keep">yes</a><a class="other">no</a>)
    out = Selma::Rewriter.new(sanitizer: nil, handlers: [NestedNotHandler.new]).rewrite(frag)

    assert_equal(
      %(<a class="keep" data-matched="true">yes</a><a class="other">no</a>),
      out,
    )
  end
end

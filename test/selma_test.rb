# frozen_string_literal: true

require "test_helper"

class SelmaTest < Minitest::Test
  class Manipulator
    SELECTOR = Selma::Selector.new(match: "strong")

    def call(node)
      node["class"] = "boldy"
    end
  end

  def test_that_it_has_a_version_number
    refute_nil ::Selma::VERSION
  end

  def test_that_it_works_with_fragment
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::DocumentFragment.to_html(frag, manipulators: [Manipulator.new])
    assert_equal '<strong class="boldy">Wow!</strong>', modified_doc
  end

  class NoSelector
    def call(node)
      node["class"] = "boldy"
    end
  end

  def test_that_it_does_not_hate_missing_selector
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::DocumentFragment.to_html(frag, manipulators: [NoSelector.new])
    assert_equal frag, modified_doc
  end

  class NoCall
    SELECTOR = Selma::Selector.new(match: "strong")
  end

  def test_that_it_does_not_hate_missing_call
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::DocumentFragment.to_html(frag, manipulators: [NoCall.new])
    assert_equal frag, modified_doc
  end
  focus
  def test_that_it_works_with_sanitization
    frag = "<strong>Wow!</strong>"
    modified_doc = Selma::DocumentFragment.to_html(frag, sanitize: {})
    assert_equal "Wow!", modified_doc
  end
end

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
    modified_doc = Selma::DocumentFragment.to_html(frag, manipulators: [Manipulator])
    assert_equal '<strong class="boldy">Wow!</strong>', modified_doc
  end
end

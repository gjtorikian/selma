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
end

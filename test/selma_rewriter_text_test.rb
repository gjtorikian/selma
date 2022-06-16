# frozen_string_literal: true

require "test_helper"

class SelmaRewriterTextTest < Minitest::Test
  class TextRewriteAll
    SELECTOR = Selma::Selector.new(text: "*")

    def selector
      SELECTOR
    end

    def handle_text(text)
      debugger
      text.sub("Wow", "No way!")
    end
  end

  focus
  def test_that_it_works_for_all
    frag = "<div>Wow!</div><span>Wow!</span><a>Wow!</a>"
    modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [TextRewriteAll.new]).rewrite
    assert_equal("<div>MEOW!</div><span>MEOW!</span><a>MEOW!</a>", modified_doc)
  end

  # class TextRewriteElements
  #   SELECTOR = Selma::Selector.new(text: ["a", "div"])

  #   def selector
  #     SELECTOR
  #   end

  #   def handle_text(text)
  #     text.sub("Wow", "MEOW!")
  #   end
  # end

  # def test_that_it_works_for_multiple_elements
  #   frag = "<div>Wow!</div><span>Wow!</span><a>Wow!</a>"
  #   modified_doc = Selma::HTML.new(frag, sanitizer: nil, handlers: [TextRewrite.new]).rewrite
  #   assert_equal("<div>MEOW!</div><span>Wow!</span><a>MEOW!</a>", modified_doc)
  # end
end

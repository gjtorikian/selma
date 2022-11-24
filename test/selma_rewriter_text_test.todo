# frozen_string_literal: true

require "test_helper"

class SelmaRewriterTextTest < Minitest::Test
  class TextRewriteAll
    SELECTOR = Selma::Selector.new(match_text_within: "*")

    def selector
      SELECTOR
    end

    def handle_text(text)
      text.sub("Wow", "MEOW!")
    end
  end

  def test_that_it_works_for_all
    frag = "<div>Wow!</div><span>Wow!</span><a>Wow!</a>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextRewriteAll.new]).rewrite(frag)
    assert_equal("<div>MEOW!!</div><span>MEOW!!</span><a>MEOW!!</a>", modified_doc)
  end

  class TextRewriteElements
    SELECTOR = Selma::Selector.new(match_text_within: "a, div")

    def selector
      SELECTOR
    end

    def handle_text(text)
      text.sub("Wow", "MEOW!")
    end
  end

  def test_that_it_works_for_multiple_elements
    frag = "<div>Wow!</div><span>Wow!</span><a>Wow!</a>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextRewriteElements.new]).rewrite(frag)
    assert_equal("<div>MEOW!!</div><span>Wow!</span><a>MEOW!!</a>", modified_doc)
  end

  class TextRewriteAndMatchElements
    SELECTOR = Selma::Selector.new(match_element: "div", match_text_within: "div, p, a")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element["class"] = "neato"
    end

    def handle_text(text)
      text.sub("you", "y'all")
    end
  end

  def test_that_it_works_for_multiple_match_and_text_elements
    frag = "<div><p>Could you visit <a>this link and tell me what you think?</a> Thank you!</div>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextRewriteAndMatchElements.new]).rewrite(frag)
    assert_equal("<div class=\"neato\"><p>Could y'all visit <a>this link and tell me what y'all think?</a> Thank y'all!</div>", modified_doc)
  end

  class TextMatchAndRejectElements
    SELECTOR = Selma::Selector.new(match_text_within: "*", ignore_text_within: ["code", "pre"])

    def selector
      SELECTOR
    end

    def handle_text(text)
      text.sub("@gjtorik", "@gjtorikian")
    end
  end

  def test_that_it_works_for_text_reject
    frag = "<div><p>Hello @gjtorik: <code>@gjtorik</code></p><br/> <pre>@gjtorik</pre></div>"
    modified_doc = Selma::Rewriter.new(sanitizer: nil, handlers: [TextMatchAndRejectElements.new]).rewrite(frag)
    assert_equal("<div><p>Hello @gjtorikian: <code>@gjtorik</code></p><br/> <pre>@gjtorik</pre></div>", modified_doc)
  end
end

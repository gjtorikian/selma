# frozen_string_literal: true

require "test_helper"

class SelmaRewriterTest < Minitest::Test
  def test_max_memory_settings_must_be_correctly_set
    fragment = "12345"
    assert_raises(ArgumentError) do # missing preallocated_parsing_buffer_size
      Selma::Rewriter.new(options: { memory: { max_allowed_memory_usage: 4 } }).rewrite(fragment)
    end
  end

  class RemoveLinkClass
    SELECTOR = Selma::Selector.new(match_element: %(a:not([class="anchor"])))

    def selector
      SELECTOR
    end

    def handle_element(element)
      element.remove_attribute("class")
    end
  end

  class RemoveIdAttributes
    SELECTOR = Selma::Selector.new(match_element: %(a[id], li[id]))

    def selector
      SELECTOR
    end

    def handle_element(element)
      # footnote ids should not be removed
      return if element.tag_name == "li"
      return if element.tag_name == "a"

      # links with generated header anchors should not be removed
      return if element.tag_name == "a" && element["class"] == "anchor"

      element.remove_attribute("id")
    end
  end

  class BaseRemoveRel
    SELECTOR = Selma::Selector.new(match_element: %(a))

    def selector
      SELECTOR
    end

    def handle_element(element)
      # we allow rel="license" to support the Rel-license microformat
      # http://microformats.org/wiki/rel-license
      unless element["rel"] == "license"
        element.remove_attribute("rel")
      end
    end
  end

  def test_max_memory_settings_work
    base_text = ->(itr) {
      %|<p data-sourcepos="#{itr}:1-#{itr}:4"><sup data-sourcepos="#{itr}:1-#{itr}:4" class="footnote-ref"><a href="#fn-#{itr}" id="fnref-#{itr}" data-footnote-ref>#{itr}</a></sup></p>|
    }

    str = []
    10.times do |itr|
      str << base_text.call(itr)
    end
    html = str.join("\n")

    sanitizer_config = Selma::Sanitizer.new(Selma::Sanitizer::Config::RELAXED)
    rewriter = Selma::Rewriter.new(sanitizer: sanitizer_config, handlers: [RemoveLinkClass.new, RemoveIdAttributes.new, BaseRemoveRel.new], options: { memory: { max_allowed_memory_usage: html.length / 2, preallocated_parsing_buffer_size: html.length / 4 } })
    assert_raises(RuntimeError) do
      rewriter.rewrite(html)
    end
  end

  class ElementRewriter
    SELECTOR = Selma::Selector.new(match_text_within: "*")

    def selector
      SELECTOR
    end

    def handle_text_chunk(text)
      content = text.to_s
      return unless content.include?("@")

      html = content.gsub(/@(\w+)/, "<a href=\"https://yetto.app/\\1\" class=\"user-mention\">@\\1</a>")

      text.replace(html, as: :html)
    end
  end

  def test_rewritten_text_chunk_is_not_sanitized
    initial_html = "<p>Hey there, @gjtorikian is here.</p>"

    sanitizer_config = Selma::Sanitizer.new({
      elements: ["a", "p"],
      attributes: {
        "a" => ["href"],
      },
      protocols: {
        "a" => { "href" => ["https"] },
      },
    })
    rewriter = Selma::Rewriter.new(sanitizer: sanitizer_config, handlers: [ElementRewriter.new])
    result = rewriter.rewrite(initial_html)

    # `class` is not sanitized out
    assert_equal("<p>Hey there, <a href=\"https://yetto.app/gjtorikian\" class=\"user-mention\">@gjtorikian</a> is here.</p>", result)
  end

  def test_stress_garbage_collection
    initial_html = File.read(File.join(__dir__, "benchmark", "html", "document-sm.html")).encode("UTF-8", invalid: :replace, undef: :replace)

    sanitizer_config = Selma::Sanitizer.new({
      elements: ["a", "p"],
      attributes: {
        "a" => ["href"],
      },
      protocols: {
        "a" => { "href" => ["https"] },
      },
    })

    GC.stress = true
    # If this segfaults, then it failed the test
    rewriter = Selma::Rewriter.new(sanitizer: sanitizer_config, handlers: [ElementRewriter.new])
    rewriter.rewrite(initial_html)
    GC.stress = false
  end
end

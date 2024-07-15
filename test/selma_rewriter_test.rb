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
end

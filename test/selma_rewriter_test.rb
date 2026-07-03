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

  # Regression tests for GC safety of handler selectors.
  #
  # A handler whose #selector returns a *fresh* Selma::Selector on every call (e.g. when the
  # selector depends on runtime context and can't be a constant) has no other Ruby reference
  # once the Rewriter takes it. The Rewriter must not depend on that Ruby object surviving GC;
  # otherwise GC can free it and a later #rewrite reads freed memory (an EmptySelector panic or
  # a bogus allocation -- a fatal, uncatchable crash).
  class FreshSelectorRewriter
    def initialize(css = "a")
      @css = css
    end

    # deliberately NOT memoized / not a constant
    def selector
      Selma::Selector.new(match_element: @css)
    end

    def handle_element(element)
      element["data-touched"] = "1"
    end
  end

  # Frees the fresh selector after the Rewriter is built, then reuses the slot, then rewrites.
  def test_fresh_handler_selector_survives_gc_after_construction
    rewriter = Selma::Rewriter.new(sanitizer: nil, handlers: [FreshSelectorRewriter.new])

    GC.start(full_mark: true, immediate_sweep: true)
    1_000_000.times { Object.new } # steady-state allocation to overwrite the freed slot

    # If the selector was collected, this aborts the process instead of returning.
    result = rewriter.rewrite("<a href='https://example.com'>x</a>")

    assert_includes(result, %(data-touched="1"))
  end

  # Exercises GC *during* Rewriter construction: building many fresh selectors allocates enough
  # (under GC.stress) that an earlier, not-yet-protected selector can be collected mid-build.
  def test_fresh_handler_selectors_survive_gc_during_construction
    css = ["a", "p", "div", "span", "li", "ul", "ol", "h1", "h2", "h3"]
    html = "<div><p><a href='https://example.com'>x</a></p></div>"

    GC.stress = true
    10.times do
      # many fresh selectors widen the window in which an earlier one can be collected
      handlers = Array.new(20) { |i| FreshSelectorRewriter.new(css[i % css.size]) }
      # If a selector is freed mid-construction, this aborts (EmptySelector / try to mark T_NONE).
      Selma::Rewriter.new(sanitizer: nil, handlers: handlers).rewrite(html)
    end
  ensure
    GC.stress = false
  end
end

# frozen_string_literal: true

require "selma"
class RemoveLinkClass
  SELECTOR = Selma::Selector.new(match_element: %(a:not([class="anchor"])))

  def selector
    SELECTOR
  end

  def handle_element(element)
    element.remove_attribute("class")
  end
end

require "commonmarker"
text = "[^1]\n[^1]:\n" * 200000
html = Commonmarker.to_html(text, options: {
  extension: { footnotes: true, description_lists: true },
  render: { hardbreaks: false },
})

sanitizer_config = Selma::Sanitizer.new(Selma::Sanitizer::Config::RELAXED)
rewriter = Selma::Rewriter.new(sanitizer: sanitizer_config, handlers: [RemoveLinkClass.new])
rewriter.rewrite(html)

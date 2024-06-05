# frozen_string_literal: true

module SelmaConfig
  class HrefHandler
    SELECTOR = Selma::Selector.new(match_element: "href")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element["href"] = element["href"].sub(/^https?:/, "gopher:")
    end
  end

  class SpanHandler
    SELECTOR = Selma::Selector.new(match_text_within: "span")

    def selector
      SELECTOR
    end

    def handle_text_chunk(text_chunk)
      text_chunk.after("<div>#{text_chunk}</div>", as: :html) unless text_chunk.to_s.strip.empty?
    end
  end

  class ImgHandler
    SELECTOR = Selma::Selector.new(match_element: "img")

    def selector
      SELECTOR
    end

    def handle_element(element)
      element.remove
    end
  end
end

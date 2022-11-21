# frozen_string_literal: true

module Selma
  class HTML
    def rewrite(sanitizer: Selma::Sanitizer.new(Selma::Sanitizer::Config::DEFAULT), handlers: [])
      raise TypeError if !sanitizer.nil? && !sanitizer.is_a?(Selma::Sanitizer)

      sanitizer&.setup
      rewriter = Selma::Rewriter.new(handlers)

      selma_rewrite(sanitizer, rewriter)
    end
  end
end

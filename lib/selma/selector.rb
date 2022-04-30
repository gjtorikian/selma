# frozen_string_literal: true

module Selma
  class Selector
    attr_reader :match

    def initialize(match: nil)
      @match = match
    end
  end
end

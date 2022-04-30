# frozen_string_literal: true

module Selma
  class Selector
    attr_reader :match, :reject

    def initialize(match: nil, reject: nil)
      @match = match
      @reject = reject
    end
  end
end

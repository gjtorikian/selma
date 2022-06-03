# frozen_string_literal: true

require "test_helper"

module Selma
  class SelmaTest < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil(::Selma::VERSION)
    end
  end
end

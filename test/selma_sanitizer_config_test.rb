# frozen_string_literal: true

require "test_helper"

module Selma
  class SanitizerConfigTest < Minitest::Test
    def test_built_in_configs_should_be_deeply_frozen
      verify_deeply_frozen(Selma::Sanitizer::Config::DEFAULT)
      verify_deeply_frozen(Selma::Sanitizer::Config::BASIC)
      verify_deeply_frozen(Selma::Sanitizer::Config::RELAXED)
      verify_deeply_frozen(Selma::Sanitizer::Config::RESTRICTED)
    end

    def test_should_deeply_freeze_and_return_a_configuration_hash
      a = { one: { one_one: [0, "1", :a], one_two: false, one_three: Set.new([:a, :b, :c]) } }
      b = Selma::Sanitizer::Config.freeze_config(a)

      assert_equal(a, b)
      verify_deeply_frozen(a)
    end

    def test_should_deeply_merge_a_configuration_hash
      # Freeze to ensure that we get an error if either Hash is modified.
      a = Selma::Sanitizer::Config.freeze_config({ one: { one_one: [0, "1", :a], one_two: false,
                                                          one_three: Set.new([:a, :b, :c]), } })
      b = Selma::Sanitizer::Config.freeze_config({ one: { one_two: true, one_three: 3 }, two: 2 })

      c = Selma::Sanitizer::Config.merge(a, b)

      refute_equal(c, a)
      refute_equal(c, b)

      assert_equal({
        one: {
          one_one: [0, "1", :a],
          one_two: true,
          one_three: 3,
        },

        two: 2,
      }, c)
    end

    def test_should_raise_an_argumenterror_if_either_argument_is_not_a_hash
      assert_raises(ArgumentError) { Selma::Sanitizer::Config.merge("foo", {}) }
      assert_raises(ArgumentError) { Selma::Sanitizer::Config.merge({}, "foo") }
    end
  end
end

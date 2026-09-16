# frozen_string_literal: true

require "test_helper"

module Selma
  # Attribute sanitization works from a snapshot of the element's attributes and reads the
  # element's config without touching it; these pin the observable edges of that.
  class SanitizerAttributesTest < Minitest::Test
    def setup
      @relaxed = Selma::Rewriter.new(sanitizer: Selma::Sanitizer.new(Sanitizer::Config::RELAXED))
    end

    def test_a_rejected_duplicate_attribute_never_survives
      # every occurrence is evaluated in order; a rejected one removes the attribute outright
      assert_equal("<a>a</a>", @relaxed.rewrite(%(<a href="http://ok" href="javascript:x">a</a>)))
      assert_equal(%(<a href="http://ok">a</a>), @relaxed.rewrite(%(<a href="javascript:x" href="http://ok">a</a>)))
    end

    def test_values_are_unescaped_before_checks_and_escaped_on_output
      assert_equal(%(<a title="a &amp; b &lt;c&gt;">a</a>), @relaxed.rewrite(%(<a title=" a &amp; b <c>">a</a>)))
      assert_equal(
        %(<a href="https://x.com/?a=1&amp;b=2">a</a>),
        @relaxed.rewrite(%(<a href="  https://x.com/?a=1&b=2">a</a>)),
      )
      assert_equal(%(<a title="plain">a</a>), @relaxed.rewrite(%(<a title="plain">a</a>)))
    end

    def test_protocol_matching_is_case_insensitive_on_the_attribute_side
      assert_equal(%(<a HREF="HTTPS://x.com">a</a>), @relaxed.rewrite(%(<a HREF="HTTPS://x.com">a</a>)))
      assert_equal("<a>a</a>", @relaxed.rewrite(%(<a href="JAVASCRIPT:alert(1)">a</a>)))
    end

    def test_elements_without_their_own_config_fall_back_to_the_global_attribute_list
      sanitizer = Selma::Sanitizer.new(elements: ["p"], attributes: { all: ["title"] })
      rewriter = Selma::Rewriter.new(sanitizer: sanitizer)

      assert_equal(%(<p title="t">x</p>), rewriter.rewrite(%(<p title="t" id="i">x</p>)))
    end

    def test_custom_elements_get_their_own_attribute_and_protocol_config
      sanitizer = Selma::Sanitizer.new(
        elements: ["foo-bar", "p"],
        attributes: { "foo-bar" => ["data-x"], "p" => ["title"] },
        protocols: { "foo-bar" => { "data-x" => ["https"] } },
      )
      rewriter = Selma::Rewriter.new(sanitizer: sanitizer)

      assert_equal(
        %(<foo-bar data-x="https://ok"><p title="t">x</p></foo-bar>),
        rewriter.rewrite(%(<foo-bar data-x="https://ok" data-y="1"><p title="t" id="i">x</p></foo-bar>)),
      )
      assert_equal("<foo-bar>x</foo-bar>", rewriter.rewrite(%(<foo-bar data-x="javascript:x">x</foo-bar>)))
      assert_equal(%(<foo-bar data-x="HTTPS://ok">x</foo-bar>), rewriter.rewrite(%(<foo-bar data-x="HTTPS://ok">x</foo-bar>)))
    end

    def test_a_comment_smuggled_into_a_tag_removes_the_whole_element
      assert_equal("", @relaxed.rewrite(%(<a <!-- href="javascript:x" -->>a</a>)))
      assert_equal("", @relaxed.rewrite(%(<a <!--x>a</a>)))
    end
  end
end

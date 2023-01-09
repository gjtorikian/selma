# frozen_string_literal: true

require "test_helper"

module Selma
  class SanitizerParserTest < Minitest::Test
    def test_should_leave_valid_entities_alone
      assert_equal("&apos;&eacute;&amp;", Selma::Rewriter.new.rewrite("&apos;&eacute;&amp;"))
    end

    def test_should_leave_translate_orphaned_ampersands_alone
      assert_equal("at&t", Selma::Rewriter.new.rewrite("at&t"))
    end

    def test_should_not_add_newlines_after_tags_when_serializing_a_fragment
      sanitizer = Selma::Sanitizer.new({
        elements: ["div", "p"],
      })

      assert_equal(
        "<div>foo\n\n<p>bar</p><div>\nbaz</div></div><div>quux</div>",
        Selma::Rewriter.new(sanitizer: sanitizer).rewrite("<div>foo\n\n<p>bar</p><div>\nbaz</div></div><div>quux</div>"),
      )
    end

    def test_should_not_have_the_nokogiri_1_4_2_unterminated_script_style_element_bug
      assert_equal("foo ", Selma::Rewriter.new.rewrite("foo <script>bar"))

      assert_equal("foo ", Selma::Rewriter.new.rewrite("foo <style>bar"))
    end

    def test_ambiguous_non_tag_brackets_should_be_parsed_correctly
      assert_equal("1 > 2 and 2 < 1", Selma::Rewriter.new.rewrite("1 > 2 and 2 < 1"))

      assert_equal("OMG HAPPY BIRTHDAY! *<:-D", Selma::Rewriter.new.rewrite("OMG HAPPY BIRTHDAY! *<:-D"))
    end
  end
end

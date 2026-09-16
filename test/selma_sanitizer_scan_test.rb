# frozen_string_literal: true

require "test_helper"

module Selma
  # The sanitizer skips work it can prove is unnecessary: the text-escaping handler is only
  # registered when the input has a `<` that can land in text, and the final tagfilter pass
  # only runs when the output can contain one of its tags. These pin the behavior on both
  # sides of each gate.
  class SanitizerScanTest < Minitest::Test
    class InnerHtmlInserter
      SELECTOR = Selma::Selector.new(match_element: "p")

      def initialize(html)
        @html = html
      end

      def selector
        SELECTOR
      end

      def handle_element(element)
        element.set_inner_content(@html, as: :html)
      end
    end

    def setup
      @relaxed = Selma::Rewriter.new(sanitizer: Selma::Sanitizer.new(Sanitizer::Config::RELAXED))
    end

    def test_every_form_of_text_lt_is_still_escaped
      {
        "a<<b>c</b>" => "a&lt;<b>c</b>",
        "a< b" => "a&lt; b",
        "a<1b" => "a&lt;1b",
        "a<=b" => "a&lt;=b",
        "a<éb" => "a&lt;éb",
        "<<foo>img src=x onerror=alert(1)>" => "&lt;img src=x onerror=alert(1)>",
        "<<!---->img src=x onerror=alert(1)>" => "&lt;img src=x onerror=alert(1)>",
      }.each { |input, expected| assert_equal(expected, @relaxed.rewrite(input), input.inspect) }
    end

    def test_non_text_lt_forms_are_unchanged
      # each of these is consumed as a tag, a comment, or a bogus comment, never as text
      {
        "a<b>c</b>" => "a<b>c</b>",
        "a<!-- x -->b" => "ab",
        "a<!x>b" => "ab",
        "a<?x>b" => "ab",
        "a</ x>b" => "ab",
        "a</>b" => "a</>b",
      }.each { |input, expected| assert_equal(expected, @relaxed.rewrite(input), input.inspect) }
    end

    def test_rcdata_lt_is_escaped_regardless_of_tag_case
      rewriter = Selma::Rewriter.new(sanitizer: Selma::Sanitizer.new(elements: ["textarea", "title"]))

      assert_equal("<textarea>a&lt;b</textarea>", rewriter.rewrite("<textarea>a<b</textarea>"))
      assert_equal("<TEXTAREA>a&lt;b</TEXTAREA>", rewriter.rewrite("<TEXTAREA>a<b</TEXTAREA>"))
      assert_equal("<TITLE>a&lt;b</TITLE>", rewriter.rewrite("<TITLE>a<b</TITLE>"))
    end

    def test_unterminated_declarations_at_eof_are_dropped_whether_or_not_text_is_escaped
      rewriter = Selma::Rewriter.new(sanitizer: Selma::Sanitizer.new(allow_comments: true, elements: ["div"]))

      ["<!-- x", "<!x", "<?x", "<!DOCTYPE html"].each do |tail|
        assert_equal("foo ", rewriter.rewrite("foo #{tail}"), tail.inspect)
        assert_equal("a&lt; b foo ", rewriter.rewrite("a< b foo #{tail}"), tail.inspect)
      end
    end

    def test_final_pass_still_catches_tags_that_handlers_insert
      # the input contains no tagfilter tag at all; only the output does
      sanitizer = Selma::Sanitizer.new(elements: ["p"])
      strict = Selma::Rewriter.new(sanitizer: sanitizer, handlers: [InnerHtmlInserter.new("<script>alert(1)</script>")])

      assert_equal("<p></p>", strict.rewrite("<p>hi</p>"))

      upper = Selma::Rewriter.new(sanitizer: sanitizer, handlers: [InnerHtmlInserter.new("<SCRIPT>alert(1)</SCRIPT>")])

      assert_equal("<p></p>", upper.rewrite("<p>hi</p>"))

      # and with the tagfilter off, nothing runs at all
      loose_sanitizer = Selma::Sanitizer.new(elements: ["p"], escape_tagfilter: false)
      loose = Selma::Rewriter.new(sanitizer: loose_sanitizer, handlers: [InnerHtmlInserter.new("<script>alert(1)</script>")])

      assert_equal("<p><script>alert(1)</script></p>", loose.rewrite("<p>hi</p>"))
    end

    def test_a_rewriter_can_be_reused_across_many_inputs
      inputs = ["<p>a < b</p>", "<b>plain</b>", "<script>x</script>", "a<<i>b</i>"]
      first = inputs.map { |i| @relaxed.rewrite(i) }
      again = inputs.map { |i| @relaxed.rewrite(i) }

      assert_equal(first, again)
      assert_equal(["<p>a &lt; b</p>", "<b>plain</b>", "", "a&lt;<i>b</i>"], first)
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Selma
  class SanitizerTest < Minitest::Test
    def test_it_sanitizes_by_default
      html = "<a href='https://google.com'>here is a neat site!</a>"
      rewritten = Selma::Rewriter.new.rewrite(html)

      assert_equal("here is a neat site!", rewritten)
    end

    def test_it_can_retrieve_elements
      hash = {
        elements: ["a"],
      }
      sanitizer = Selma::Sanitizer.new(hash)

      assert_equal(["a"], sanitizer.config[:elements])
    end

    def test_it_can_keep_attributes
      hash = {
        elements: ["a"],

        attributes: {
          "a" => ["href"],
        },

        protocols: {
          "a" => { "href" => ["ftp", "http", "https", "mailto", :relative] },
        },
      }

      sanitizer = Selma::Sanitizer.new(hash)
      html = "<a href='https://google.com'>wow!</a>"
      result = Selma::Rewriter.new(sanitizer: sanitizer).rewrite(html)

      assert_equal("<a href=\"https://google.com\">wow!</a>", result)
    end

    def test_it_can_remove_attributes
      hash = {
        elements: ["a"],

        attributes: {
          "a" => ["href"],
        },

        protocols: {
          "a" => { "href" => ["ftp", "http", "https", "mailto", :relative] },
        },
      }

      sanitizer = Selma::Sanitizer.new(hash)
      html = "<a href='https://google.com' class='very'>wow!</a>"
      result = Selma::Rewriter.new(sanitizer: sanitizer).rewrite(html)

      assert_equal("<a href=\"https://google.com\">wow!</a>", result)
    end

    def test_it_can_be_turned_off
      html = '<a href="https://google.com">wow!</a>'
      assert_raises(ArgumentError) do
        Selma::Rewriter.new(sanitizer: nil).rewrite(html)
      end
    end

    def test_can_handle_non_standard_elements
      frag = <<~FRAG
        <svg height="100" width="100">
        <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
        </svg>
      FRAG

      hash = {
        elements: ["svg", "circle"],
        attributes: {
          "svg" => ["width"],
          "circle" => ["cx", "cy", "r"],
        },
      }
      sanitizer = Selma::Sanitizer.new(hash)
      result = Selma::Rewriter.new(sanitizer: sanitizer).rewrite(frag)

      assert_equal(%(<svg width="100">\n<circle cx="50" cy="50" r="40" />\n</svg>\n), result)
    end

    describe "#fragment" do
      def setup
        @sanitizer = Selma::Sanitizer.new(elements: ["html"])
      end

      def test_should_sanitize_an_html_fragment
        assert_equal(
          "Lorem ipsum dolor sitamet ",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<b>Lo<!-- comment -->rem</b> <a href="pants" title="foo">ipsum</a> <a href="http://foo.com/"><strong>dolor</strong></a> sit<br/>amet <script>alert("hello world");</script>'),
        )
      end

      def test_should_not_modify_the_input_string
        input = "<b>foo</b>"
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<b>foo</b>")

        assert_equal("<b>foo</b>", input)
      end

      def test_should_not_choke_on_fragments_containing_html_or_body
        assert_equal("foo", Selma::Rewriter.new.rewrite("<html><b>foo</b></html>"))
        assert_equal("foo", Selma::Rewriter.new.rewrite("<body><b>foo</b></body>"))
        assert_equal("foo", Selma::Rewriter.new.rewrite("<html><body><b>foo</b></body></html>"))
        assert_equal(
          "foo",
          Selma::Rewriter.new.rewrite("<!DOCTYPE html><html><body><b>foo</b></body></html>"),
        )
      end

      def test_should_not_choke_on_frozen_fragments
        assert_equal("foo", Selma::Rewriter.new.rewrite("<b>foo</b>"))
      end

      def test_should_normalize_newlines
        skip("non-essential feature")

        assert_equal(
          "a\n\n\n\n\nz",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("a\r\n\n\r\r\r\nz"),
        )
      end

      def test_should_strip_control_characters_except_ascii_whitespace
        skip("non-essential feature")

        sample_control_chars = "\u0001\u0008\u000b\u000e\u001f\u007f\u009f"
        whitespace = "\t\n\f\u0020"

        assert_equal(
          "a#{whitespace}z",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("a#{sample_control_chars}#{whitespace}z"),
        )
      end

      def test_should_strip_non_characters
        skip("non-essential feature")

        sample_non_chars = "\ufdd0\ufdef\ufffe\uffff\u{1fffe}\u{1ffff}\u{2fffe}\u{2ffff}\u{3fffe}\u{3ffff}\u{4fffe}\u{4ffff}\u{5fffe}\u{5ffff}\u{6fffe}\u{6ffff}\u{7fffe}\u{7ffff}\u{8fffe}\u{8ffff}\u{9fffe}\u{9ffff}\u{afffe}\u{affff}\u{bfffe}\u{bffff}\u{cfffe}\u{cffff}\u{dfffe}\u{dffff}\u{efffe}\u{effff}\u{ffffe}\u{fffff}\u{10fffe}\u{10ffff}"

        assert_equal("az", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("a#{sample_non_chars}z"))
      end

      def test_should_remove_the_contents_of_dangerous_elements
        assert_equal("", Selma::Rewriter.new.rewrite(%(<iframe src="https://www.youtube.com/embed/dXBohfjc4WA" width="680" height="480" allowfullscreen>hackerman</iframe>)))
      end
    end
  end
end

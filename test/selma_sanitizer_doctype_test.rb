# frozen_string_literal: true

require "test_helper"

module Selma
  class SanitizerDoctypeTest < Minitest::Test
    describe "sanitization" do
      context "when :allow_doctype is false" do
        def setup
          @sanitizer = Selma::Sanitizer.new({ allow_doctype: false, elements: ["html"] })
        end

        def test_it_removes_doctype
          assert_equal(
            "<html>foo</html>",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!DOCTYPE html><html>foo</html>"),
          )
          assert_equal("foo", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!DOCTYPE html>foo"))
        end
      end

      def test_blocks_invalid_doctypes_in_documents
        skip("non-essential feature")
        @sanitizer = Selma::Sanitizer.new({ allow_doctype: true, elements: ["html"] })

        assert_equal(
          "<!DOCTYPE html><html>foo</html>",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!DOCTYPE blah blah blah><html>foo</html>"),
        )
        assert_equal(
          "<!DOCTYPE html><html>foo</html>",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!DOCTYPE blah><html>foo</html>"),
        )
        assert_equal(
          "<!DOCTYPE html><html>foo</html>",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<!DOCTYPE html BLAH "-//W3C//DTD HTML 4.01//EN"><html>foo</html>'),
        )
        assert_equal(
          "<!DOCTYPE html><html>foo</html>",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!whatever><html>foo</html>"),
        )
      end

      context "when :allow_doctype is true" do
        def setup
          @sanitizer = Selma::Sanitizer.new({ allow_doctype: true, elements: ["html"] })
        end

        def test_it_allows_doctypes_in_documents
          assert_equal(
            "<!DOCTYPE html><html>foo</html>",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!DOCTYPE html><html>foo</html>"),
          )
          assert_equal(
            '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN"><html>foo</html>',
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN"><html>foo</html>'),
          )
          assert_equal(
            '<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n    \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\"><html>foo</html>',
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(
              '<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n    \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\"><html>foo</html>',
            ),
          )
        end

        def test_blocks_invalid_doctypes_in_documents
          skip("non-essential feature")

          assert_equal(
            "<!DOCTYPE html><html>foo</html>",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!DOCTYPE blah blah blah><html>foo</html>"
                .rewrite(sanitizer: @sanitizer)),
          )
          assert_equal(
            "<!DOCTYPE html><html>foo</html>",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!DOCTYPE blah><html>foo</html>"),
          )
          assert_equal(
            "<!DOCTYPE html><html>foo</html>",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<!DOCTYPE html BLAH "-//W3C//DTD HTML 4.01//EN"><html>foo</html>'),
          )
          assert_equal(
            "<!DOCTYPE html><html>foo</html>",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<!whatever><html>foo</html>"),
          )
        end
      end
    end
  end
end

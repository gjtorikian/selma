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
          assert_equal("<html>foo</html>",
            Selma::HTML.new("<!DOCTYPE html><html>foo</html>").rewrite(sanitizer: @sanitizer))
          assert_equal("foo", Selma::HTML.new("<!DOCTYPE html>foo").rewrite(sanitizer: @sanitizer))
        end
      end

      def test_blocks_invalid_doctypes_in_documents
        skip
        @sanitizer = Selma::Sanitizer.new({ allow_doctype: true, elements: ["html"] })
        assert_equal("<!DOCTYPE html><html>foo</html>",
          Selma::HTML.new("<!DOCTYPE blah blah blah><html>foo</html>").rewrite(sanitizer: @sanitizer))
        assert_equal("<!DOCTYPE html><html>foo</html>",
          Selma::HTML.new("<!DOCTYPE blah><html>foo</html>").rewrite(sanitizer: @sanitizer))
        assert_equal("<!DOCTYPE html><html>foo</html>",
          Selma::HTML.new('<!DOCTYPE html BLAH "-//W3C//DTD HTML 4.01//EN"><html>foo</html>',
            sanitizer: @sanitizer).rewrite)
        assert_equal("<!DOCTYPE html><html>foo</html>",
          Selma::HTML.new("<!whatever><html>foo</html>").rewrite(sanitizer: @sanitizer))
      end

      context "when :allow_doctype is true" do
        def setup
          @sanitizer = Selma::Sanitizer.new({ allow_doctype: true, elements: ["html"] })
        end

        def test_it_allows_doctypes_in_documents
          assert_equal("<!DOCTYPE html><html>foo</html>",
            Selma::HTML.new("<!DOCTYPE html><html>foo</html>").rewrite(sanitizer: @sanitizer))
          assert_equal('<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN"><html>foo</html>',
            Selma::HTML.new('<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN"><html>foo</html>').rewrite(sanitizer: @sanitizer))
          assert_equal('<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n    \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\"><html>foo</html>',
            Selma::HTML.new(
              '<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n    \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\"><html>foo</html>',
            ).rewrite(sanitizer: @sanitizer))
        end

        def test_blocks_invalid_doctypes_in_documents
          skip
          assert_equal("<!DOCTYPE html><html>foo</html>",
            Selma::HTML.new("<!DOCTYPE blah blah blah><html>foo</html>")
              .rewrite(sanitizer: @sanitizer))
          assert_equal("<!DOCTYPE html><html>foo</html>",
            Selma::HTML.new("<!DOCTYPE blah><html>foo</html>").rewrite(sanitizer: @sanitizer))
          assert_equal("<!DOCTYPE html><html>foo</html>",
            Selma::HTML.new('<!DOCTYPE html BLAH "-//W3C//DTD HTML 4.01//EN"><html>foo</html>')
            .rewrite(sanitizer: @sanitizer))
          assert_equal("<!DOCTYPE html><html>foo</html>",
            Selma::HTML.new("<!whatever><html>foo</html>").rewrite(sanitizer: @sanitizer))
        end
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module Selma
  class SanitizerCommentsTest < Minitest::Test
    describe "sanitization" do
      context "when :allow_comments is false" do
        def setup
          @sanitizer = Selma::Sanitizer.new({ allow_comments: false, elements: ["div"] })
        end

        def test_it_removes_comments
          assert_equal("foo  bar",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!-- comment --> bar"))
          assert_equal("foo ", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!-- "))
          assert_equal("foo ", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!-- - -> bar"))
          assert_equal("foo bar",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!--\n\n\n\n-->bar"))
          assert_equal("foo  --> -->bar",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!-- <!-- <!-- --> --> -->bar"))
          assert_equal("foo ",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <div <!-- comment -->>bar</div>"))

          # Special case: the comment markup is inside a <script>, which makes it
          # text content and not an actual HTML comment.
          assert_equal("",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<script><!-- comment --></script>"))

          sanitizer = Selma::Sanitizer.new({ allow_comments: false, elements: ["script"] })
          assert_equal("<script><!-- comment --></script>", Selma::Rewriter.new(sanitizer: sanitizer).rewrite("<script><!-- comment --></script>"))
        end
      end

      context "when :allow_comments is true" do
        def setup
          @sanitizer = Selma::Sanitizer.new({ allow_comments: true, elements: ["div"] })
        end

        def test_it_keeps_comments
          assert_equal("foo <!-- comment --> bar",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!-- comment --> bar"))
          assert_equal("foo <!-- ", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!-- "))
          assert_equal("foo <!-- - -> bar",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!-- - -> bar"))
          assert_equal("foo <!--\n\n\n\n-->bar",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!--\n\n\n\n-->bar"))
          assert_equal("foo <!-- <!-- <!-- --> --> -->bar",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <!-- <!-- <!-- --> --> -->bar"))

          assert_equal("foo ",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <div <!-- comment -->>bar</div>"))

          sanitizer = Selma::Sanitizer.new({ allow_comments: true, elements: ["script"] })
          assert_equal("<script><!-- comment --></script>", Selma::Rewriter.new(sanitizer: sanitizer).rewrite("<script><!-- comment --></script>"))
        end
      end
    end
  end
end

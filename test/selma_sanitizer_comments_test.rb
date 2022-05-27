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
            Selma::HTML.new("foo <!-- comment --> bar", sanitizer: @sanitizer).rewrite)
          assert_equal("foo ", Selma::HTML.new("foo <!-- ", sanitizer: @sanitizer).rewrite)
          assert_equal("foo ", Selma::HTML.new("foo <!-- - -> bar", sanitizer: @sanitizer).rewrite)
          assert_equal("foo bar",
            Selma::HTML.new("foo <!--\n\n\n\n-->bar", sanitizer: @sanitizer).rewrite)
          assert_equal("foo  --> -->bar",
            Selma::HTML.new("foo <!-- <!-- <!-- --> --> -->bar",
              sanitizer: @sanitizer).rewrite)
          assert_equal("foo <div comment>>bar</div>",
            Selma::HTML.new("foo <div <!-- comment -->>bar</div>",
              sanitizer: @sanitizer).rewrite)

          # Special case: the comment markup is inside a <script>, which makes it
          # text content and not an actual HTML comment.
          assert_equal("",
            Selma::HTML.new("<script><!-- comment --></script>",
              sanitizer: @sanitizer).rewrite)

          sanitizer = Selma::Sanitizer.new({ allow_comments: false, elements: ["script"] })
          assert_equal("<script><!-- comment --></script>", Selma::HTML.new("<script><!-- comment --></script>", sanitizer: sanitizer)
                                              .rewrite)
        end
      end

      context "when :allow_comments is true" do
        def setup
          @sanitizer = Selma::Sanitizer.new({ allow_comments: true, elements: ["div"] })
        end

        def test_it_keeps_comments
          assert_equal("foo <!-- comment --> bar",
            Selma::HTML.new("foo <!-- comment --> bar", sanitizer: @sanitizer).rewrite)
          assert_equal("foo ", Selma::HTML.new("foo <!-- ", sanitizer: @sanitizer).rewrite)
          assert_equal("foo ",
            Selma::HTML.new("foo <!-- - -> bar", sanitizer: @sanitizer).rewrite)
          assert_equal("foo <!--\n\n\n\n-->bar",
            Selma::HTML.new("foo <!--\n\n\n\n-->bar", sanitizer: @sanitizer).rewrite)
          assert_equal("foo <!-- <!-- <!-- --> --> -->bar",
            Selma::HTML.new("foo <!-- <!-- <!-- --> --> -->bar",
              sanitizer: @sanitizer).rewrite)

          assert_equal("foo <div>&gt;bar</div>",
            Selma::HTML.new("foo <div <!-- comment -->>bar</div>",
                                          sanitizer: @sanitizer).rewrite)

          sanitizer = Selma::Sanitizer.new({ allow_comments: true, elements: ["script"] })
          assert_equal("<script><!-- comment --></script>", Selma::HTML.new("<script><!-- comment --></script>", sanitizer: sanitizer)
                                              .rewrite)
        end
      end
    end
  end
end

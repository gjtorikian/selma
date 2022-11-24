# frozen_string_literal: true

require "test_helper"

module Selma
  class SanitizerTest < Minitest::Test
    describe "sanitize" do
      context "Default config" do
        def test_remove_non_allowlisted_elements_leaving_safe_contents_behind
          assert_equal("foo bar baz quux",
            Selma::Rewriter.new.rewrite('foo <b>bar</b> <strong><a href="#a">baz</a></strong> quux'))
          assert_equal("", Selma::Rewriter.new.rewrite('<script>alert("<xss>");</script>'))
          assert_equal("", Selma::Rewriter.new.rewrite('<<script>script>alert("<xss>");</<script>>'))
          assert_equal('< script <>> alert("");</script>',
            Selma::Rewriter.new.rewrite('< script <>> alert("<xss>");</script>'))
        end

        def test_should_surround_the_contents_of_whitespace_elements_with_space_characters_when_removing_the_element
          assert_equal("foo bar baz", Selma::Rewriter.new.rewrite("foo<div>bar</div>baz"))
          assert_equal("foo bar baz", Selma::Rewriter.new.rewrite("foo<br>bar<br>baz"))
          assert_equal("foo bar baz", Selma::Rewriter.new.rewrite("foo<hr>bar<hr>baz"))
        end

        def test_should_not_choke_on_several_instances_of_the_same_element_in_a_row
          assert_equal("",
            Selma::Rewriter.new.rewrite('<img src="http://www.google.com/intl/en_ALL/images/logo.gif"><img src="http://www.google.com/intl/en_ALL/images/logo.gif"><img src="http://www.google.com/intl/en_ALL/images/logo.gif"><img src="http://www.google.com/intl/en_ALL/images/logo.gif">'))
        end

        def test_should_not_preserve_the_content_of_removed_iframe_elements
          assert_equal("", Selma::Rewriter.new.rewrite("<iframe>hello! <script>alert(0)</script></iframe>"))
        end

        def test_should_not_preserve_the_content_of_removed_math_elements
          assert_equal("", Selma::Rewriter.new.rewrite("<math>hello! <script>alert(0)</script></math>"))
        end

        def test_should_not_preserve_the_content_of_removed_noembed_elements
          assert_equal("", Selma::Rewriter.new.rewrite("<noembed>hello! <script>alert(0)</script></noembed>"))
        end

        def test_should_not_preserve_the_content_of_removed_noframes_elements
          assert_equal("",
            Selma::Rewriter.new.rewrite("<noframes>hello! <script>alert(0)</script></noframes>"))
        end

        def test_should_not_preserve_the_content_of_removed_noscript_elements
          assert_equal("",
            Selma::Rewriter.new.rewrite("<noscript>hello! <script>alert(0)</script></noscript>"))
        end

        def test_should_not_preserve_the_content_of_removed_plaintext_elements
          assert_equal("", Selma::Rewriter.new.rewrite("<plaintext>hello! <script>alert(0)</script>"))
        end

        def test_should_not_preserve_the_content_of_removed_script_elements
          # NOTE: this gets confused by the embedding
          assert_equal("</script>", Selma::Rewriter.new.rewrite("<script>hello! <script>alert(0)</script></script>"))
        end

        def test_should_not_preserve_the_content_of_removed_style_elements
          assert_equal("", Selma::Rewriter.new.rewrite("<style>hello! <script>alert(0)</script></style>"))
        end

        def test_should_not_preserve_the_content_of_removed_svg_elements
          assert_equal("", Selma::Rewriter.new.rewrite("<svg>hello! <script>alert(0)</script></svg>"))
        end

        def test_should_not_preserve_the_content_of_removed_xmp_elements
          assert_equal("", Selma::Rewriter.new.rewrite("<xmp>hello! <script>alert(0)</script></xmp>"))
        end

        STRINGS.each do |name, data|
          define_method :"test_should_clean_#{name}_HTML" do
            assert_equal(data[:default], Selma::Rewriter.new.rewrite(data[:html]))
          end
        end

        PROTOCOLS.each do |name, data|
          define_method :"test_should_not_allow_#{name}" do
            assert_equal(data[:default], Selma::Rewriter.new.rewrite(data[:html]))
          end
        end
      end

      context "Restricted config" do
        def setup
          @sanitizer = Selma::Sanitizer.new(Selma::Sanitizer::Config::RESTRICTED)
        end

        STRINGS.each do |name, data|
          define_method :"test_should_clean_#{name}_HTML" do
            assert_equal(data[:restricted], Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(data[:html]))
          end
        end

        PROTOCOLS.each do |name, data|
          define_method :"test_should_not_allow_#{name}" do
            assert_equal(data[:restricted], Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(data[:html]))
          end
        end
      end

      context "Basic config" do
        def setup
          @sanitizer = Selma::Sanitizer.new(Selma::Sanitizer::Config::BASIC)
        end

        def test_should_not_choke_on_valueless_attributes
          assert_equal("foo <a>foo</a> bar",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("foo <a href>foo</a> bar"))
        end

        def test_should_downcase_attribute_names_when_checking
          assert_equal("<a>bar</a>",
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<a HREF="javascript:alert(\'foo\')">bar</a>'))
        end

        STRINGS.each do |name, data|
          define_method :"test_should_clean_#{name}_HTML" do
            assert_equal(data[:basic], Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(data[:html]))
          end
        end

        PROTOCOLS.each do |name, data|
          define_method :"test_should_not_allow_#{name}" do
            assert_equal(data[:basic], Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(data[:html]))
          end
        end
      end

      context "Relaxed config" do
        def setup
          @sanitizer = Selma::Sanitizer.new(Selma::Sanitizer::Config::RELAXED)
        end

        def test_should_encode_special_chars_in_attribute_values
          assert_equal('<a href="http://example.com" title="&lt;b&gt;éxamples&lt;&#47;b&gt; &amp; things">foo</a>',
            Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<a href="http://example.com" title="<b>éxamples</b> & things">foo</a>'))
        end

        STRINGS.each do |name, data|
          define_method :"test_should_clean_#{name}_HTML" do
            assert_equal(data[:relaxed], Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(data[:html]))
          end
        end

        PROTOCOLS.each do |name, data|
          define_method :"test_should_not_allow_#{name}" do
            assert_equal(data[:relaxed], Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(data[:html]))
          end
        end
      end

      context "Custom config" do
        def test_should_allow_attributes_on_all_elements_if_allowlisted_under_all
          input = "<p>bar</p>"
          Selma::Rewriter.new.rewrite(input)
          assert_equal(" bar ", Selma::Rewriter.new.rewrite(input))

          sanitizer = Selma::Sanitizer.new({
            elements: ["p"],
            attributes: { all: ["class"] },
          })
          assert_equal(input, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))

          sanitizer = Selma::Sanitizer.new({
            elements: ["p"],
            attributes: { "div" => ["class"] },
          })
          assert_equal("<p>bar</p>", Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))

          sanitizer = Selma::Sanitizer.new({
            elements: ["p"],
            attributes: { "p" => ["title"], :all => ["class"] },
          })
          assert_equal(input, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))
        end

        def test_should_not_allow_relative_urls_when_relative_urls_arent_allowlisted
          input = '<a href="/foo/bar">Link</a>'

          sanitizer = Selma::Sanitizer.new({
            elements: ["a"],
            attributes: { "a" => ["href"] },
            protocols: { "a" => { "href" => ["http"] } },
          })
          assert_equal("<a>Link</a>", Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))
        end

        def test_should_allow_relative_urls_containing_colons_when_the_colon_is_not_in_the_first_path_segment
          input = '<a href="/wiki/Special:Random">Random Page</a>'

          sanitizer = Selma::Sanitizer.new({
            elements: ["a"],
            attributes: { "a" => ["href"] },
            protocols: { "a" => { "href" => [:relative] } },
          })
          assert_equal(input, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))
        end

        def test_should_allow_relative_urls_containing_colons_when_the_colon_is_part_of_an_anchor
          input = '<a href="#fn:1">Footnote 1</a>'

          sanitizer = Selma::Sanitizer.new({
            elements: ["a"],
            attributes: { "a" => ["href"] },
            protocols: { "a" => { "href" => [:relative] } },
          })
          assert_equal(input, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))

          input = '<a href="somepage#fn:1">Footnote 1</a>'

          sanitizer = Selma::Sanitizer.new({
            elements: ["a"],
            attributes: { "a" => ["href"] },
            protocols: { "a" => { "href" => [:relative] } },
          })
          assert_equal(input, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))

          input = '<a href="fn:1">Footnote 1</a>'

          sanitizer = Selma::Sanitizer.new({
            elements: ["a"],
            attributes: { "a" => ["href"] },
            protocols: { "a" => { "href" => [:relative] } },
          })
          assert_equal("<a>Footnote 1</a>", Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))
        end

        def test_should_remove_the_contents_of_filtered_nodes_when_remove_contents_is_true
          sanitizer = Selma::Sanitizer.new({ remove_contents: true })
          assert_equal("foo bar ",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite("foo bar <div>baz<span>quux</span></div>"))
        end

        def test_remove_the_contents_of_specified_nodes_when_remove_contents_is_an_array_or_set_of_element_names_as_strings
          sanitizer = Selma::Sanitizer.new({ remove_contents: ["script", "span"] })
          assert_equal("foo bar baz hi",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('foo bar <div>baz<span>quux</span> <b>hi</b><script>alert("hello!");</script></div>'))

          sanitizer = Selma::Sanitizer.new({ remove_contents: Set.new(["script", "span"]) })
          assert_equal("foo bar baz hi",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('foo bar <div>baz<span>quux</span> <b>hi</b><script>alert("hello!");</script></div>'))
        end

        def test_should_remove_the_contents_of_specified_nodes_when_remove_contents_is_an_array_or_set_of_element_names_as_symbols
          sanitizer = Selma::Sanitizer.new({ remove_contents: [:script, :span] })
          assert_equal("foo bar baz hi",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('foo bar <div>baz<span>quux</span> <b>hi</b><script>alert("hello!");</script></div>'))

          sanitizer = Selma::Sanitizer.new({ remove_contents: Set.new([:script, :span]) })
          assert_equal("foo bar baz hi",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('foo bar <div>baz<span>quux</span> <b>hi</b><script>alert("hello!");</script></div>'))
        end

        def test_should_remove_the_contents_of_allowlisted_iframes
          sanitizer = Selma::Sanitizer.new({ elements: ["iframe"] })
          assert_equal("<iframe> </iframe>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite("<iframe>hi <script>hello</script></iframe>"))
        end

        def test_should_not_allow_arbitrary_html5_data_attributes_by_default
          sanitizer = Selma::Sanitizer.new({ elements: ["b"] })
          assert_equal("<b></b>", Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b data-foo="bar"></b>'))

          sanitizer = Selma::Sanitizer.new({ attributes: { "b" => ["class"] },
                                             elements: ["b"], })
          assert_equal('<b class="foo"></b>',
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b class="foo" data-foo="bar"></b>'))
        end

        def test_should_allow_arbitrary_html5_data_attributes
          sanitizer = Selma::Sanitizer.new(
            attributes: { "b" => ["data-foo", "data-bar"] },
            elements: ["b"],
          )

          str = '<b data-foo="valid" data-bar="valid"></b>'
          assert_equal(str, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(str))

          assert_equal("<b></b>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b data-="invalid"></b>'))

          assert_equal("<b></b>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b data-xml="invalid"></b>'))

          assert_equal("<b></b>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b data-xmlfoo="invalid"></b>'))

          assert_equal("<b></b>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b data-f:oo="valid"></b>'))

          assert_equal("<b></b>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b data-f:oo="valid"></b>'))

          assert_equal("<b></b>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b data-f/oo="partial"></b>'))

          assert_equal("<b></b>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<b data-éfoo="valid"></b>'))
        end

        def test_should_handle_protocols_correctly_regardless_of_case
          input = '<a href="hTTpS://foo.com/">Text</a>'

          sanitizer = Selma::Sanitizer.new(
            elements: ["a"],
            attributes: { "a" => ["href"] },
            protocols: { "a" => { "href" => ["https"] } },
          )

          assert_equal(input, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))

          input = '<a href="mailto:someone@example.com?Subject=Hello">Text</a>'

          assert_equal("<a>Text</a>", Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))
        end

        def test_should_sanitize_protocols_in_data_attributes_even_if_data_attributes_are_generically_allowed
          input = '<a data-url="mailto:someone@example.com">Text</a>'

          sanitizer = Selma::Sanitizer.new(
            elements: ["a"],
            attributes: { "a" => ["data-url"] },
            protocols: { "a" => { "data-url" => ["https"] } },
          )

          assert_equal("<a>Text</a>", Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))

          sanitizer = Selma::Sanitizer.new(
            elements: ["a"],
            attributes: { "a" => ["data-url"] },
            protocols: { "a" => { "data-url" => ["mailto"] } },
          )

          assert_equal(input, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(input))
        end

        def test_should_prevent_meta_tags_from_being_used_to_set_a_non_utf8_charset
          sanitizer = Selma::Sanitizer.new(
            elements: ["html", "head", "meta", "body"],
            attributes: { "meta" => ["charset"] },
          )

          assert_equal("<html><head><meta charset=\"utf-8\"></head><body>Howdy!</body></html>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<html><head><meta charset="utf-8"></head><body>Howdy!</body></html>'))

          sanitizer = Selma::Sanitizer.new(
            elements: ["html", "meta"],
            attributes: { "meta" => ["charset"] },
          )

          assert_equal("<html><meta charset=\"utf-8\">Howdy!</html>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<html><meta charset="utf-8">Howdy!</html>'))

          sanitizer = Selma::Sanitizer.new(
            elements: ["html", "meta"],
            attributes: { "meta" => ["charset"] },
          )

          assert_equal("<html><meta charset=\"utf-8\">Howdy!</html>",
            Selma::Rewriter.new(sanitizer: sanitizer).rewrite('<html><meta charset="us-ascii">Howdy!</html>'))
        end

        def test_should_prevent_meta_tags_from_being_used_to_set_a_non_utf8_charset_when_charset_other_values
          skip
          sanitizer = Selma::Sanitizer.new(
            elements: ["html", "meta"],
            attributes: { "meta" => ["content", "http-equiv"] },
          )

          result = "<!DOCTYPE html><html><meta http-equiv=\"content-type\" content=\" text/html;charset=utf-8\">Howdy!</html>"
          assert_equal(result, Selma::Sanitizer.new(sanitizer: sanitizer).rewrite(
              '<html><meta http-equiv="content-type" content=" text/html; charset=us-ascii">Howdy!</html>',
            ))

          sanitizer = Selma::Sanitizer.new(
            elements: ["html", "meta"],
            attributes: { "meta" => ["content", "http-equiv"] },
          )

          result = '<html><meta http-equiv=\"Content-Type\" content=\"text/plain;charset=utf-8\">Howdy!</html>'
          assert_equal(
            result, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(
              '<html><meta http-equiv="Content-Type" content="text/plain;charset = us-ascii">Howdy!</html>',
            )
          )
        end

        def test_should_not_modify_meta_tags_that_already_set_a_utf8_charset
          skip
          sanitizer = Selma::Sanitizer.new(elements: ["html", "head", "meta", "body"],
            attributes: { "meta" => ["content", "http-equiv"] })

          result = '<html><head><meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\"></head><body>Howdy!</body></html>'
          assert_equal(
            result, Selma::Rewriter.new(sanitizer: sanitizer).rewrite(
              '<html><head><meta http-equiv="Content-Type" content="text/html;charset=utf-8"></head><body>Howdy!</body></html>', sanitizer: sanitizer
            )
          )
        end
      end
    end
  end
end

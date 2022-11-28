# frozen_string_literal: true

require "test_helper"

module Selma
  class SanitizerMaliciousHtmlTest < Minitest::Test
    def setup
      @sanitizer = Selma::Sanitizer.new(Sanitizer::Config::RELAXED)
    end

    def test_should_not_allow_script_injection_via_conditional_comments
      assert_equal("",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<!--[if gte IE 4]>\n<script>alert('XSS');</script>\n<![endif]-->]))
    end

    def test_should_escape_erb_style_tags
      skip
      assert_equal("&lt;% naughty_ruby_code %&gt;",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<% naughty_ruby_code %>"))

      assert_equal("&lt;%= naughty_ruby_code %&gt;",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<%= naughty_ruby_code %>"))
    end

    def test_should_remove_php_style_tags
      skip
      assert_equal("", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<? naughtyPHPCode(); ?>"))

      assert_equal("", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<?= naughtyPHPCode(); ?>"))
    end

    def test_should_not_be_possible_to_inject_js_via_a_malformed_event_attribute
      assert_equal("<html><head></head><body></body></html>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<html><head></head><body onload!#$%&()*~+-_.,:;?@[/|\\]^`=alert("XSS")></body></html>'))
    end

    def test_should_not_be_possible_to_inject_an_iframe_using_an_improperly_closed_tag
      assert_equal("",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%(<iframe src=http://ha.ckers.org/scriptlet.html <)))
    end

    def test_should_not_be_possible_to_inject_js_via_an_unquoted_img_src_attribute
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<img src=javascript:alert("XSS")>'))
    end

    def test_should_not_be_possible_to_inject_js_using_grave_accents_as_img_src_delimiters
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<img src=`javascript:alert("XSS")`>'))
    end

    def test_should_not_be_possible_to_inject_script_via_a_malformed_img_tag
      assert_equal('<img>">',
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<img """><script>alert("XSS")</script>">'))
    end

    def test_should_not_be_possible_to_inject_protocol_based_js
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(
          "<img src=&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;&#97;&#108;&#101;&#114;&#116;&#40;&#39;&#88;&#83;&#83;&#39;&#41;>",
        ))

      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(
          "<img src=&#0000106&#0000097&#0000118&#0000097&#0000115&#0000099&#0000114&#0000105&#0000112&#0000116&#0000058&#0000097&#0000108&#0000101&#0000114&#0000116&#0000040&#0000039&#0000088&#0000083&#0000083&#0000039&#0000041>",
        ))

      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(
          "<img src=&#x6A&#x61&#x76&#x61&#x73&#x63&#x72&#x69&#x70&#x74&#x3A&#x61&#x6C&#x65&#x72&#x74&#x28&#x27&#x58&#x53&#x53&#x27&#x29>",
        ))

      # Encoded tab character.
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="jav&#x09;ascript:alert('XSS');">]))

      # Encoded newline.
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="jav&#x0A;ascript:alert('XSS');">]))

      # Encoded carriage return.
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="jav&#x0D;ascript:alert('XSS');">]))

      # Null byte.
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src=java\0script:alert("XSS")>]))

      # Spaces plus meta char.
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src=" &#14;  javascript:alert('XSS');">]))

      # Mixed spaces and tabs.
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="j\na v\tascript://alert('XSS');">]))
    end

    def test_should_not_be_possible_to_inject_protocol_based_js_via_whitespace
      assert_equal("<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="jav\tascript:alert('XSS');">]))
    end

    # tag never resolves the way it might in eg. Gumbo
    def test_should_not_be_possible_to_inject_js_using_a_half_open_img_tag
      assert_equal("",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="javascript:alert('XSS')"]))
    end

    def test_should_not_be_possible_to_inject_script_using_a_malformed_non_alphanumeric_tag_name
      assert_equal("",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<script/xss src="http://ha.ckers.org/xss.js">alert(1)</script>]))
    end

    def test_should_not_be_possible_to_inject_script_via_extraneous_open_brackets
      assert_equal("",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<<script>alert("XSS");//<</script>]))
    end

    # https://github.com/rgrove/sanitize/security/advisories/GHSA-p4x4-rw2p-8j8m

    def test_prevents_a_sanitization_bypass_via_carefully_crafted_foreign_content
      ["iframe", "noembed", "noframes", "noscript", "plaintext", "script", "style", "xmp"].each do |tag_name|
        assert_equal("",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<math><#{tag_name}>/*&lt;/#{tag_name}&gt;&lt;img src onerror=alert(1)>*/]))

        assert_equal("",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<svg><#{tag_name}>/*&lt;/#{tag_name}&gt;&lt;img src onerror=alert(1)>*/]))
      end
    end
  end
end

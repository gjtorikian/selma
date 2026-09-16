# frozen_string_literal: true

require "test_helper"

module Selma
  class LtProbeHandler
    SELECTOR = Selma::Selector.new(match_text_within: "p")

    attr_reader :seen

    def initialize
      @seen = []
    end

    def selector
      SELECTOR
    end

    def handle_text_chunk(text)
      @seen << text.to_s
    end
  end

  class LtReplaceHandler
    SELECTOR = Selma::Selector.new(match_text_within: "p")

    def initialize(replacement, as:)
      @replacement = replacement
      @as = as
    end

    def selector
      SELECTOR
    end

    def handle_text_chunk(text)
      text.replace(@replacement, as: @as) if text.to_s.include?("<")
    end
  end

  class SanitizerMaliciousHtmlTest < Minitest::Test
    def setup
      @sanitizer = Selma::Sanitizer.new(Sanitizer::Config::RELAXED)
    end

    def test_should_not_allow_script_injection_via_conditional_comments
      assert_equal(
        "",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<!--[if gte IE 4]>\n<script>alert('XSS');</script>\n<![endif]-->]),
      )
    end

    def test_should_escape_erb_style_tags
      skip("non-essential feature")

      assert_equal(
        "&lt;% naughty_ruby_code %&gt;",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<% naughty_ruby_code %>"),
      )

      assert_equal(
        "&lt;%= naughty_ruby_code %&gt;",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<%= naughty_ruby_code %>"),
      )
    end

    def test_should_remove_php_style_tags
      skip("non-essential feature")

      assert_equal("", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<? naughtyPHPCode(); ?>"))

      assert_equal("", Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<?= naughtyPHPCode(); ?>"))
    end

    def test_should_not_be_possible_to_inject_js_via_a_malformed_event_attribute
      assert_equal(
        "<html><head></head><body></body></html>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<html><head></head><body onload!#$%&()*~+-_.,:;?@[/|\\]^`=alert("XSS")></body></html>'),
      )
    end

    def test_should_not_be_possible_to_inject_an_iframe_using_an_improperly_closed_tag
      assert_equal(
        "",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%(<iframe src=http://ha.ckers.org/scriptlet.html <)),
      )
    end

    def test_should_not_be_possible_to_inject_js_via_an_unquoted_img_src_attribute
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<img src=javascript:alert("XSS")>'),
      )
    end

    def test_should_not_be_possible_to_inject_js_using_grave_accents_as_img_src_delimiters
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<img src=`javascript:alert("XSS")`>'),
      )
    end

    def test_should_not_be_possible_to_inject_script_via_a_malformed_img_tag
      assert_equal(
        '<img>">',
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite('<img """><script>alert("XSS")</script>">'),
      )
    end

    def test_should_not_be_possible_to_inject_protocol_based_js
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(
          "<img src=&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;&#97;&#108;&#101;&#114;&#116;&#40;&#39;&#88;&#83;&#83;&#39;&#41;>",
        ),
      )

      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(
          "<img src=&#0000106&#0000097&#0000118&#0000097&#0000115&#0000099&#0000114&#0000105&#0000112&#0000116&#0000058&#0000097&#0000108&#0000101&#0000114&#0000116&#0000040&#0000039&#0000088&#0000083&#0000083&#0000039&#0000041>",
        ),
      )

      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(
          "<img src=&#x6A&#x61&#x76&#x61&#x73&#x63&#x72&#x69&#x70&#x74&#x3A&#x61&#x6C&#x65&#x72&#x74&#x28&#x27&#x58&#x53&#x53&#x27&#x29>",
        ),
      )

      # Encoded tab character.
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="jav&#x09;ascript:alert('XSS');">]),
      )

      # Encoded newline.
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="jav&#x0A;ascript:alert('XSS');">]),
      )

      # Encoded carriage return.
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="jav&#x0D;ascript:alert('XSS');">]),
      )

      # Null byte.
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src=java\0script:alert("XSS")>]),
      )

      # Spaces plus meta char.
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src=" &#14;  javascript:alert('XSS');">]),
      )

      # Mixed spaces and tabs.
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="j\na v\tascript://alert('XSS');">]),
      )
    end

    def test_should_not_be_possible_to_inject_protocol_based_js_via_whitespace
      assert_equal(
        "<img>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="jav\tascript:alert('XSS');">]),
      )
    end

    # tag never resolves the way it might in eg. Gumbo
    def test_should_not_be_possible_to_inject_js_using_a_half_open_img_tag
      assert_equal(
        "",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<img src="javascript:alert('XSS')"]),
      )
    end

    def test_should_not_be_possible_to_inject_script_using_a_malformed_non_alphanumeric_tag_name
      assert_equal(
        "",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<script/xss src="http://ha.ckers.org/xss.js">alert(1)</script>]),
      )
    end

    def test_should_not_be_possible_to_inject_script_via_extraneous_open_brackets
      assert_equal(
        "&lt;",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<<script>alert("XSS");//<</script>]),
      )
    end

    # https://github.com/rgrove/sanitize/security/advisories/GHSA-p4x4-rw2p-8j8m

    def test_prevents_a_sanitization_bypass_via_carefully_crafted_foreign_content
      ["iframe", "noembed", "noframes", "noscript", "plaintext", "script", "style", "xmp"].each do |tag_name|
        assert_equal(
          "",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<math><#{tag_name}>/*&lt;/#{tag_name}&gt;&lt;img src onerror=alert(1)>*/]),
        )

        assert_equal(
          "",
          Selma::Rewriter.new(sanitizer: @sanitizer).rewrite(%[<svg><#{tag_name}>/*&lt;/#{tag_name}&gt;&lt;img src onerror=alert(1)>*/]),
        )
      end
    end

    # https://github.com/gjtorikian/selma/security/advisories/GHSA-4xw4-3jxj-c23p

    def test_prevents_mutation_xss_via_stray_lt_before_a_removed_node
      # the original report
      sanitizer = Selma::Sanitizer.new(elements: ["p"], remove_contents: true)

      assert_equal(
        "&lt;img src=x onerror=alert(1)>",
        Selma::Rewriter.new(sanitizer: sanitizer).rewrite("<<script></script>img src=x onerror=alert(1)>"),
      )

      payloads = [
        "<<script></script>img src=x onerror=alert(1)>", # removed with contents
        "<<!---->img src=x onerror=alert(1)>",           # removed comment
        "<<foo>img src=x onerror=alert(1)>",             # unknown element
        "<<div></div>img src=x onerror=alert(1)>",       # element removed, contents kept
      ]
      configs = {
        default: Sanitizer::Config::DEFAULT,
        restricted: Sanitizer::Config::RESTRICTED,
        basic: Sanitizer::Config::BASIC,
        relaxed: Sanitizer::Config::RELAXED,
      }

      payloads.each do |payload|
        configs.each do |name, config|
          output = Selma::Rewriter.new(sanitizer: Selma::Sanitizer.new(config)).rewrite(payload)

          refute_includes(output, "<img", "#{payload.inspect} under #{name} produced #{output.inspect}")
          assert_includes(output, "&lt;", "#{payload.inspect} under #{name} produced #{output.inspect}")
        end
      end

      # a fused comment opener must not be able to swallow what follows it
      assert_equal(
        "&lt;!-- <b>hidden</b>",
        Selma::Rewriter.new(sanitizer: @sanitizer).rewrite("<<foo>!-- <b>hidden</b>"),
      )

      # the second-pass tagfilter is no longer the only thing standing in the way
      sanitizer = Selma::Sanitizer.new(elements: ["p"], escape_tagfilter: false)

      assert_equal(
        "&lt;script>alert(1)</script>",
        Selma::Rewriter.new(sanitizer: sanitizer).rewrite("<<foo>script>alert(1)</script>"),
      )
    end

    def test_escapes_literal_lt_in_text_without_touching_entities_or_raw_text
      rewriter = Selma::Rewriter.new(sanitizer: @sanitizer)

      assert_equal("<p>a &lt; b</p>", rewriter.rewrite("<p>a < b</p>"))
      assert_equal("<p>1 &lt; 2 &lt; 3</p>", rewriter.rewrite("<p>1 < 2 < 3</p>"))

      # already-encoded text is not double-encoded
      assert_equal("<p>a &lt; b &amp; c &gt; d</p>", rewriter.rewrite("<p>a &lt; b &amp; c &gt; d</p>"))

      # `>` on its own cannot open a tag and is left alone
      assert_equal("<p>a > b</p>", rewriter.rewrite("<p>a > b</p>"))

      # raw-text contexts do not decode entities, so they are left untouched
      assert_equal("<style>a<b{color:red}</style>", rewriter.rewrite("<style>a<b{color:red}</style>"))

      # RCDATA decodes entities, so escaping there is lossless
      textarea = Selma::Rewriter.new(sanitizer: Selma::Sanitizer.new(elements: ["textarea"]))

      assert_equal("<textarea>a &lt; b</textarea>", textarea.rewrite("<textarea>a < b</textarea>"))
    end

    def test_text_handlers_still_see_the_original_text_and_their_replacements_win
      probe = LtProbeHandler.new

      assert_equal(
        "<p>a &lt; b</p>",
        Selma::Rewriter.new(sanitizer: @sanitizer, handlers: [probe]).rewrite("<p>a < b</p>"),
      )
      assert_equal("a < b", probe.seen.join)

      as_text = LtReplaceHandler.new("x <y> z", as: :text)

      assert_equal(
        "<p>a x &lt;y&gt; z b</p>",
        Selma::Rewriter.new(sanitizer: @sanitizer, handlers: [as_text]).rewrite("<p>a < b</p>"),
      )

      as_html = LtReplaceHandler.new("<b>!</b>", as: :html)

      assert_equal(
        "<p>a <b>!</b> b</p>",
        Selma::Rewriter.new(sanitizer: @sanitizer, handlers: [as_html]).rewrite("<p>a < b</p>"),
      )

      # no sanitizer means no escaping: the rewriter alone stays byte-faithful
      assert_equal("<p>a < b</p>", Selma::Rewriter.new(sanitizer: nil, handlers: [probe]).rewrite("<p>a < b</p>"))
    end
  end
end

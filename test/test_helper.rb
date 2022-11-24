# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "selma"

require "minitest/autorun"
require "minitest/focus"
require "minitest-spec-context"
require "minitest/pride"

require "amazing_print"

def verify_deeply_frozen(config)
  assert_predicate(config, :frozen?)

  case config
  when Hash
    config.each_value { |v| verify_deeply_frozen(v) }
  when Set, Array
    config.each { |v| verify_deeply_frozen(v) }
  end
end

def nest_html_content(html_content, depth)
  "#{"<span>" * depth}#{html_content}#{"</span>" * depth}"
end

STRINGS = {
  basic: {
    html: '<b>Lo<!-- comment -->rem</b> <a href="pants" title="foo" style="text-decoration: underline;">ipsum</a> <a href="http://foo.com/"><strong>dolor</strong></a> sit<br/>amet <style>.foo { color: #fff; }</style> <script>alert("hello world");</script>',
    default: "Lorem ipsum dolor sit amet  ",
    restricted: "<b>Lorem</b> ipsum <strong>dolor</strong> sit amet  ",
    basic: '<b>Lorem</b> <a>ipsum</a> <a href="http://foo.com/"><strong>dolor</strong></a> sit<br/>amet  ',
    relaxed: '<b>Lorem</b> <a title="foo" style="text-decoration: underline;">ipsum</a> <a href="http://foo.com/"><strong>dolor</strong></a> sit<br/>amet <style>.foo { color: #fff; }</style> ',
  },

  malformed: {
    html: 'Lo<!-- comment -->rem</b> <a href=pants title="foo>ipsum <a href="http://foo.com/"><strong>dolor</a></strong> sit<br/>amet <script>alert("hello world");',
    default: "Lorem</b> dolor</strong> sit amet ",
    restricted: "Lorem</b> <strong>dolor</strong> sit amet ",
    basic: "Lorem</b> <a><strong>dolor</a></strong> sit<br/>amet ",
    relaxed: 'Lorem</b> <a title="foo&gt;ipsum &lt;a href="><strong>dolor</a></strong> sit<br/>amet ',
  },

  unclosed: {
    html: "<p>a</p><blockquote>b",
    default: " a  b",
    restricted: " a  b",
    basic: "<p>a</p><blockquote>b",
    relaxed: "<p>a</p><blockquote>b",
  },

  malicious: {
    html: '<b>Lo<!-- comment -->rem</b> <a href="javascript:pants" title="foo">ipsum</a> <a href="http://foo.com/"><strong>dolor</strong></a> sit<br/>amet <<foo>script>alert("hello world");</script>',
    default: "Lorem ipsum dolor sit amet ",
    restricted: "<b>Lorem</b> ipsum <strong>dolor</strong> sit amet ",
    basic: '<b>Lorem</b> <a>ipsum</a> <a href="http://foo.com/"><strong>dolor</strong></a> sit<br/>amet ',
    relaxed: '<b>Lorem</b> <a title="foo">ipsum</a> <a href="http://foo.com/"><strong>dolor</strong></a> sit<br/>amet ',
  },
}.freeze

PROTOCOLS = {
  protocol_based_js_injection_simple_no_spaces: {
    html: '<a href="javascript:alert(\'XSS\');">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_simple_spaces_before: {
    html: '<a href="javascript    :alert(\'XSS\');">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_simple_spaces_after: {
    html: '<a href="javascript:    alert(\'XSS\');">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_simple_spaces_before_and_after: {
    html: '<a href="javascript    :   alert(\'XSS\');">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_preceding_colon: {
    html: '<a href=":javascript:alert(\'XSS\');">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_UTF8_encoding: {
    html: '<a href="javascript&#58;">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_long_UTF8_encoding: {
    html: '<a href="javascript&#0058;">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_long_UTF8_encoding_without_semicolons: {
    html: "<a href=&#0000106&#0000097&#0000118&#0000097&#0000115&#0000099&#0000114&#0000105&#0000112&#0000116&#0000058&#0000097&#0000108&#0000101&#0000114&#0000116&#0000040&#0000039&#0000088&#0000083&#0000083&#0000039&#0000041>foo</a>",
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_hex_encoding: {
    html: '<a href="javascript&#x3A;">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_long_hex_encoding: {
    html: '<a href="javascript&#x003A;">foo</a>',
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_hex_encoding_without_semicolons: {
    html: "<a href=&#x6A&#x61&#x76&#x61&#x73&#x63&#x72&#x69&#x70&#x74&#x3A&#x61&#x6C&#x65&#x72&#x74&#x28&#x27&#x58&#x53&#x53&#x27&#x29>foo</a>",
    default: "foo",
    restricted: "foo",
    basic: "<a>foo</a>",
    relaxed: "<a>foo</a>",
  },

  protocol_based_js_injection_null_char: {
    html: "<img src=java\0script:alert(\"XSS\")>",
    default: "",
    restricted: "",
    basic: "",
    relaxed: "",
  },

  protocol_based_js_injection_invalid_URL_char: {
    html: '<img src=java\script:alert("XSS")>',
    default: "",
    restricted: "",
    basic: "",
    relaxed: "<img>",
  },

  protocol_based_js_injection_spaces_and_entities: {
    html: '<img src=" &#14;  javascript:alert(\'XSS\');">',
    default: "",
    restricted: "",
    basic: "",
    relaxed: "<img>",
  },

  protocol_whitespace: {
    html: '<a href=" http://example.com/"></a>',
    default: "",
    restricted: "",
    basic: '<a href="http://example.com/"></a>',
    relaxed: '<a href="http://example.com/"></a>',
  },
}.freeze

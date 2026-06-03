# frozen_string_literal: true

require "test_helper"

class SelmaRewriterAttributeSourceLocationTest < Minitest::Test
  class CaptureLocations
    SELECTOR = Selma::Selector.new(match_element: "a, input, div")

    attr_reader :locations

    def initialize(*names)
      @names = names
      @locations = {}
    end

    def selector
      SELECTOR
    end

    def handle_element(element)
      @names.each do |name|
        @locations[name] = element.attribute_source_location(name)
      end
    end
  end

  class ModifyAndCapture
    SELECTOR = Selma::Selector.new(match_element: "a")

    attr_reader :added_location, :original_location

    def selector
      SELECTOR
    end

    def handle_element(element)
      element["data-new"] = "x"
      @added_location = element.attribute_source_location("data-new")
      @original_location = element.attribute_source_location("href")
    end
  end

  def test_returns_byte_offsets_for_name_and_value
    handler = CaptureLocations.new("href")
    html = %(<p>hi <a href="/world">link</a></p>)
    Selma::Rewriter.new(sanitizer: nil, handlers: [handler]).rewrite(html)

    loc = handler.locations["href"]

    refute_nil(loc)

    assert_equal("href", html.byteslice(loc[:name]))
    assert_equal("/world", html.byteslice(loc[:value]))
  end

  def test_returns_empty_value_range_for_explicit_empty_value
    handler = CaptureLocations.new("disabled")
    html = %(<input disabled="">)
    Selma::Rewriter.new(sanitizer: nil, handlers: [handler]).rewrite(html)

    loc = handler.locations["disabled"]

    refute_nil(loc)
    assert_equal("disabled", html.byteslice(loc[:name]))
    assert_equal("", html.byteslice(loc[:value]))
  end

  # lol_html does not record a source location for pure-boolean
  # attributes (those written without "="), so we surface that as nil rather
  # than fabricating one.
  def test_returns_nil_for_pure_boolean_attribute
    handler = CaptureLocations.new("disabled")
    html = %(<input disabled>)
    Selma::Rewriter.new(sanitizer: nil, handlers: [handler]).rewrite(html)

    assert_nil(handler.locations["disabled"])
  end

  def test_returns_nil_for_missing_attribute
    handler = CaptureLocations.new("nope")
    html = %(<a href="/x">link</a>)
    Selma::Rewriter.new(sanitizer: nil, handlers: [handler]).rewrite(html)

    assert_nil(handler.locations["nope"])
  end

  def test_returns_nil_for_attribute_added_during_rewrite
    handler = ModifyAndCapture.new
    html = %(<a href="/x">link</a>)
    Selma::Rewriter.new(sanitizer: nil, handlers: [handler]).rewrite(html)

    assert_nil(handler.added_location)
    refute_nil(handler.original_location)
    assert_equal("href", html.byteslice(handler.original_location[:name]))
    assert_equal("/x", html.byteslice(handler.original_location[:value]))
  end

  def test_distinct_offsets_for_multiple_attributes
    handler = CaptureLocations.new("class", "data-foo")
    html = %(<div class="a b" data-foo="baz">x</div>)
    Selma::Rewriter.new(sanitizer: nil, handlers: [handler]).rewrite(html)

    class_loc = handler.locations["class"]
    foo_loc = handler.locations["data-foo"]

    refute_nil(class_loc)
    refute_nil(foo_loc)

    assert_equal("class", html.byteslice(class_loc[:name]))
    assert_equal("a b", html.byteslice(class_loc[:value]))
    assert_equal("data-foo", html.byteslice(foo_loc[:name]))
    assert_equal("baz", html.byteslice(foo_loc[:value]))

    refute_equal(class_loc[:name], foo_loc[:name])
  end
end

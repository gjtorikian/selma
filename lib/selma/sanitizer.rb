# frozen_string_literal: true

require "selma/sanitizer/config"

module Selma
  class Sanitizer
    ALLOW = 1 << 0
    ESCAPE_TAGFILTER = (1 << 1)
    REMOVE_CONTENTS = (1 << 2)
    WRAP_WHITESPACE = (1 << 3)

    # initialize is in Rust, this just helps manage config setup in Ruby
    # TODO: could this just become initialize?
    def setup
      allow_element(config[:elements] || [])

      (config[:attributes] || {}).each do |element, attrs|
        allow_attribute(element, attrs)
      end

      (config[:protocols] || {}).each do |element, protocols|
        protocols.each do |attribute, pr|
          allow_protocol(element, attribute, pr)
        end
      end

      remove_contents(config[:remove_contents]) if config.include?(:remove_contents)

      wrap_with_whitespace(config[:whitespace_elements]) if config.include?(:whitespace_elements)

      set_escape_tagfilter(config.fetch(:escape_tagfilter, true))
      set_allow_comments(config.fetch(:allow_comments, false))
      set_allow_doctype(config.fetch(:allow_doctype, true))
    end

    def elements
      config[:elements]
    end

    def allow_element(elements)
      elements.flatten.each { |e| set_flag(e, ALLOW, true) }
    end

    def disallow_element(elements)
      elements.flatten.each { |e| set_flag(e, ALLOW, false) }
    end

    def allow_attribute(element, attrs)
      attrs.flatten.each { |attr| set_allowed_attribute(element, attr, true) }
    end

    def require_any_attributes(element, attrs)
      if attr.empty?
        set_required_attribute(element, "*", true)
      else
        attrs.flatten.each { |attr| set_required_attribute(element, attr, true) }
      end
    end

    def disallow_attribute(element, attrs)
      attrs.flatten.each { |attr| set_allowed_attribute(element, attr, false) }
    end

    def allow_class(element, *klass)
      klass.flatten.each { |k| set_allowed_class(element, k, true) }
    end

    def allow_protocol(element, attr, protos)
      if protos.is_a?(Array)
        raise ArgumentError, "`:all` must be passed outside of an array" if protos.include?(:all)
      else
        protos = [protos]
      end

      set_allowed_protocols(element, attr, protos)
    end

    def remove_contents(elements)
      if elements.is_a?(TrueClass) || elements.is_a?(FalseClass)
        set_all_flags(REMOVE_CONTENTS, elements)
      else
        elements.flatten.each { |e| set_flag(e, REMOVE_CONTENTS, true) }
      end
    end

    def wrap_with_whitespace(elements)
      elements.flatten.each { |e| set_flag(e, WRAP_WHITESPACE, true) }
    end
  end
end

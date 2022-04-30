# frozen_string_literal: true

require "zeitwerk"
gem_loader = Zeitwerk::Loader.for_gem
gem_loader.setup

require "nokogiri"
require "selma/version"

# require "amazing_print"
# require "debug"

module Selma
  class DocumentFragment
    def self.to_html(fragment, manipulators: [])
      selectors = manipulators.each_with_object({}) do |manipulator, hash|
        selector = begin
          manipulator::SELECTOR
        rescue NameError # SELECTOR is not defined
          next
        end

        next if selector.match.nil? || selector.match.empty?

        if hash.key?(:match)
          hash[selector.match] << manipulator
        else
          hash[selector.match] = [manipulator]
        end
      end

      doc = Nokogiri::HTML.fragment(fragment)
      matches = selectors.keys
      doc.css(*matches).each_with_index do |matched_content, idx|
        match = matches[idx]
        selectors[match].each do |manipulator|
          matched_content.replace(manipulator.new.call(matched_content))
        rescue NameError # #call is not defined
          next
        end
      end.to_html
    end

    def self.select_match(selector)
      { selector: selector, match: selector.match }
    end
  end
end

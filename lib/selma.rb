# frozen_string_literal: true

require "zeitwerk"
gem_loader = Zeitwerk::Loader.for_gem
gem_loader.setup

require "nokogiri"
require "selma/version"

require "sanitize"

# Sanitize annoyingly won't give you a node
# back, only a string. Monkey patch to just
# get the Nokogiri doc back, we have more to do
# with it!
class Sanitize
  def to_html(doc)
    doc
  end
end

require "amazing_print"
require "debug"

module Selma
  class DocumentFragment
    def self.to_html(fragment, sanitize: nil, manipulators: [])
      selectors = manipulators.each_with_object({}) do |manipulator, hash|
        selector = begin
          manipulator.class::SELECTOR
        rescue NameError # SELECTOR is not defined
          next
        end

        if !selector.match.nil? && !selector.match.empty?
          if hash.key?(:match)
            if hash[:match].key?(selector.match)
              hash[:match][selector.match] << manipulator
            else
              hash[:match][selector.match] = [manipulator]
            end
          else
            hash[:match] = {}
            hash[:match][selector.match] = [manipulator]
          end
        end
      end

      doc = if sanitize.nil?
              Nokogiri::HTML.fragment(fragment)
            else

              Sanitize.fragment(fragment, sanitize)
            end

      return doc.to_html unless selectors.key?(:match)

      matches = selectors[:match].keys

      matched_doc = doc.css(*matches)
      return fragment if matched_doc.empty?

      matched_doc.each do |matched_content|
        selectors[:match].each_pair do |match, manipulators|
          next unless matched_content.matches?(match) # is this a match?

          manipulators.each do |manipulator|
            next unless manipulator.respond_to?(:call)  # #call is not defined

            replacement = manipulator.call(matched_content)
            matched_content.replace(replacement) unless replacement.nil?
          end
        end
      end.to_html
    end
  end
end

# frozen_string_literal: true

require "benchmark/ips"
require "sanitize"
require "selma"

DIR = File.expand_path(File.dirname(__FILE__))

DOCUMENT_HUGE   = File.read("#{DIR}/benchmark/html/document-huge.html").encode("UTF-8", invalid: :replace, undef: :replace)
DOCUMENT_MEDIUM = File.read("#{DIR}/benchmark/html/document-medium.html").encode("UTF-8", invalid: :replace, undef: :replace)
DOCUMENT_SMALL  = File.read("#{DIR}/benchmark/html/document-small.html").encode("UTF-8", invalid: :replace, undef: :replace)

def compare_sanitize
  sanitize_config = Sanitize::Config::RELAXED
  [[DOCUMENT_HUGE, "huge"], [DOCUMENT_MEDIUM, "medium"], [DOCUMENT_SMALL, "small"]].each do |(html, label)|
    Benchmark.ips do |x|
      x.report("sanitize-document-#{label}") do
        Sanitize.document(html, sanitize_config)
      end

      x.report("selma-document-#{label}") do
        sanitizer = Selma::Sanitizer.new(Selma::Sanitizer::Config::RELAXED)
        Selma::Rewriter.new(sanitizer: sanitizer).rewrite(html)
      end
    end
  end
end

compare_sanitize

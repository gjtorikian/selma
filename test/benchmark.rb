# frozen_string_literal: true

require "benchmark/ips"
require "selma"
require_relative "benchmark/selma_config"

require "sanitize"
require "nokogiri"
require "nokolexbor"

DIR = File.expand_path(File.dirname(__FILE__))

DOCUMENT_SMALL  = File.read("#{DIR}/benchmark/html/document-sm.html").encode("UTF-8", invalid: :replace, undef: :replace)
DOCUMENT_MEDIUM = File.read("#{DIR}/benchmark/html/document-md.html").encode("UTF-8", invalid: :replace, undef: :replace)
DOCUMENT_HUGE   = File.read("#{DIR}/benchmark/html/document-lg.html").encode("UTF-8", invalid: :replace, undef: :replace)

DOCUMENTS = [
  [DOCUMENT_SMALL, "sm"],
  [DOCUMENT_MEDIUM, "md"],
  [DOCUMENT_HUGE, "lg"],
]

IPS_ARGS = { time: 30, warmup: 10 }

def bytes_to_megabytes(bytes)
  (bytes.to_f / 1_000_000).round(2)
end

def print_size(html)
  bytes = html.bytesize
  mbes = bytes_to_megabytes(bytes)
  puts("input size = #{bytes} bytes, #{mbes} MB\n\n")
end

def compare_sanitize
  DOCUMENTS.each do |(html, label)|
    print_size(html)
    Benchmark.ips do |x|
      x.config(IPS_ARGS)

      x.report("sanitize-#{label}") do
        Sanitize.document(html, Sanitize::Config::RELAXED)
      end

      x.report("selma-#{label}") do
        sanitizer = Selma::Sanitizer.new(Selma::Sanitizer::Config::RELAXED)
        Selma::Rewriter.new(sanitizer: sanitizer).rewrite(html)
      end

      x.compare!
    end
  end
end

def compare_rewriting
  nokogiri_compat = ->(doc) do
    doc.css(%(a[href])).each do |node|
      node["href"] = node["href"].sub(/^https?:/, "gopher:")
    end

    doc.css("span").each do |node|
      node.parent.add_child("<div>#{node.text}</div>")
    end

    doc.css("img").each(&:remove)

    doc.to_html
  end

  DOCUMENTS.each do |(html, label)|
    print_size(html)
    Benchmark.ips do |x|
      x.config(IPS_ARGS)

      x.report("nokogiri-#{label}") do
        doc = Nokogiri::HTML.parse(html)

        nokogiri_compat.call(doc)
      end

      x.report("nokolexbor-#{label}") do
        doc = Nokolexbor::HTML(html)

        nokogiri_compat.call(doc)
      end

      x.report("selma-#{label}") do
        Selma::Rewriter.new(sanitizer: nil, handlers: [
          SelmaConfig::HrefHandler.new,
          SelmaConfig::SpanHandler.new,
          SelmaConfig::ImgHandler.new,
        ]).rewrite(html)
      end

      x.compare!
    end
  end
end

compare_sanitize
compare_rewriting

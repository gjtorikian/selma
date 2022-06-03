# frozen_string_literal: true

require "benchmark/ips"
require "html/pipeline"
require "commonmarker"
require "sanitize"
require "selma"
require_relative "benchmark/selma_config"

REWRITE_INPUT = File.read("test/benchmark/rewrite_benchmark_input.md").freeze

def bytes_to_megabytes(bytes)
  (bytes.to_f / 1_000_000).round(2)
end

DIR = File.expand_path(File.dirname(__FILE__))

DOCUMENT_HUGE   = File.read("#{DIR}/benchmark/html/document-huge.html").encode("UTF-8", invalid: :replace, undef: :replace)
DOCUMENT_MEDIUM = File.read("#{DIR}/benchmark/html/document-medium.html").encode("UTF-8", invalid: :replace, undef: :replace)
DOCUMENT_SMALL  = File.read("#{DIR}/benchmark/html/document-small.html").encode("UTF-8", invalid: :replace, undef: :replace)

FRAGMENT_LARGE = File.read("#{DIR}/benchmark/html/fragment-large.html").encode("UTF-8", invalid: :replace, undef: :replace)
FRAGMENT_SMALL = File.read("#{DIR}/benchmark/html/fragment-small.html").encode("UTF-8", invalid: :replace, undef: :replace)

def compare_sanitize
  sanitize_config = Sanitize::Config::RELAXED
  [[DOCUMENT_HUGE, "huge"], [DOCUMENT_MEDIUM, "medium"], [DOCUMENT_SMALL, "small"]].each do |(html, label)|
    Benchmark.ips do |x|
      x.report("sanitize-document-#{label}") do
        Sanitize.document(html, sanitize_config)
      end

      x.report("selma-document-#{label}") do
        Selma::HTML.new(html, sanitize: Selma::Sanitizer::Config::RELAXED).rewrite
      end
    end
  end
end

def compare_rewriting
  bytes = REWRITE_INPUT.bytesize
  mbes = bytes_to_megabytes(bytes)
  puts("input size = #{bytes} bytes, #{mbes} MB\n\n")

  Benchmark.ips do |x|
    x.report("html-pipeline") do
      context = {
        asset_root: "http://your-domain.com/where/your/images/live/icons",
        base_url: "http://your-domain.com",
        asset_proxy: "https//assets.example.org",
        asset_proxy_secret_key: "ssssh-secret",
      }
      pipeline = HTML::Pipeline.new([
        HTML::Pipeline::MarkdownFilter,
        HTML::Pipeline::SanitizationFilter,
        HTML::Pipeline::CamoFilter,
        HTML::Pipeline::ImageMaxWidthFilter,
        HTML::Pipeline::HttpsFilter,
        HTML::Pipeline::MentionFilter,
        HTML::Pipeline::EmojiFilter,
        HTML::Pipeline::SyntaxHighlightFilter,
      ], context.merge(gfm: true))
      result = pipeline.call(REWRITE_INPUT)
      result[:output].to_s
    end

    x.report("selma") do
      html = CommonMarker.render_html(REWRITE_INPUT)
      Selma::HTML.new(html, sanitize: SelmaConfig::ALLOWLIST, handlers: [
        SelmaConfig::CamoHandler.new,
        SelmaConfig::ImageMaxWidthHandler.new,
        SelmaConfig::HttpsHandler.new,
        SelmaConfig::MentionHandler.new,
        SelmaConfig::EmojiHandler.new,
        SelmaConfig::SyntaxHighlightHandler.new,
      ]).rewrite
    end

    x.compare!
  end
end

compare_sanitize
compare_rewriting

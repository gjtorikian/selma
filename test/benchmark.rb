# frozen_string_literal: true

require "benchmark/ips"
require "html/pipeline"
require "commonmarker"
require "selma"
require_relative "benchmark/selma_config"

benchinput = File.read("test/benchinput.md").freeze

def bytes_to_megabytes(bytes)
  (bytes.to_f / 1_000_000).round(2)
end

bytes = benchinput.bytesize
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
    result = pipeline.call(benchinput)
    result[:output].to_s
  end

  x.report("selma") do
    html = CommonMarker.render_html(benchinput)
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

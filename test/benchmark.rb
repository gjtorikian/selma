# frozen_string_literal: true

require "benchmark/ips"
require "html/pipeline"
require "commonmarker"
require "selma"
require_relative "benchmark/selma_config"

benchinput = File.read("test/benchinput.md").freeze

printf("input size = %<bytes>d bytes\n\n", { bytes: benchinput.bytesize })

Benchmark.ips do |x|
  x.report("html-pipeline") do
    context = {
      asset_root: "http://your-domain.com/where/your/images/live/icons",
      base_url: "http://your-domain.com",
      asset_proxy: "https//assets.example.org",
      asset_proxy_secret_key: "ssssh-secret"
    }
    pipeline = HTML::Pipeline.new [
      HTML::Pipeline::MarkdownFilter,
      HTML::Pipeline::SanitizationFilter,
      HTML::Pipeline::CamoFilter,
      HTML::Pipeline::ImageMaxWidthFilter,
      HTML::Pipeline::HttpsFilter,
      HTML::Pipeline::MentionFilter,
      HTML::Pipeline::EmojiFilter,
      HTML::Pipeline::SyntaxHighlightFilter
    ], context.merge(gfm: true)
    result = pipeline.call(benchinput)
    result[:output].to_s
  end

  x.report("selma") do
    html = CommonMarker.render_html(benchinput)
    Selma::DocumentFragment.to_html(html, sanitize: SelmaConfig::ALLOWLIST, manipulators: [
                                      SelmaConfig::CamoManipulator.new,
                                      SelmaConfig::ImageMaxWidthManipulator.new,
                                      SelmaConfig::HttpsManipulator.new,
                                      SelmaConfig::MentionManipulator.new,
                                      SelmaConfig::EmojiManipulator.new,
                                      SelmaConfig::SyntaxHighlightManipulator.new
                                    ])
  end

  x.compare!
end

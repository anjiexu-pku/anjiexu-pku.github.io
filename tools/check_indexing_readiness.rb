# frozen_string_literal: true

require "net/http"
require "optparse"
require "rexml/document"
require "uri"
require "yaml"
require "date"

module IndexingReadiness
  Post = Struct.new(:title, :url, :source_path, keyword_init: true)
  Item = Struct.new(
    :title,
    :url,
    :source_path,
    :local_path,
    :in_sitemap,
    :canonical,
    :canonical_ok,
    :http_status,
    keyword_init: true
  )
  Report = Struct.new(:items, :noise_urls, keyword_init: true) do
    def failures
      items.reject do |item|
        item.in_sitemap &&
          item.local_path &&
          File.file?(item.local_path) &&
          item.canonical_ok &&
          (!item.http_status || item.http_status.to_i.between?(200, 399))
      end
    end
  end

  NOISE_URL_PATTERNS = [
    %r{/archive-layout-with-content/?$},
    %r{/collection-archive/?$},
    %r{/markdown/?$},
    %r{/non-menu-page/?$},
    %r{/page-archive/?$},
    %r{/portfolio(?:/|$)},
    %r{/talkmap\.html$},
    %r{/talkmap/map\.html$},
    %r{/talks(?:/|$)},
    %r{/teaching(?:/|$)},
    %r{/publication/\d{4}-\d{2}-\d{2}-paper-title-number-\d},
    %r{/files/(?:paper|slides)[1-3]\.pdf$},
    %r{/print-template\.html$},
    %r{/markdown_generator(?:/|$)},
    %r{/docs/blog-writing-style(?:/|\.md$)}
  ].freeze

  module_function

  def post_urls_from(posts_dir, base_url)
    Dir.glob(File.join(posts_dir, "*.md")).sort.filter_map do |path|
      data = front_matter(path)
      next if data["sitemap"] == false

      title = data.fetch("title", File.basename(path, ".md"))
      Post.new(title: title, url: absolute_url(post_path(path, data), base_url), source_path: path)
    end
  end

  def build_report(posts_dir:, site_dir:, base_url:, check_remote: false)
    sitemap_path = File.join(site_dir, "sitemap.xml")
    sitemap_urls = read_sitemap_urls(sitemap_path)
    items = post_urls_from(posts_dir, base_url).map do |post|
      local_path = local_html_path(site_dir, post.url, base_url)
      canonical = File.file?(local_path) ? canonical_for(local_path) : nil
      Item.new(
        title: post.title,
        url: post.url,
        source_path: post.source_path,
        local_path: local_path,
        in_sitemap: sitemap_urls.include?(post.url),
        canonical: canonical,
        canonical_ok: canonical == post.url,
        http_status: check_remote ? remote_status(post.url) : nil
      )
    end

    Report.new(
      items: items,
      noise_urls: sitemap_urls.select { |url| noise_url?(url) }.sort
    )
  end

  def front_matter(path)
    text = File.read(path)
    return {} unless text.start_with?("---")

    _leading, yaml, = text.split(/^---\s*$/, 3)
    yaml ? (YAML.safe_load(yaml, permitted_classes: [Date, Time], aliases: true) || {}) : {}
  end

  def post_path(path, data)
    permalink = data["permalink"]
    return ensure_slashes(permalink) if permalink && !permalink.empty?

    slug = File.basename(path, ".md").sub(/\A\d{4}-\d{2}-\d{2}-/, "")
    categories = Array(data["categories"]).map(&:to_s).reject(&:empty?)
    ensure_slashes(File.join("", *categories, slug))
  end

  def absolute_url(path, base_url)
    "#{base_url.sub(%r{/\z}, "")}#{ensure_slashes(path)}"
  end

  def ensure_slashes(path)
    normalized = "/#{path}".squeeze("/")
    normalized.end_with?("/") ? normalized : "#{normalized}/"
  end

  def read_sitemap_urls(path)
    doc = REXML::Document.new(File.read(path))
    urls = []
    REXML::XPath.each(doc, "//sm:url/sm:loc", "sm" => "http://www.sitemaps.org/schemas/sitemap/0.9") do |node|
      urls << node.text.to_s.strip
    end
    urls
  end

  def local_html_path(site_dir, url, base_url)
    path = url.delete_prefix(base_url.sub(%r{/\z}, ""))
    path = "/" if path.empty?
    if path.end_with?("/")
      File.join(site_dir, path, "index.html")
    else
      File.join(site_dir, path)
    end
  end

  def canonical_for(path)
    html = File.read(path)
    match = html.match(/<link\s+rel=["']canonical["']\s+href=["']([^"']+)["']/i) ||
            html.match(/<link\s+href=["']([^"']+)["']\s+rel=["']canonical["']/i)
    match && match[1]
  end

  def remote_status(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
    response.code.to_i
  rescue StandardError
    0
  end

  def noise_url?(url)
    NOISE_URL_PATTERNS.any? { |pattern| url.match?(pattern) }
  end

  def print_report(report)
    puts "Blog indexing readiness"
    puts
    printf "%-7s %-9s %-9s %s\n", "HTTP", "SITEMAP", "CANON", "URL"
    report.items.each do |item|
      status = item.http_status || "-"
      sitemap = item.in_sitemap ? "ok" : "missing"
      canonical = item.canonical_ok ? "ok" : "bad"
      printf "%-7s %-9s %-9s %s\n", status, sitemap, canonical, item.url
    end

    return if report.noise_urls.empty?

    puts
    puts "Potential sitemap noise"
    report.noise_urls.each { |url| puts "  #{url}" }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    root: Dir.pwd,
    base_url: "https://anjiexu-pku.github.io",
    remote: false
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby tools/check_indexing_readiness.rb [options]"
    opts.on("--root DIR", "Repository root, default: current directory") { |value| options[:root] = value }
    opts.on("--base-url URL", "Site base URL") { |value| options[:base_url] = value }
    opts.on("--remote", "Also check deployed HTTP status") { options[:remote] = true }
  end.parse!

  report = IndexingReadiness.build_report(
    posts_dir: File.join(options[:root], "_posts"),
    site_dir: File.join(options[:root], "_site"),
    base_url: options[:base_url],
    check_remote: options[:remote]
  )
  IndexingReadiness.print_report(report)

  exit(report.failures.empty? && report.noise_urls.empty? ? 0 : 1)
end

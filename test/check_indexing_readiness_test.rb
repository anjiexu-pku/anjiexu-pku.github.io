# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

require_relative "../tools/check_indexing_readiness"

class CheckIndexingReadinessTest < Minitest::Test
  def test_post_urls_are_derived_from_categories_and_filename
    Dir.mktmpdir do |dir|
      posts_dir = File.join(dir, "_posts")
      FileUtils.mkdir_p(File.join(posts_dir, "demo_blog"))

      File.write(File.join(posts_dir, "2026-06-03-how-i-design-skills.md"), <<~POST)
        ---
        title: "How I Design Claude Code Skills"
        categories:
          - tech
          - ai
        ---

        body
      POST
      File.write(File.join(posts_dir, "demo_blog", "2014-08-14-blog-post-3.md"), <<~POST)
        ---
        title: "Demo"
        categories:
          - posts
        ---
      POST

      posts = IndexingReadiness.post_urls_from(posts_dir, "https://example.com")

      assert_equal ["https://example.com/tech/ai/how-i-design-skills/"], posts.map(&:url)
      assert_equal "How I Design Claude Code Skills", posts.first.title
    end
  end

  def test_report_checks_sitemap_membership_and_canonical
    Dir.mktmpdir do |dir|
      posts_dir = File.join(dir, "_posts")
      site_dir = File.join(dir, "_site")
      FileUtils.mkdir_p(posts_dir)
      FileUtils.mkdir_p(File.join(site_dir, "tech", "ai", "how-i-design-skills"))

      File.write(File.join(posts_dir, "2026-06-03-how-i-design-skills.md"), <<~POST)
        ---
        title: "How I Design Claude Code Skills"
        categories:
          - tech
          - ai
        ---
      POST
      File.write(File.join(site_dir, "sitemap.xml"), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/tech/ai/how-i-design-skills/</loc></url>
        </urlset>
      XML
      File.write(File.join(site_dir, "tech", "ai", "how-i-design-skills", "index.html"), <<~HTML)
        <html><head>
          <link rel="canonical" href="https://example.com/tech/ai/how-i-design-skills/">
        </head><body></body></html>
      HTML

      report = IndexingReadiness.build_report(
        posts_dir: posts_dir,
        site_dir: site_dir,
        base_url: "https://example.com",
        check_remote: false
      )

      assert_equal 1, report.items.size
      assert_empty report.failures
      assert report.items.first.in_sitemap
      assert report.items.first.canonical_ok
    end
  end

  def test_noise_detection_catches_template_static_files
    assert IndexingReadiness.noise_url?("https://example.com/files/paper1.pdf")
    assert IndexingReadiness.noise_url?("https://example.com/files/slides3.pdf")
    assert IndexingReadiness.noise_url?("https://example.com/print-template.html")
    refute IndexingReadiness.noise_url?("https://example.com/files/huffman-optimality-lean4.zip")
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

class AsterinasStoryRenderTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  HOME = ROOT.join("_site/index.html")
  POST = ROOT.join("_site/tech/systems/booting-asterinas-riscv-megrez/index.html")
  ROUTE = "/tech/systems/booting-asterinas-riscv-megrez/"

  def setup
    assert HOME.file?, "run bundle exec jekyll build before this test"
    assert POST.file?, "missing generated article at #{POST.relative_path_from(ROOT)}"
  end

  def test_homepage_card_targets_the_generated_article
    html = HOME.read

    assert_includes html, 'class="latest-work-card"'
    assert_match(%r{href="#{Regexp.escape(ROUTE)}"}, html)
  end

  def test_article_renders_the_title_and_boot_chain
    html = POST.read

    assert_includes html, "我们如何在 RISC-V 实板上启动 Asterinas"
    assert_includes html, 'class="asterinas-boot-chain"'
    assert_includes html, "stage=user_first_write_returned"
  end

  def test_public_html_stays_inside_the_approved_device_scope
    [HOME, POST].each do |path|
      html = path.read
      refute_match(/\b(?:USB|framebuffer|keyboard)\b/i, html)
    end
  end
end

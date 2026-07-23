# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

class AsterinasStoryHomepageTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  HOME = ROOT.join("_pages/about.md")
  STYLE = ROOT.join("_sass/_homepage.scss")
  MAIN_SCSS = ROOT.join("assets/css/main.scss")
  POST_ID = "2026-07-23-booting-asterinas-riscv-megrez"

  def test_card_is_between_blog_heading_and_post_loop
    text = HOME.read
    heading = text.index("Blog\n======")
    card = text.index('class="latest-work-card"')
    loop = text.index("{% for post in site.posts %}")

    refute_nil heading
    refute_nil card
    refute_nil loop
    assert_operator heading, :<, card
    assert_operator card, :<, loop
  end

  def test_card_uses_the_exact_approved_copy_and_post_url
    text = HOME.read

    assert_includes text, "Latest Systems Work · July 2026"
    assert_includes text, "Booting Asterinas on real RISC-V hardware"
    assert_includes text, "From U-Boot's <code>booti</code> handoff through early virtual memory, OSTD/SMP, rootfs, and PID 1 on Milk-V Megrez."
    assert_includes text, "{% post_url #{POST_ID} %}"
    assert_includes text, "Read how we booted an OS"
  end

  def test_homepage_styles_are_scoped_and_imported
    assert STYLE.file?, "missing _sass/_homepage.scss"
    css = STYLE.read

    assert_includes MAIN_SCSS.read, '@import "homepage";'
    assert_includes css, ".latest-work-card"
    assert_includes css, "@include breakpoint(max-width $small)"
    refute_match(/^\s*(?:body|h[1-6]|p|a)\s*\{/m, css)
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

class AsterinasStoryPostTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  POST = ROOT.join("_posts/2026-07-23-booting-asterinas-riscv-megrez.md")

  def source
    assert POST.file?, "missing #{POST.relative_path_from(ROOT)}"
    POST.read
  end

  def test_frontmatter_matches_the_approved_route_and_taxonomy
    text = source

    assert_match(/^title: "我们如何在 RISC-V 实板上启动 Asterinas"$/, text)
    assert_match(/^date: 2026-07-23$/, text)
    assert_includes text, "categories:\n  - tech\n  - systems"
    %w[Asterinas RISC-V Operating\ Systems Milk-V\ Megrez].each do |tag|
      assert_includes text, "  - #{tag}"
    end
  end

  def test_article_contains_the_approved_boot_spine
    text = source
    required = [
      "Starting kernel ...",
      "Linux Image v0.2",
      "`satp`",
      "Enter riscv_boot",
      "OSTD initialized. Preparing components.",
      "[kernel] rootfs is ready",
      "stage=user_enter",
      "stage=user_first_write_returned",
      "OpenSBI v1.5",
      "U-Boot 2024.01",
      "第一个缺失边界"
    ]

    required.each { |marker| assert_includes text, marker }
  end

  def test_article_uses_only_the_approved_public_scope
    text = source

    refute_match(/\b(?:USB|framebuffer|keyboard)\b/i, text)
    refute_match(/世界首(?:个|次)|first-ever|world first|已(?:经)?正式支持|production-ready/i, text)
    refute_includes text, "TankTechnology/asterinas-riscv"
    refute_includes text, "/home/ubuntu/"
    refute_includes text, "/dev/tty"
  end

  def test_article_links_primary_documentation
    text = source
    references = [
      "https://asterinas.github.io/book/kernel/",
      "https://asterinas.github.io/2025/12/19/announcing-asterinas-0.17.0.html",
      "https://docs.u-boot.org/en/v2024.01/usage/cmd/booti.html",
      "https://docs.kernel.org/6.1/riscv/boot-image-header.html",
      "https://docs.kernel.org/next/arch/riscv/boot.html",
      "https://milkv.io/docs/megrez/getting-started/resources"
    ]

    references.each { |url| assert_includes text, url }
  end

  def test_article_contains_the_responsive_boot_chain
    text = source

    assert_includes text, 'class="asterinas-boot-chain"'
    %w[OpenSBI U-Boot Image/DTB OSTD/SMP rootfs PID\ 1].each do |stage|
      assert_includes text, ">#{stage}<"
    end
    assert_includes text, "@media (max-width: 700px)"
  end
end

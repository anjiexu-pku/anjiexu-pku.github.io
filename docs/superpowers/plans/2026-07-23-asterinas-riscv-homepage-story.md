# Asterinas RISC-V 实板启动主页与文章 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有个人主页的 Blog 列表前加入一张英文 Latest Systems Work 提示卡，并新增一篇中文技术文章，准确复盘 Asterinas 在 Milk-V Megrez 上从 U-Boot `booti` 到 PID 1 的基础启动过程。

**Architecture:** 首页只负责提供紧凑入口，通过 Jekyll `post_url` 强绑定到文章；文章负责完整技术叙事和证据边界。新增的首页 SCSS 使用独立 partial 和 `.latest-work-card` 命名空间，文章内启动链使用局部 HTML/CSS，不改变站点全局结构。

**Tech Stack:** Jekyll、Kramdown、Liquid、SCSS、Ruby Minitest、HTML/CSS、Playwright 浏览器检查。

---

## 执行前约束

- 设计说明：
  `docs/superpowers/specs/2026-07-23-asterinas-riscv-homepage-story-design.md`
- 主张审计：
  `docs/audits/2026-07-23-asterinas-megrez-claim-audit.md`
- 机器可读支持矩阵：
  `docs/audits/2026-07-23-asterinas-megrez-support-matrix.json`
- 不修改或提交 `_site/`；
- 不推送远端；
- 不加入 USB、framebuffer、keyboard 等后续设备工程；
- 不加入私有仓库 URL、主机路径、串口设备标识或原始日志；
- 不使用“世界首个”“已正式支持”“生产可用”等主张；
- 公开技术背景只引用官方资料。

## 文件结构

### 新建

- `_posts/2026-07-23-booting-asterinas-riscv-megrez.md`
  - 中文技术文章；
  - 包含 frontmatter、局部启动链样式、正文、脱敏日志和官方引用。
- `_sass/_homepage.scss`
  - 只负责首页 Latest Systems Work 提示卡。
- `test/asterinas_story_post_test.rb`
  - 锁定文章 frontmatter、技术主线、公开引用和主张边界。
- `test/asterinas_story_homepage_test.rb`
  - 锁定首页卡片位置、文案、Liquid 链接和样式隔离。
- `test/asterinas_story_render_test.rb`
  - 锁定 Jekyll 生成后的首页链接和文章路由。

### 修改

- `_pages/about.md`
  - 在 Blog 标题与文章循环之间加入提示卡；
  - 保持原有博客循环不变。
- `assets/css/main.scss`
  - 导入 `homepage` SCSS partial。

## Task 1：用来源契约驱动中文技术文章

**Files:**

- Create: `test/asterinas_story_post_test.rb`
- Create: `_posts/2026-07-23-booting-asterinas-riscv-megrez.md`
- Reference: `docs/superpowers/specs/2026-07-23-asterinas-riscv-homepage-story-design.md`
- Reference: `docs/audits/2026-07-23-asterinas-megrez-claim-audit.md`
- Reference: `/home/ubuntu/xaj/Program/asterinas/docs/porting/evidence/2026-07-20-megrez-pid1-recovery.md`

- [ ] **Step 1：先写失败的文章来源测试**

创建 `test/asterinas_story_post_test.rb`：

```ruby
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
```

- [ ] **Step 2：运行测试，确认因文章缺失而失败**

Run:

```bash
ruby test/asterinas_story_post_test.rb
```

Expected:

```text
5 runs
5 failures
missing _posts/2026-07-23-booting-asterinas-riscv-megrez.md
```

- [ ] **Step 3：创建文章 frontmatter 与局部启动链样式**

创建 `_posts/2026-07-23-booting-asterinas-riscv-megrez.md`，文件开头必须是：

```markdown
---
title: "我们如何在 RISC-V 实板上启动 Asterinas"
date: 2026-07-23
categories:
  - tech
  - systems
tags:
  - Asterinas
  - RISC-V
  - Operating Systems
  - Milk-V Megrez
excerpt: "从 U-Boot 的一次 booti，到早期页表、OSTD、四核启动、rootfs 和 PID 1：复盘我们怎样定义、推进并验证一次真实 RISC-V 开发板上的操作系统启动。"
---

<style>
.asterinas-boot-chain {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 0.55rem;
  margin: 1.5rem 0 2rem;
}
.asterinas-boot-chain__stage {
  position: relative;
  padding: 0.8rem 0.45rem;
  border: 1px solid #d9e5e9;
  border-radius: 4px;
  background: #f4fafc;
  color: #34495e;
  font-size: 0.78em;
  font-weight: 700;
  text-align: center;
}
.asterinas-boot-chain__stage:not(:last-child)::after {
  content: "›";
  position: absolute;
  top: 50%;
  right: -0.55rem;
  z-index: 1;
  transform: translate(50%, -50%);
  color: #52adc8;
  font-size: 1.1rem;
}
@media (max-width: 700px) {
  .asterinas-boot-chain {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .asterinas-boot-chain__stage::after {
    display: none;
  }
}
</style>
```

紧接开篇成功判据后加入：

```html
<div class="asterinas-boot-chain" aria-label="Asterinas 在 Megrez 上的基础启动链">
  <div class="asterinas-boot-chain__stage">OpenSBI</div>
  <div class="asterinas-boot-chain__stage">U-Boot</div>
  <div class="asterinas-boot-chain__stage">Image/DTB</div>
  <div class="asterinas-boot-chain__stage">OSTD/SMP</div>
  <div class="asterinas-boot-chain__stage">rootfs</div>
  <div class="asterinas-boot-chain__stage">PID 1</div>
</div>
```

- [ ] **Step 4：按已确认的六个转折点写完整正文**

正文必须使用以下标题和内容边界：

```markdown
## `Starting kernel ...` 之后还有多远

## 三个世界：开发机、固件与 Asterinas

## 合法的镜像头为什么仍会移动内核

## 把“无输出”拆成第一个缺失边界

## OSTD、四个 hart 与 rootfs

## DTB 正确，实际 bootargs 仍可能错误

## PID 1：从内核启动到用户态

## 一次可审计的真机启动

## 值得保留的方法

## 边界与参考资料
```

各节必须覆盖以下精确信息：

1. `Starting kernel ...` 只证明 U-Boot 接受镜像并跳转，不是文章的启动成功判据；
2. 解释 OpenSBI、U-Boot、平坦 Image、DTB、initramfs 和 Asterinas 各自职责；
3. 解释历史工具在链接后前插 64 字节 header，导致页表相对链接地址移动
   `0x40`；
4. 解释最终 header 位于链接布局，导出工具只做验证、抽取和补零；
5. 用 `satp`、高半地址、frame allocator、线性映射和 `Enter riscv_boot`
   说明“第一个缺失边界”；
6. 明确真机启动了三个 application processor，加上 boot hart 共四个 hart；
7. 解释 `6df0f28f` 到达 rootfs 后，U-Boot RAM `bootargs` 覆盖 DTB，
   使 `init=/init` 丢失并产生 `ENOENT`；
8. 解释 `3ef99e6bd` 的 PID 1 进入 U-mode、首次缺页、`openat` 和
   50 字节 `write`；
9. 解释冻结提交/镜像身份、大小、SHA-256、CRC、内存范围、单次
   `booti`、被动观察与恢复能力；
10. 结尾明确这是受控开发分支上的 Megrez bring-up 结果，不把它扩大为
    上游板级支持。

- [ ] **Step 5：加入两段经过脱敏的真机日志**

第一段只保留下列基础启动边界：

```text
Starting kernel ...
Enter riscv_boot
INFO: Booting 3 processors
INFO: All application processors started. The BSP continues to run.
OSTD initialized. Preparing components.
[kernel] rootfs is ready
ASTERINAS_FIRST_PROCESS_DIAG stage=user_enter ...
ASTERINAS_FIRST_PROCESS_DIAG stage=user_first_page_fault_handler outcome=resolved
ASTERINAS_FIRST_PROCESS_DIAG stage=user_first_syscall id=56 ...
ASTERINAS_FIRST_PROCESS_DIAG stage=user_first_write_returned fd=1 requested=50 result=50
```

第二段只保留新的固件周期：

```text
DDR type:LPDDR5;Size:16GB,Data Rate:6400MT/s
DDR self test OK
OpenSBI v1.5
U-Boot 2024.01
=>
```

不要复制 ANSI 色彩、主机路径、加载地址、串口标识或这两个片段之间的其他
设备日志。

- [ ] **Step 6：加入官方一手资料**

在“边界与参考资料”中加入：

```markdown
- [Asterinas Book: Getting Started](https://asterinas.github.io/book/kernel/)
- [Announcing Asterinas 0.17.0](https://asterinas.github.io/2025/12/19/announcing-asterinas-0.17.0.html)
- [U-Boot `booti` command](https://docs.u-boot.org/en/v2024.01/usage/cmd/booti.html)
- [Linux: Boot image header in RISC-V](https://docs.kernel.org/6.1/riscv/boot-image-header.html)
- [Linux: RISC-V Kernel Boot Requirements and Constraints](https://docs.kernel.org/next/arch/riscv/boot.html)
- [Milk-V Megrez resources](https://milkv.io/docs/megrez/getting-started/resources)
```

在正文首次使用这些事实时就近链接，不把参考资料只堆在文章末尾。

- [ ] **Step 7：运行文章来源测试并确认通过**

Run:

```bash
ruby test/asterinas_story_post_test.rb
```

Expected:

```text
5 runs
0 failures
0 errors
```

- [ ] **Step 8：检查文章 diff 并提交**

Run:

```bash
git diff --check
git diff -- _posts/2026-07-23-booting-asterinas-riscv-megrez.md test/asterinas_story_post_test.rb
```

Expected:

```text
git diff --check exits 0
diff contains only the new article and its source contract test
```

Commit:

```bash
git add _posts/2026-07-23-booting-asterinas-riscv-megrez.md test/asterinas_story_post_test.rb
git commit -m "Add Asterinas Megrez bring-up story"
```

## Task 2：用 TDD 加入首页 Latest Systems Work 入口

**Files:**

- Create: `test/asterinas_story_homepage_test.rb`
- Create: `_sass/_homepage.scss`
- Modify: `_pages/about.md`
- Modify: `assets/css/main.scss`

- [ ] **Step 1：先写失败的首页来源测试**

创建 `test/asterinas_story_homepage_test.rb`：

```ruby
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
```

- [ ] **Step 2：运行测试，确认首页卡片和样式缺失**

Run:

```bash
ruby test/asterinas_story_homepage_test.rb
```

Expected:

```text
3 runs
failures mention missing latest-work-card and _sass/_homepage.scss
```

- [ ] **Step 3：在 Blog 标题与文章循环之间加入首页卡片**

将 `_pages/about.md` 的 Blog 部分改为：

```markdown
Blog
======

<div class="latest-work-card">
  <p class="latest-work-card__eyebrow">Latest Systems Work · July 2026</p>
  <h3 class="latest-work-card__title">Booting Asterinas on real RISC-V hardware</h3>
  <p class="latest-work-card__summary">From U-Boot's <code>booti</code> handoff through early virtual memory, OSTD/SMP, rootfs, and PID 1 on Milk-V Megrez.</p>
  <a class="latest-work-card__link" href="{% post_url 2026-07-23-booting-asterinas-riscv-megrez %}">Read how we booted an OS <span aria-hidden="true">→</span></a>
</div>

{% for post in site.posts %}
- **{{ post.date | date: "%Y-%m-%d" }}** — [{{ post.title }}]({{ post.url }})
{% endfor %}
```

- [ ] **Step 4：创建范围隔离的首页样式**

创建 `_sass/_homepage.scss`：

```scss
/* ==========================================================================
   Homepage feature callouts
   ========================================================================== */

.latest-work-card {
  margin: 0.5em 0 1.75em;
  padding: 1em 1.1em;
  border: 1px solid $border-color;
  border-left: 0.25rem solid $info-color;
  border-radius: $border-radius;
  background: mix(#fff, $info-color, 94%);
  box-shadow: 0 1px 1px rgba($info-color, 0.15);

  &__eyebrow {
    margin: 0 0 0.45em !important;
    color: mix(#000, $info-color, 22%);
    font-size: $type-size-7 !important;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  &__title {
    margin: 0 0 0.45em;
    font-size: $type-size-5;
  }

  &__summary {
    margin-bottom: 0.75em !important;
  }

  &__link {
    display: inline-flex;
    gap: 0.35em;
    align-items: center;
    color: $link-color;
    font-size: $type-size-6;
    font-weight: 700;
    text-decoration: none !important;
  }

  @include breakpoint(max-width $small) {
    padding: 0.9em;

    &__title {
      line-height: 1.35;
    }
  }
}
```

- [ ] **Step 5：把 homepage partial 接入主样式**

在 `assets/css/main.scss` 中紧跟 `@import "page";` 加入：

```scss
@import "homepage";
```

- [ ] **Step 6：运行首页来源测试并确认通过**

Run:

```bash
ruby test/asterinas_story_homepage_test.rb
```

Expected:

```text
3 runs
0 failures
0 errors
```

- [ ] **Step 7：运行所有来源层测试**

Run:

```bash
ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

Expected:

```text
all Minitest suites pass
0 failures
0 errors
```

- [ ] **Step 8：检查首页 diff 并提交**

Run:

```bash
git diff --check
git diff -- _pages/about.md _sass/_homepage.scss assets/css/main.scss test/asterinas_story_homepage_test.rb
```

Expected:

```text
git diff --check exits 0
existing About, Education, Publications, Blog loop, Awards, Experience, Skills, and Hobbies content remains intact
```

Commit:

```bash
git add _pages/about.md _sass/_homepage.scss assets/css/main.scss test/asterinas_story_homepage_test.rb
git commit -m "Feature Asterinas RISC-V story on homepage"
```

## Task 3：锁定 Jekyll 生成后的路由与链接

**Files:**

- Create: `test/asterinas_story_render_test.rb`
- Generated, do not commit: `_site/index.html`
- Generated, do not commit:
  `_site/tech/systems/booting-asterinas-riscv-megrez/index.html`

- [ ] **Step 1：先写生成结果测试**

创建 `test/asterinas_story_render_test.rb`：

```ruby
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
```

- [ ] **Step 2：在重新构建前确认测试失败**

Run:

```bash
ruby test/asterinas_story_render_test.rb
```

Expected:

```text
failures report a missing generated article or stale homepage
```

- [ ] **Step 3：运行完整 Jekyll 构建**

Run:

```bash
bundle exec jekyll build
```

Expected:

```text
exit 0
Generating...
done
```

- [ ] **Step 4：运行生成结果测试**

Run:

```bash
ruby test/asterinas_story_render_test.rb
```

Expected:

```text
3 runs
0 failures
0 errors
```

- [ ] **Step 5：运行现有索引测试和完整测试集**

Run:

```bash
ruby test/check_indexing_readiness_test.rb
ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

Expected:

```text
check_indexing_readiness_test.rb: 3 runs, 0 failures, 0 errors
full suite: 0 failures, 0 errors
```

- [ ] **Step 6：确认文章进入 sitemap 和 canonical**

Run:

```bash
bundle exec ruby tools/check_indexing_readiness.rb
```

Expected:

```text
exit 0
the Asterinas story route is present in sitemap.xml
the generated article canonical URL matches https://anjiexu-pku.github.io/tech/systems/booting-asterinas-riscv-megrez/
```

- [ ] **Step 7：提交生成结果测试，不提交 `_site/`**

Run:

```bash
git status --short
git diff --check
```

Expected:

```text
only test/asterinas_story_render_test.rb is uncommitted
_site/ is ignored
```

Commit:

```bash
git add test/asterinas_story_render_test.rb
git commit -m "Test rendered Asterinas story route"
```

## Task 4：桌面与移动端浏览器验证

**Files:**

- Inspect: `_site/index.html`
- Inspect:
  `_site/tech/systems/booting-asterinas-riscv-megrez/index.html`
- Temporary screenshots, do not commit:
  `/tmp/asterinas-story-home-desktop.png`
  `/tmp/asterinas-story-home-mobile.png`
  `/tmp/asterinas-story-post-desktop.png`
  `/tmp/asterinas-story-post-mobile.png`

- [ ] **Step 1：启动本地 Jekyll 服务**

Run in a persistent terminal:

```bash
bundle exec jekyll serve --host 127.0.0.1 --port 4000 --no-watch
```

Expected:

```text
Server address: http://127.0.0.1:4000/
Server running
```

- [ ] **Step 2：使用 webapp-testing 检查桌面首页**

打开 `http://127.0.0.1:4000/`，视口设为 `1440 × 1000`。

检查：

- 卡片位于 Blog 标题与日期列表之间；
- About、Education、Publications 未重排；
- 卡片标题、摘要、CTA 与批准文案一致；
- 卡片没有遮挡侧栏；
- `document.documentElement.scrollWidth <= document.documentElement.clientWidth`；
- 浏览器控制台无错误。

保存截图：

```text
/tmp/asterinas-story-home-desktop.png
```

- [ ] **Step 3：点击首页 CTA 并检查文章桌面版**

点击 `Read how we booted an OS →`，确认 URL 为：

```text
http://127.0.0.1:4000/tech/systems/booting-asterinas-riscv-megrez/
```

检查：

- 中文标题和摘要正确；
- 启动链同一行显示六个阶段；
- 代码块可横向滚动，不撑破正文；
- 表格、notice 与日志片段可读；
- 页面没有 USB、framebuffer 或 keyboard 文字；
- 浏览器控制台无错误。

保存截图：

```text
/tmp/asterinas-story-post-desktop.png
```

- [ ] **Step 4：检查移动端首页和文章**

视口设为 `390 × 844`，依次检查首页和文章：

- 首页卡片保持单列，CTA 可点击；
- 页面无横向滚动；
- 启动链重排为两列；
- 日志和表格不超出正文容器；
- 文章标题没有裁切；
- 浏览器控制台无错误。

保存：

```text
/tmp/asterinas-story-home-mobile.png
/tmp/asterinas-story-post-mobile.png
```

- [ ] **Step 5：若浏览器检查失败，只做局部修正**

允许的修正范围：

- `_sass/_homepage.scss` 的卡片间距、字号和窄屏规则；
- 文章局部 `.asterinas-boot-chain` 样式；
- Markdown 表格附近的局部容器；
- 错字、断链或脱敏遗漏。

不允许：

- 改变全站字体、导航或主体宽度；
- 加入 JavaScript 或外部图片；
- 扩大文章设备范围。

每次修正后重新执行：

```bash
ruby test/asterinas_story_post_test.rb
ruby test/asterinas_story_homepage_test.rb
bundle exec jekyll build
ruby test/asterinas_story_render_test.rb
```

Expected:

```text
all commands exit 0
```

如果产生修正，提交：

```bash
git add _posts/2026-07-23-booting-asterinas-riscv-megrez.md _sass/_homepage.scss
git commit -m "Polish Asterinas story presentation"
```

若没有源文件变化，不创建空提交。

## Task 5：最终证据、构建与工作树审计

**Files:**

- Verify: `_pages/about.md`
- Verify: `_posts/2026-07-23-booting-asterinas-riscv-megrez.md`
- Verify: `_sass/_homepage.scss`
- Verify: `assets/css/main.scss`
- Verify: `test/asterinas_story_post_test.rb`
- Verify: `test/asterinas_story_homepage_test.rb`
- Verify: `test/asterinas_story_render_test.rb`

- [ ] **Step 1：验证主张支持矩阵和公开内容边界**

Run:

```bash
jq empty docs/audits/2026-07-23-asterinas-megrez-support-matrix.json
rg -n -i '\\b(USB|framebuffer|keyboard)\\b' _pages/about.md _posts/2026-07-23-booting-asterinas-riscv-megrez.md
rg -n -i 'world first|first-ever|世界首(个|次)|已(经)?正式支持|production-ready' _pages/about.md _posts/2026-07-23-booting-asterinas-riscv-megrez.md
rg -n '/home/ubuntu|/dev/tty|TankTechnology/asterinas-riscv' _pages/about.md _posts/2026-07-23-booting-asterinas-riscv-megrez.md
```

Expected:

```text
jq exits 0
all three rg commands return no matches
```

- [ ] **Step 2：运行最终测试与构建**

Run:

```bash
set -e
bundle exec jekyll build
ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
ruby test/asterinas_story_render_test.rb
bundle exec ruby tools/check_indexing_readiness.rb
git diff --check
```

Expected:

```text
Jekyll build exits 0
all Minitest suites pass
render tests pass
indexing readiness exits 0
git diff --check exits 0
```

- [ ] **Step 3：检查提交历史和工作树**

Run:

```bash
git log -5 --oneline
git status --short
```

Expected history contains:

```text
Test rendered Asterinas story route
Feature Asterinas RISC-V story on homepage
Add Asterinas Megrez bring-up story
Design Asterinas RISC-V homepage story
```

Expected status:

```text
empty
```

- [ ] **Step 4：停止本地服务并汇报，不推送远端**

停止 Task 4 启动的 Jekyll 服务。

最终汇报必须包含：

- 首页卡片和中文文章的本地路径；
- 文章公开 URL 路由；
- 精确测试与构建结果；
- 桌面/移动端检查结果；
- commit 列表；
- 明确说明没有执行 `git push`。

## 计划自审映射

- 首页采用 C 方案：Task 2；
- 英文首页摘要 + 中文正文：Task 1、Task 2；
- 六个基础启动转折点：Task 1；
- 排除后续设备工程：Task 1 测试、Task 5 扫描；
- 官方一手资料：Task 1 Step 6；
- 独立、范围受控的样式：Task 2；
- Liquid 链接失败即构建失败：Task 2、Task 3；
- Jekyll 构建、sitemap 与 canonical：Task 3；
- 桌面与移动端视觉检查：Task 4；
- 不发布远端：执行前约束、Task 5。

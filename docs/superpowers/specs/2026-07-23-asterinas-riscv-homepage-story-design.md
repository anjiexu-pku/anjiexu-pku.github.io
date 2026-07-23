# Asterinas RISC-V 实板启动主页与文章设计

日期：2026-07-23
状态：已完成交互设计确认，等待书面设计复核

## 目标

在不改变个人主页整体学术结构的前提下，增加一条克制但容易发现的
系统工程成果入口，并写一篇中文技术文章，复盘我们如何在真实的
Milk-V Megrez RISC-V 开发板上把 Asterinas 从 U-Boot `booti` 带到
PID 1 用户态。

文章的价值不只是宣布“系统启动了”，而是解释：

1. 怎样定义一个可验证的操作系统启动边界；
2. 固件、镜像、页表、OSTD、SMP、rootfs 和 PID 1 如何连接；
3. 哪些失败改变了我们对系统的理解；
4. 怎样把一次危险且容易误判的真机实验变成可审计的工程结果。

## 设计依据

设计以本地 Asterinas 证据链为主要事实来源，并以公开的 Asterinas
项目资料作为背景：

- Asterinas 公开项目将 RISC-V 64 列为 Tier 2 部署架构；
- Asterinas 0.17.0 已公开记录 HiFive Unleashed、PLIC、SMP、FPU 和
  VirtIO 等 RISC-V 进展；
- 本地 Megrez 追加式证据索引记录了从 U-Boot 跳转、早期地址空间、
  OSTD、四个 hart、rootfs 到 PID 1 的逐级真机边界；
- 受控候选 `3ef99e6bd15341578b32256c897050e873ca2547` 在 Megrez 上进入
  PID 1 用户态，解析首次缺页，执行 `openat`，并完成一次 50 字节
  `write`；
- 同一受控会话后来出现新的 DDR、OpenSBI 和 U-Boot 周期，并回到
  U-Boot prompt。

主张支持矩阵和安全措辞见：

- `docs/audits/2026-07-23-asterinas-megrez-support-matrix.json`
- `docs/audits/2026-07-23-asterinas-megrez-claim-audit.md`

## 公开主张

### 允许使用

首页使用以下英文主张：

> From U-Boot's `booti` handoff through early virtual memory, OSTD/SMP,
> rootfs, and PID 1 on Milk-V Megrez.

文章使用以下中文核心主张：

> 我们在真实的 Milk-V Megrez RISC-V 开发板上，把 Asterinas 从
> U-Boot `booti` 带到了 PID 1 用户态。

上述主张的“实板”范围来自受控 Megrez 运行，而不是从 QEMU 结果外推。

### 禁止使用

公开页面不得使用下列表述：

- “世界首个”“首次在 RISC-V 开发板启动 Asterinas”；
- “Asterinas 已正式支持 Milk-V Megrez”；
- “完整支持”“生产可用”“长期稳定”；
- 任何把开发分支描述为已经合入 Asterinas 上游的措辞。

## 范围

### 包含

- OpenSBI、U-Boot 和 Asterinas 之间的控制权交接；
- RISC-V Linux Image v0.2 镜像契约；
- DTB 与 initramfs 在启动链中的职责；
- 链接布局、早期页表、高半地址和 `satp` 边界；
- OSTD 初始化和四 hart 启动；
- rootfs 和 U-Boot RAM bootargs 覆盖问题；
- PID 1 进入 U-mode、首次缺页、`openat` 和 `write`；
- QEMU 门禁与真机证据的区别；
- 提交、镜像、哈希、单次 `booti` 和受控恢复的取证方法。

### 不包含

- USB、framebuffer、键盘和后续本地 console 工程；
- 图形界面、完整发行版用户空间或应用兼容性；
- 原始日志附件、主机路径、串口设备标识或其他本地环境细节；
- 私有仓库 URL；
- 正式板级支持、性能、长期稳定性或优先权主张。

## 信息架构

采用已确认的 C 方案：

1. 保持首页的 About Me、Education、Publications 等原有顺序和样式；
2. 在 `Blog` 标题之后、按日期生成的文章列表之前加入一张
   `Latest Systems Work` 提示卡；
3. 提示卡使用英文，与现有主页主体语言一致；
4. 卡片链接到一篇中文技术文章；
5. 所有技术细节放入文章，不在首页展开。

首页卡片文案：

```text
LATEST SYSTEMS WORK · JULY 2026

Booting Asterinas on real RISC-V hardware

From U-Boot's booti handoff through early virtual memory, OSTD/SMP,
rootfs, and PID 1 on Milk-V Megrez.

Read how we booted an OS →
```

## 文章设计

### 基本信息

- 文件：
  `_posts/2026-07-23-booting-asterinas-riscv-megrez.md`
- 标题：
  `我们如何在 RISC-V 实板上启动 Asterinas`
- 语言：中文
- 建议分类：`tech`、`systems`
- 建议标签：`Asterinas`、`RISC-V`、`Operating Systems`、`Milk-V Megrez`
- 摘要：
  `从 U-Boot 的一次 booti，到早期页表、OSTD、四核启动、rootfs 和
  PID 1：复盘我们怎样定义、推进并验证一次真实 RISC-V 开发板上的
  操作系统启动。`

### 开篇

文章从一个可观察的反差开始：

> `Starting kernel ...` 只证明 U-Boot 接受镜像并完成跳转。它没有证明
> Asterinas 建立了地址空间、进入 Rust、初始化内核，更没有证明 PID 1
> 已经在用户态运行。

随后给出本文的成功判据：

1. Asterinas 进入 `riscv_boot`；
2. OSTD 和四个 hart 初始化；
3. 内核组件完成并准备 rootfs；
4. PID 1 进入 U-mode；
5. PID 1 执行第一批系统调用；
6. 受控实验回到已知固件状态。

### 技术主线

文章按六个改变判断的转折点组织，而不是逐条复述命令。

#### 一、镜像契约：合法 header 仍可能移动内核

历史工具在链接完成后向 raw image 前插 64 字节 Linux Image header。
U-Boot 因此接受镜像，但链接时确定的启动代码和页表整体移动 `0x40`。

文章解释：

- 为什么 U-Boot 使用平坦 Image，而 QEMU 可以直接读取 ELF；
- 为什么文件偏移必须与链接时物理布局一致；
- 为什么最终做法是把 header 放入链接布局，并让导出工具只验证和抽取。

#### 二、早期内存：把“无输出”变成命名边界

在 `satp`、高半地址跳转、frame allocator 和线性映射附近加入有限的
进度标记，区分：

- 尚未进入 Asterinas；
- 已执行启动汇编但没有完成地址空间切换；
- 已进入 Rust/OSTD；
- 仍在进行缓慢的内存初始化，而不是卡死。

文章强调“第一个缺失边界”这一调试方法。

#### 三、OSTD 与 SMP：从启动 hart 到运行中的内核

真机证据证明：

- Asterinas 进入 `riscv_boot`；
- OSTD 完成初始化；
- 另外三个 application processor 启动；
- 组件初始化继续推进。

这里明确区分真机观察与 QEMU 预检，避免把模拟器能力写成板级事实。

#### 四、rootfs 与 bootargs：DTB 正确仍不等于实际参数正确

`6df0f28f` 在 Megrez 上到达 `rootfs is ready`，随后 `/init` 以
`ENOENT` 失败。根因不是 initramfs 没有被解包，而是 U-Boot RAM 中
陈旧的 `bootargs` 覆盖了 DTB `/chosen/bootargs`，使 `init=/init`
没有进入内核。

这一节讲清：

- U-Boot 如何修改 `/chosen`；
- 为什么只改 DTB 不足以改变最终参数；
- 为什么固件的易失状态也是实验输入。

#### 五、PID 1：把“内核启动”推进到用户态

冻结候选 `3ef99e6bd` 和修正后的易失 bootargs 在真机上依次观察到：

1. rootfs ready；
2. PID 1 进入 U-mode；
3. 首次 load page fault 被处理；
4. PID 1 到达 `openat`；
5. `write(fd=1, requested=50)` 返回 50。

这一节是文章最强的基础启动结论。文章不借此扩大为完整板级支持。

#### 六、受控恢复：让实验结束在已知状态

文章说明这次真机流程为什么可审计：

- 冻结 Git 提交、镜像和 initramfs 身份；
- 核对大小、SHA-256、CRC 和内存范围；
- 使用 RAM-only 参数，不写入持久 U-Boot 环境；
- 每个冻结候选只发送一次 `booti`；
- 启动后转为被动观察；
- 保留外部恢复能力；
- 记录后续新 OpenSBI/U-Boot 周期和最终 prompt。

### 结尾

结尾不写成成果宣言，而是总结三个可复用方法：

1. 先定义成功边界，再开始真机实验；
2. 模拟器用来收窄软件问题，不能替代真实硬件证据；
3. 用冻结身份、单变量实验和第一个缺失里程碑抵抗误判。

最后明确说明：这是一项受控开发分支上的 Megrez bring-up 结果，不代表
Asterinas 已正式支持该开发板。

## 文章呈现

文章保持现有 Jekyll 技术博客风格，不增加语言切换脚本和头图。

使用以下元素：

- 一个响应式 HTML/CSS 启动链：
  `OpenSBI → U-Boot → Image/DTB → OSTD/SMP → rootfs → PID 1`；
- 三张以内的紧凑表格：
  - 启动产物与职责；
  - 关键里程碑与能证明的结论；
  - QEMU 门禁与真机证据边界；
- 少量经过脱敏的日志片段；
- `notice--info` 表示概念边界；
- `notice--warning` 表示禁止外推的结论；
- 只展示解释关键决策所需的最小代码或链接器片段。

不加入：

- AI 生成图片；
- 外部 JavaScript；
- 原始串口日志下载；
- 不能公开访问的代码链接；
- 与基础启动主线无关的后续设备工程。

## 文件与职责

### `_pages/about.md`

- 在 Blog 列表前加入首页提示卡；
- 使用 `{% post_url 2026-07-23-booting-asterinas-riscv-megrez %}`；
- 不改变原有博客循环。

### `_sass/_homepage.scss`

- 只定义 `.latest-work-card` 及其子元素；
- 提供桌面与窄屏布局；
- 沿用现有颜色变量、字体和圆角；
- 不修改全局标题、正文或链接规则。

### `assets/css/main.scss`

- 仅增加对 `homepage` partial 的导入。

### `_posts/2026-07-23-booting-asterinas-riscv-megrez.md`

- 保存中文文章、frontmatter、局部启动链 markup 和必要的文章内样式；
- 使用公开的 Asterinas 与 Milk-V 官方资料作为背景链接；
- 使用本地证据的脱敏摘录支撑真机结论。

### `docs/audits/`

- 保存内部主张支持矩阵与安全措辞；
- `_config.yml` 已排除 `docs`，这些文件不会进入公开站点。

## 构建数据流

```text
about.md 的 post_url
        ↓
Jekyll 查找指定 _posts 文件
        ↓
Markdown / Liquid / SCSS 构建
        ↓
_site 首页提示卡 ─────→ _site 中文技术文章
        ↓                         ↓
桌面与移动端浏览器验证 ←──────────┘
```

`post_url` 是有意选择的失败即报错机制。文章文件名或日期不匹配时，Jekyll
构建应失败，而不是生成一个不可见的错误 URL。

## 失败处理

- Markdown、Liquid 或 SCSS 无法构建：不提交实现变更；
- 首页链接不能到达文章：修正 `post_url` 与文件名后重新构建；
- 移动端启动链溢出：降为两列或单列，不使用横向页面滚动；
- 外部链接失效：优先替换为官方稳定入口；
- 某条实板主张不能追溯到证据页：删除或降级措辞；
- 发现 USB、framebuffer 或正式支持等越界内容：在公开文章中移除；
- `_site/` 仅作为生成结果检查，不作为源文件修改。

## 验证

### 内容门禁

- JSON 主张矩阵通过 `jq` 解析；
- 扫描公开首页和文章，确保没有越界设备主题；
- 扫描 `world first`、`first-ever`、`official support`、
  `production-ready` 等禁止表述；
- 强结论逐项对应证据页或官方公开资料；
- 私有路径、串口标识和私有仓库 URL 不进入公开内容。

### 构建门禁

- 运行 `bundle exec jekyll build`；
- 确认生成首页包含提示卡；
- 确认提示卡链接到生成后的文章 URL；
- 确认文章 frontmatter、标题层级、代码块、表格和提示块正确；
- `git diff --check` 无空白错误。

### 浏览器门禁

- 桌面视口检查首页和文章；
- 移动端视口检查首页提示卡与启动链重排；
- 点击首页提示卡并到达文章；
- 页面没有横向溢出；
- 浏览器控制台没有错误；
- 截图检查文章第一屏、启动链和一处证据表格。

## 完成标准

只有同时满足下列条件才认为本地主页更新完成：

1. 首页出现已确认的 C 型 Latest Systems Work 提示卡；
2. 卡片能够到达中文文章；
3. 文章完整讲清六个基础启动转折点；
4. 文章不展开被排除的设备工程；
5. 每个强主张都能由本地证据或官方公开资料支撑；
6. Jekyll 构建通过；
7. 桌面与移动端浏览器检查通过；
8. 设计、审计和实现变更均保持在当前仓库内，未执行远端发布。

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

把一个内核放进开发板内存，然后看到一句 `Starting kernel ...`，算不算已经启动了一个操作系统？

对我们（TankTechnology）来说，答案是否定的。那一行只说明
[U-Boot 的 `booti`](https://docs.u-boot.org/en/v2024.01/usage/cmd/booti.html)
接受了镜像并把控制权交了出去。它没有证明 Asterinas 建立了可用的地址空间，
没有证明 Rust 内核已经运行，更没有证明第一个用户进程真的执行过指令。

我们把这次 Milk-V Megrez 实板实验的成功判据定得更具体：Asterinas 必须进入
`riscv_boot`，完成 OSTD 和四个 hart 的初始化，准备好 rootfs，让 PID 1
进入 U-mode 并执行第一批系统调用；实验结束时，还要能够回到已知的固件状态。

<div class="asterinas-boot-chain" aria-label="Asterinas 在 Megrez 上的基础启动链">
  <div class="asterinas-boot-chain__stage">OpenSBI</div>
  <div class="asterinas-boot-chain__stage">U-Boot</div>
  <div class="asterinas-boot-chain__stage">Image/DTB</div>
  <div class="asterinas-boot-chain__stage">OSTD/SMP</div>
  <div class="asterinas-boot-chain__stage">rootfs</div>
  <div class="asterinas-boot-chain__stage">PID 1</div>
</div>

这篇文章不复述一串成功命令，而是沿着几次真正改变判断的转折点，解释我们如何
把“没有输出”逐步收窄成一个可命名、可复现、可验证的问题。

## `Starting kernel ...` 之后还有多远

真机启动首先是一条跨越多个软件世界的控制流。每一层都可能打印自己的日志，
但上一层的成功不能替下一层作证。

| 阶段或产物 | 在这次启动中的职责 | 不能单独证明什么 |
| --- | --- | --- |
| OpenSBI | 提供 RISC-V M-mode 固件接口，把执行环境交给下一阶段 | Asterinas 已经建立地址空间 |
| U-Boot | 从内存读取启动产物，解析镜像格式并执行一次 `booti` | 内核入口之后仍然存活 |
| 平坦 Image | 承载按链接布局导出的 Asterinas 内核 | DTB、参数和根文件系统正确 |
| DTB | 描述 hart、内存和 `/chosen` 等硬件与启动信息 | U-Boot 中的易失参数没有覆盖它 |
| initramfs | 提供早期 rootfs 与 `/init` | PID 1 已经进入用户态 |
| Asterinas | 建立地址空间、初始化 OSTD 与组件并运行用户进程 | 超出本次受控范围的板级能力 |

开发机负责构建 ELF、Image 和 initramfs；板上的 OpenSBI 与 U-Boot 负责早期
固件环境和启动交接；Asterinas 接手之后，才开始证明属于操作系统本身的边界。
[Asterinas Book](https://asterinas.github.io/book/kernel/) 介绍了内核的构建与
运行入口，而 Megrez 的公开硬件资料可以从
[Milk-V 的资源页](https://milkv.io/docs/megrez/getting-started/resources)
取得。两类资料给出背景，实板日志则负责回答“这一个候选到底走到了哪里”。

{: .notice--info}
**关键区别：**QEMU 可以直接装载 ELF，并让调试器观察符号；U-Boot 的 `booti`
面对的是具有约定头部和内存布局的平坦 Image。两条启动路径共享内核代码，却
不是同一个加载契约。

## 三个世界：开发机、固件与 Asterinas

这三个世界的输入必须逐项对齐。

在开发机上，链接器决定入口代码、早期页表和各段之间的相对位置；导出工具把
链接结果变成固件要读取的平坦文件。在固件中，U-Boot 把 Image、DTB 和
initramfs 放入互不重叠的内存范围，并用当时 RAM 中的参数修订启动信息。进入
Asterinas 后，启动汇编使用链接时的布局建立最初映射，然后才有条件进入 Rust、
初始化 OSTD 并解释 DTB。

这意味着一个候选并不只是“某次编译生成的 Image”。它至少由 Git 提交、构建
配置、Image、initramfs、DTB 和固件易失状态共同定义。少记其中一项，就可能
在下一次实验中得到表面相似、实则输入不同的结果。

RISC-V 的 Linux 启动镜像有明确的
[Image header 约定](https://docs.kernel.org/6.1/riscv/boot-image-header.html)；
内核被调用时的 hart 状态、`a0`/`a1` 参数和地址映射也受
[RISC-V 启动要求](https://docs.kernel.org/next/arch/riscv/boot.html)
约束。我们使用 **Linux Image v0.2** 的文件契约，不是为了把 Asterinas
变成 Linux，而是为了让现有固件能够以双方都理解的格式完成交接。

## 合法的镜像头为什么仍会移动内核

第一个真正隐蔽的问题来自 64 字节镜像头。

早期导出工具先按 ELF 的链接布局生成 raw image，再在文件最前面插入
64 字节 Linux Image header。这样生成的文件对 U-Boot 来说是合法的：
magic、版本和大小都可以通过检查，`booti` 也愿意跳转。但对 Asterinas
启动代码来说，文件里的所有内容都相对链接地址整体后移了 `0x40`。

问题最容易出现在早期页表上。启动汇编按照链接时确定的相对位置寻找页表，
而固件实际装载的字节已经向后移动；入口附近还能执行，不代表随后读取到的
页表就是链接器安排的那一页。格式正确与布局正确，是两个独立条件。

最终修复不是在启动代码中补偿 `0x40`，而是让 header 从一开始就属于链接
布局。这样，入口、段边界和早期页表的相对位置在 ELF 与 Image 两种视图中
保持一致。导出工具的职责也随之收窄为三件事：验证已有 header、抽取可加载
范围、按链接布局补零；它不再在链接完成后改变内核的坐标系。

这条经验很朴素：不要只问“固件是否接受了文件”，还要问“固件装载后的每个
关键字节，是否仍位于链接时承诺的位置”。

## 把“无输出”拆成第一个缺失边界

修正镜像布局以后，下一类失败仍然可能表现为串口上没有新字符。如果把它统称
为“卡死”，调试空间会同时包含入口、页表、异常、内存分配和日志路径，几乎
无法有效推进。

我们的做法是在破坏性最小的位置加入有限的进度标记，并始终追问
**第一个缺失边界**：

1. 是否已经执行 Asterinas 的启动汇编；
2. 写入 `satp` 之前，frame allocator 是否返回了合法页帧；
3. 页表切换以后，高半地址跳转是否完成；
4. 物理内存的线性映射是否覆盖了随后访问的范围；
5. 是否终于打印出 `Enter riscv_boot`，证明控制流进入 Rust 启动入口。

`satp` 是这里最有分量的分界线之一。写入它之前可用的地址解释，与启用新页表
之后并不相同；高半地址、页表页的物理地址和线性映射只要有一个假设不成立，
后续日志就不会出现。另一方面，Megrez 内存较大，frame allocator 的初始化
可能需要时间。没有中间边界时，“仍在工作”和“已经停住”看起来完全一样。

这些标记的价值不在于多打印几行，而在于每一行都排除一组假设。当
`Enter riscv_boot` 出现以后，我们就不再回头怀疑 U-Boot 有没有跳到入口；
问题域已经进入 OSTD 与组件初始化。

## OSTD、四个 hart 与 rootfs

进入 `riscv_boot` 后，我们继续观察到：

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

这里的 `3 processors` 指另外三个 application processor；加上一直继续运行的
boot hart，这次真机启动共有四个 hart。随后
`OSTD initialized. Preparing components.` 把证据推进到 OSTD 初始化之后，
`[kernel] rootfs is ready` 又说明内核组件已经走到根文件系统可用的边界。

[Asterinas 0.17.0 的发布说明](https://asterinas.github.io/2025/12/19/announcing-asterinas-0.17.0.html)
记录了项目在 RISC-V、PLIC 和 SMP 等方向的公开进展；我们的结论则更窄：
上述四 hart、OSTD 和 rootfs 边界是在这一块 Megrez、这一受控候选上实际
观察到的，不是从模拟器运行推导出来的。

## DTB 正确，实际 bootargs 仍可能错误

提交 `6df0f28f` 对应的候选已经到达 `[kernel] rootfs is ready`，但随后启动
`/init` 得到 `ENOENT`。这很容易被解释成“initramfs 没有解包”或“文件系统
实现有问题”，实际根因却在更早的固件状态。

构建时提供的 DTB 已经在 `/chosen/bootargs` 中写入 `init=/init`。然而
U-Boot RAM 中还保留着一份陈旧的 `bootargs`；执行 `booti` 时，固件用这份
易失值更新了 `/chosen`，使真正交给 Asterinas 的参数里丢失了 `init=/init`。
因此，检查磁盘上的 DTB 正确并不足以证明运行时 DTB 正确。

修正方法也刻意保持为 RAM-only：为当前受控会话设置正确参数，不保存到持久
环境。这样既能验证根因，也不会把一次实验状态变成开发板以后每次开机的默认
输入。

这个转折点改变了我们的实验模型：固件不仅是负责跳转的“前置程序”，它的
易失状态也是候选身份的一部分。对 DTB 的静态检查必须和 `booti` 前的实际
参数核对放在一起。

## PID 1：从内核启动到用户态

修正易失参数后，冻结提交 `3ef99e6bd` 的候选把证据链从“内核已经起来”
推进到了“第一个用户进程已经运行”。

| 观察到的里程碑 | 它能证明的结论 |
| --- | --- |
| `stage=user_enter` | PID 1 已进入 U-mode |
| 首次 load page fault 返回 `outcome=resolved` | 用户地址空间的第一次按需映射得到处理，执行可以继续 |
| `stage=user_first_syscall id=56` | 用户进程已经越过系统调用边界并到达 `openat` |
| `stage=user_first_write_returned ... result=50` | 一次请求 50 字节的 `write` 已成功返回 50 |

这几行比一条内核欢迎语更重要。它们把地址空间、异常处理、用户态切换和系统
调用连接成了连续证据。尤其是 `write` 返回 50，说明 PID 1 不只是被创建，
而是已经执行到了第一段可观察的用户逻辑。

但它仍是一个经过控制的最小用户态边界。我们没有把这次结果外推为完整应用
兼容性、长期稳定性或完整的板级能力；本文要回答的是更基础的问题：能否在
真实板上把 Asterinas 从固件交接带到一个实际执行系统调用的 PID 1。答案是
可以，而且每个关键转折点都有对应证据。

## 一次可审计的真机启动

真机 bring-up 不仅要到达目标，还要避免把偶然结果写成结论。我们为每次冻结
候选记录提交身份，并在发送启动命令前核对 Image 和 initramfs 的大小、
SHA-256、板端 CRC 以及内存范围，确认各产物没有重叠。

实验纪律如下：

1. 提交、构建配置、Image、initramfs、DTB 与 RAM-only bootargs 一起冻结；
2. 模拟器预检只作为软件门禁，不替代实板观察；
3. 每个冻结候选只发送一次 `booti`，跳转后保持被动观察；
4. 不在运行中用额外输入“帮助”候选越过未知状态；
5. 保留独立恢复能力，并把新的固件周期作为结束边界。

同一受控会话稍后出现了完整的新固件周期：

```text
DDR type:LPDDR5;Size:16GB,Data Rate:6400MT/s
DDR self test OK
OpenSBI v1.5
U-Boot 2024.01
=>
```

这段记录证明上一候选之后，开发板重新经过 DDR、OpenSBI 和 U-Boot，并停在
可识别的 U-Boot prompt。由于原始串行记录本身没有墙钟时间，我们只把它表述
为受控会话中观察到的新固件周期和安全结束状态，不从日志单独推导更强的因果。

| 证据来源 | 适合证明 | 不适合替代 |
| --- | --- | --- |
| QEMU 门禁 | 镜像能执行、软件路径可复现、常见回归未出现 | 固件交接与真实 hart、内存行为 |
| 静态检查 | header、哈希、大小、地址范围与产物身份 | 运行时控制流 |
| Megrez 日志 | 真实固件交接、OSTD/SMP、rootfs 与 PID 1 边界 | 未被日志直接观察的长期性质 |

## 值得保留的方法

这次工作最终留下的，不只是一份能启动的 Image。

**先定义成功，再开始实验。** 如果目标只是看到 `Starting kernel ...`，
固件一跳转就会过早宣布成功；如果目标明确写到 PID 1、首次系统调用和恢复
边界，证据采集就会围绕真正的操作系统问题展开。

**用模拟器收窄问题，用实板确认事实。** QEMU 适合快速验证共享的软件路径，
但它不能替 Megrez 证明固件状态、真实内存布局和多 hart 的运行结果。我们把
二者组织成门禁与证据的关系，而不是互相替代。

**持续寻找第一个缺失里程碑。** 从 Image header 到 `satp`，从
`Enter riscv_boot` 到 rootfs，再从 `ENOENT` 到 PID 1，每次只移动第一个
未知边界。这样，失败不会退化成模糊的“没启动”，成功也不会膨胀成没有依据的
“全部可用”。

**冻结身份，保持单变量。** 提交、哈希、CRC、内存范围和易失参数都进入实验
记录；一个候选只执行一次启动。可重复的身份让后来的每条日志都能回到明确的
软件与固件输入。

## 边界与参考资料

本文记录的是 TankTechnology 在受控开发分支上完成的一次 Milk-V Megrez
bring-up：Asterinas 从 U-Boot `booti` 进入内核，建立早期地址空间，完成
OSTD 与四 hart 初始化，准备 rootfs，并让 PID 1 进入 U-mode、处理首次缺页
和执行系统调用。

{: .notice--warning}
**结论边界：**这不代表 Asterinas 对 Megrez 的上游板级支持，也不说明超出
本文基础启动链的能力、性能或长期稳定性。它证明的是一个冻结候选在一块真实
开发板上到达了这些明确、连续、可审计的边界。

进一步阅读：

- [Asterinas Book: Getting Started](https://asterinas.github.io/book/kernel/)
- [Announcing Asterinas 0.17.0](https://asterinas.github.io/2025/12/19/announcing-asterinas-0.17.0.html)
- [U-Boot `booti` command](https://docs.u-boot.org/en/v2024.01/usage/cmd/booti.html)
- [Linux: Boot image header in RISC-V](https://docs.kernel.org/6.1/riscv/boot-image-header.html)
- [Linux: RISC-V Kernel Boot Requirements and Constraints](https://docs.kernel.org/next/arch/riscv/boot.html)
- [Milk-V Megrez resources](https://milkv.io/docs/megrez/getting-started/resources)

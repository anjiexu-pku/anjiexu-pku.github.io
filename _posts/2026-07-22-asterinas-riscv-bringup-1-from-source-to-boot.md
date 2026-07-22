---
title: "从源码到 riscv_boot：为什么「编译成功」离「内核启动」还有一万个坑"
date: 2026-07-22
categories:
  - tech
  - os
tags:
  - asterinas
  - riscv
  - kernel
  - boot
  - bringup
  - operating-system
excerpt: "把 Asterinas 移植到 RISC-V 真机时，编译器说一切正常、QEMU 里也跑到了用户态——但真机只输出一行 Starting kernel ... 就沉默了。这篇文章从第一性原理出发，逐层拆解构建机、固件、内核三个世界之间的隐秘契约。"
---

2026 年 7 月，我们在 Milk-V Megrez 开发板上尝试启动 Asterinas 内核。

[Asterinas](https://github.com/TankTechnology/asterinas-riscv) 是一个 Linux 兼容的通用操作系统内核，用 Rust 写成。它的核心架构约束是 framekernel——所有 `unsafe` 代码被隔离在名为 OSTD 的框架层中，内核主体（文件系统、网络栈、进程管理）完全用 safe Rust 实现，已经在 x86-64 上稳定运行。我们正在做的是把它移植到 RISC-V 架构上。

Megrez 是一块搭载 EIC7700 SoC 的 RISC-V 开发板：4 核、Sv48 分页、16 GiB LPDDR5、HDMI 输出、FTDI 串口。从软件栈的角度看，它就是一台微缩版的 Linux 机器，只是 CPU 换成了 RISC-V。

我们先把 Asterinas 编译成了 RISC-V 目标。`cargo build --target riscv64` 返回零。然后在 QEMU 里跑——`make run_kernel` 能看到 `Enter riscv_boot`，能看到 OSTD 初始化，能一路走到 initramfs 里的 PID 1 打印 `Hello from RISC-V userspace!`。

然后把同一份 Image 搬到 Megrez 上。U-Boot 校验了 header、加载了 Image、接受了 DTB 和 initramfs。跳转——然后板子输出了一行：

```text
Starting kernel ...
```

之后 120 秒，什么都没有。没有 `Enter riscv_boot`，没有 panic，没有自动复位。**纯沉默。**

这篇文章想回答一个具体的问题：从 Rust 源码到 RISC-V 开发板上第一条内核日志，中间到底发生了什么？为什么编译器说没问题、QEMU 说没问题、U-Boot 说没问题——真机却沉默了？

答案不在任何一个组件的 bug 里。答案在它们之间的契约差异里。为了系统地理解这个问题，我们用一个三层模型来组织思路。

## 1. 三世界模型：为什么构建机、固件、内核互相不理解

整个 OS 移植过程横跨三个彼此独立的计算上下文。我们把它叫做"三个世界"：

{% include asterinas-three-worlds.html %}

这三个世界各自有一套关于"可执行代码应该长什么样"的假设。关键在于：**这些假设不是同一个人设计的，它们之间没有协商机制。** 构建机生成的东西不符合固件预期，固件不会报错——它只会把错误的字节放到正确的地址然后跳转。之后的一切都不可预测。

这不是设计缺陷。U-Boot 不想知道自己加载的是什么内核——Linux、FreeBSD、Asterinas——只要 Image header 格式合规就行。链接器不想知道内核最终在哪块板子上跑——符号地址对了就行。OpenSBI 不想知道上层跑的是什么 OS——只要 `ecall` 参数合法就行。这种分层让每个组件可以独立演进，代价是**契约的正确性完全由移植者负责，没有任何工具能自动检查。**

下面沿着代码的实际流动方向，逐个看这三个世界里各自的逻辑、它们之间的契约、以及我们在 Megrez 上违反过哪些。

## 2. 世界一：构建机——从 `.rs` 到平坦 Image

构建机的任务是吃掉 Rust 源码，产出一个可以在 RISC-V 机器上执行的字节序列。这件事听起来简单——编译、链接、打包——但"怎么打包"完全取决于谁来加载这个字节序列。

### 2.1 QEMU 认识 ELF，U-Boot 不认识

**Crux：同一个内核，QEMU 的 loader 会解析 ELF 的段表和符号表，把代码精确放到链接器指定的地址。U-Boot 不理解 ELF——它只认识从文件偏移 0 开始的连续字节流。构建机必须为 U-Boot 生成正确格式的产物，而不是为 QEMU。**

一台 x86 构建机上，Rust 编译器产出的 RISC-V ELF 包含丰富的元数据：段表（program headers）告诉 loader 哪些字节加载到哪个物理地址、哪些需要清零（`.bss`）；节表（section headers）保留符号名和调试信息；`e_entry` 字段指向 `_start`。

QEMU 内置了一个 ELF loader。用 `cargo osdk run` 启动时，QEMU 解析 ELF 的全部元数据，把每个段精确放到链接器指定的地址上。QEMU 路径天然知道 `_start` 在哪、`sv48_boot_l4pt` 在哪——它理解 ELF 的语义。

U-Boot 不一样。它的 `booti` 命令期望一个**平坦的 Linux Image**：从头到尾没有任何元数据的连续字节流。根据 Linux 内核文档 `Documentation/arch/riscv/boot-image-header.rst`，这个 Image 的前 64 字节是一个标准 header，包含 magic number（`RSC\x05`）、image size、load offset 和 flags。U-Boot 跳过 header 后直接把余下所有字节加载到连续的物理地址。

两种格式不是谁比谁好——ELF 追求灵活性（任意复杂的加载布局），平坦 Image 追求简单（bootloader 不需要解析 ELF）。但当你在 QEMU 上用 ELF 开发、然后把产物转成 Image 给 U-Boot 时，转换过程中的任何错误都是静默的。

### 2.2 概念插播：QEMU 能帮我们做什么，不能帮我们做什么

在继续之前，需要厘清 QEMU 的角色——因为后面每一节都会涉及"QEMU 通过了但真机失败了"的模式。

QEMU 的全称是 Quick Emulator。它是一个**机器模拟器**（machine emulator），而不是虚拟机（virtual machine）。虚拟机利用 CPU 硬件虚拟化扩展，让 guest 指令直接在物理 CPU 上执行——它要求 host 和 guest 是同一种 CPU 架构。QEMU 用软件（一个叫 TCG 的动态二进制翻译器）把 guest 的每条指令翻译成 host CPU 指令，所以它可以在 x86 上运行 RISC-V、ARM、MIPS 甚至 m68k 的内核。

在 RISC-V 平台上，QEMU 提供了一台名为 `virt` 的虚拟机器。它模拟了 CPU 核心（指令行为通过了 RISC-V 兼容性测试套件）、字节精确的内存、完整的 MMU 和页表 walker、标准外设（NS16550A UART、virtio 块设备/网络、PLIC、CLINT）、以及内嵌的 OpenSBI 固件。这些都是 RISC-V 生态中通用的组件，QEMU 对它们的模拟是可信的。

但 QEMU `virt` 不模拟的东西同样重要：

- **EIC7700 特有的微架构行为**。QEMU 的 CPU 是通用 RISC-V 实现。真实的 EIC7700 硅片可能存在勘误（erratum）——页表 walker 的 A/D 位更新时序、指令发射顺序、缓存一致性协议，都可能与 QEMU 的简单模型不同。
- **厂商固件**。Megrez 真机跑的是厂商定制的 OpenSBI 1.5 和 U-Boot，不是 QEMU 内嵌的主线版本。厂商可能修改了 SBI 行为、patch 了 DTB 生成逻辑、或添加了非标准的安全监控代码。
- **真实设备树**。QEMU 自动生成的 `virt` DTB 中，UART 的 compatible 是 `ns16550a`。Megrez 板载 DTB 描述的是 `snps,dw-apb-uart`——寄存器布局完全不同（reg-shift=2、reg-io-width=4 vs NS16550A 的 reg-shift=0、reg-io-width=1）。
- **物理时序**。在 QEMU 里，16 GiB identity map 循环瞬间完成；在真机 1.6 GHz 的 EIC7700 上，这个操作需要逐个巨页推进，串口能看到明显的进度。
- **电源、时钟、复位**。QEMU 没有 PMIC、没有 PLL 树、没有硬件看门狗。卡死的 QEMU 进程用 `kill -9` 解决；卡死的真机需要人走到板子前按复位按钮。

我们用 QEMU 做了三件事：作为**开发环境**（秒级反馈循环）；作为**软件门禁**（QEMU 失败一定省一次真机尝试）；作为**可配置实验平台**（比如用 `-cpu rv64,svade=true` 关闭硬件 A/D 更新来测试内核的对应路径——这在真机上做不到，无法把 EIC7700 的 Svade 关掉）。

但 QEMU 有一个硬边界：**QEMU 通过只意味着软件路径可能正确，不代表硬件路径正确。**

### 2.3 v3 的 64 字节：一个精确定位的错误

搞清楚 QEMU 和 U-Boot 的格式差异之后，来看我们在 Megrez bringup 中犯过的最根本实现错误。

当时的流程是：链接器产出 ELF，`_start` 位于文件偏移 0。然后一个 Python 脚本在文件**前面**拼接 64 字节的 RISC-V Linux Image header。结果：原有内容整体后移 64 字节。

{% include asterinas-image-layout.html %}

这个错误的后果是精确的。硬件页表 walker 按 `satp` 寄存器的值读根页表。`satp` 的 PPN 字段按 4 KiB 对齐——它永远假设根页表在一个 4 KiB 对齐的物理地址上。链接器把 `sv48_boot_l4pt` 放在了偏移 `0x1000`（`.balign 4096` 保证的）。但拼接 header 后，根页表实际在文件偏移 `0x1040`。

`satp` 指向 `0x1000`，数据在 `0x1040`。硬件读到的是上一页尾部的垃圾，而非合法的页表项。**页表第一项就无效，整个地址翻译链在第一级就断了。** CPU 不会报错——取到无效 PTE、触发 page fault、fault handler 还没初始化、double fault、triple fault、静默停止。

修正方案参考了 Linux 内核自身的实现（`arch/riscv/kernel/head.S` 中的 `_start` 定义）：**header 必须是汇编源码的一部分，由链接器保证布局。** `make_booti.py` 不向前插入任何字节。

```asm
# bsp_boot.S 的开头
.balign 8
.global _start
_start:
    .4byte 0x0400006f              # jal zero, +0x40 — 跳过 header
    .4byte 0                       # reserved
    .8byte 0x200000                # load offset (2 MiB)
    .8byte KERNEL_IMAGE_SIZE       # image_size
    # ... 余下 header 字段 ...

bsp_boot_body:
    .if (bsp_boot_body - _start) != 0x40
        .error "RISC-V Linux Image header must be exactly 64 bytes"
    .endif
```

第一条指令 `jal x0, +0x40` 跳转到偏移 0x40，CPU 执行流自然越过 header。对链接器来说 `_start` 就是文件偏移 0，跟在其后的 `.balign 4096` 保持各符号的 4 KiB 对齐。`make_booti.py` 现在只做三件事：验证、抽取、补零——每个已知偏移在构建时就被自动检测，编译不过就是错的。

### 2.4 DTB 和 initramfs：内核还需要什么

构建机产出的不只有 Image。一次完整启动还需要两样东西。

**DTB（Device Tree Blob）** 是一个二进制数据结构，描述硬件平台的组成：有哪些 CPU 核心、内存从哪到哪、串口在哪个地址、中断控制器是什么型号。在 x86 世界，这个功能由 ACPI 和 PCI 枚举承担——BIOS/UEFI 在启动时探测硬件，填入标准表中。嵌入式/RISC-V 世界没有统一的自动发现协议，每块板子的外设组合都可能不同。Device Tree 就是为解决这个问题而设计的：一个与平台无关的硬件描述格式，内核通过解析 DTB 了解当前平台。《Devicetree Specification》定义了它的完整语法。

在 Megrez 上，DTB 由厂商提供（`eic7700-milkv-megrez.dtb`）。U-Boot 在跳转前加载它到内存并修补 `/chosen` 节点——写入 `bootargs`（内核启动参数）、`linux,initrd-start` 和 `linux,initrd-end`（initramfs 物理地址范围）。Asterinas 在 `riscv_boot` 中收到 DTB 指针，从这里开始认识硬件。DTB 的内容必须与内核的驱动假设一致——后面会看到，UART 的 compatible 字符串不匹配直接导致 console 不可见。

**initramfs（Initial RAM Filesystem）** 是一个压缩的 cpio 归档。它的作用很朴素：在内核还没挂载真正根文件系统之前，提供一个最小可用文件系统，其中至少包含一个 `/init` 程序——内核完成自身初始化后执行的第一个用户态进程（PID 1）。Megrez bringup 初期使用的 initramfs 只有约 570 字节，一个极小的 RISC-V 诊断程序：打开 `/dev/ttyS0`、打印 marker、持续自旋。没有 shell——只证明"用户态代码被执行了"。

Image + DTB + initramfs，构成了一次真机启动的三类输入。

### 2.5 物理内存布局：为什么 Image 必须在 `0x80200000`

构建机在链接时硬编码了 `_start = 0x80200000`。这不是随机选的——RISC-V Linux 约定 DRAM 起始地址为 `0x80000000`，Image 偏移 `0x200000`（2 MiB），前 2 MiB 留给 OpenSBI。但 Megrez 的 16 GiB DRAM 不只是"一段连续 RAM"——它被固件、DTB、framebuffer 和外设瓜分了：

{% include asterinas-memory-map.html %}

- Image 不能随便放，因为 `_start = 0x80200000` 是链接时写死的。换地址就得重新链接，而重链接意味着页表符号（`sv48_boot_l4pt` 在 `+0x1000`、`sv39_boot_l3pt` 在 `+0x3000`）全部跟着变——这些偏移是汇编里 `.balign 4096` 保证的，但 linker script 必须和 U-Boot 的加载地址一致。
- initramfs 放在 `0x83000000` 是因为 Image 末尾约在 `0x80cd0610`，下一个安全可用的对齐地址就是这里。
- Framebuffer 是"保留区域"而非"可用内存"——U-Boot 已经初始化了 `0xfd800000` 的 HDMI scanout。Asterinas 如果把这段地址分配给内核堆，屏幕花掉。
- 高位约 500 MiB 被固件保留区、U-Boot LMB、DTB 和 framebuffer 占满，剩下能用的物理内存是中间那一大段——约 13.6 GiB。

## 3. 世界二：固件——为什么内核不能直接接管硬件

构建机产出的字节序列，由固件世界负责加载和跳转。但为什么固件链必须存在？为什么 CPU 上电后不能直接跳到 Asterinas 的 `_start`？

### 3.1 RISC-V 的三级特权

**Crux：CPU 上电时在最高特权级 M-mode。需要一个机制把控制权安全地逐级传递下去——每一级只能通过 `ecall` 与相邻级通信。**

RISC-V 定义了三种特权级：**M-mode**（Machine mode，最高特权级，可访问所有硬件寄存器、配置 PMP），**S-mode**（Supervisor mode，内核所在，可使用 MMU 但不能碰 machine timer），**U-mode**（User mode，用户程序，连页表都不能碰，只能通过 `ecall` 请求 syscall）。这三种不是"功能开关"，而是三种互相隔离的硬件执行上下文。分层不是 RISC-V 独有的——x86 有 Ring 0–3，ARM 有 EL3–EL0——底层原因一致：**如果任何代码都能改写任何寄存器，一个 bug 就让机器物理损坏。**

分层带来的代价是启动时必须逐级交接控制权。这就是固件链存在的根本原因。

### 3.2 上电后到底发生了什么

{% include asterinas-privilege-stack.html %}

一台 RISC-V 机器上电时，PC 指向芯片内 ROM 的固定地址。这段 Boot ROM 代码是厂商烧进去的，它做的第一件事是初始化 DDR 控制器——DDR 需要训练（调整时序参数匹配特定 PCB 走线的电气特性），训练完成之前 DRAM 不可用，连栈都没有。这是"上电"和"操作系统启动"之间最根本的物理鸿沟。

DDR 就绪后，Boot ROM 从 SD 卡加载下一阶段固件到 DRAM——在 Megrez 上，这一阶段是 **OpenSBI**，驻留在 M-mode。它向 S-mode 软件（U-Boot，然后是 Asterinas）提供标准化的 SBI 服务：`sbi_console_putchar`（控制台输出）、`sbi_set_timer`（定时器）、`sbi_send_ipi`（核间中断）、`sbi_system_reset`（系统复位）。这些服务是内核访问 M-mode 功能的唯一合法通道，调用约定由《RISC-V SBI Specification》v2.0 定义。

OpenSBI 初始化完成后，把 **U-Boot** 作为 S-mode payload 启动。U-Boot 从 SD 卡读取 Image、DTB 和 initramfs 到 DRAM 约定地址，修补 DTB 的 `/chosen` 节点，然后执行 `booti` 跳转到内核入口 `_start`。

### 3.3 固件链对 Asterinas 的具体影响

这个链条不是抽象的"启动流程"——每个环节都直接影响了 Asterinas 的行为。

**OpenSBI 是启动最早期的唯一可用外设。** 在 `riscv_boot` 执行第一条 Rust 日志之前，boot assembly 完全依赖 SBI 的 `sbi_console_putchar` 输出调试 marker。没有它，沉默悬崖就是绝对黑箱。同时 OpenSBI 驻留在 DRAM 底部（`0x80000000` 起始），Asterinas 的 frame allocator 必须通过解析 DTB 的 `/reserved-memory` 来避开这个区域。

**U-Boot 的 bootargs 覆写行为是一个隐蔽的陷阱。** `booti` 命令在执行时会用 RAM 环境变量 `bootargs` 覆写 DTB 中的 `/chosen/bootargs`（这是 U-Boot 源码 `cmd/booti.c` 的实现逻辑，不是 DTB 规范的要求）。我们在 `6df0f28f` 轮次中栽在这里：DTB 里写了 `init=/init`，但 U-Boot RAM 环境中残留了不带此参数的旧 `bootargs`。跳转后内核看到的启动参数是旧值——最终 init ENOENT，内核到了 rootfs 却找不到 `/init`。

U-Boot 修正后的 bootargs 契约非常简单：`cpu_no_boost_1_6ghz loglevel=info init=/init`。但必须同时在 `setenv bootargs`（RAM 环境）和 `fdt set /chosen bootargs`（DTB）中设置为同一精确值，且 `booti` 前分别打印对比——永不执行 `saveenv`。

### 3.4 ecall：唯一合法的跨层通道

S-mode 调用 M-mode 服务的机制是 `ecall`。调用约定：`a7` 放服务编号，`a0`–`a6` 放参数，然后执行 `ecall`。CPU 硬件自动提升特权级到 M-mode、跳转到 OpenSBI 的 trap handler、OpenSBI 检查 `a7` 执行对应服务（比如 `SBI_CONSOLE_PUTCHAR = 0x01`）、然后 `mret` 回到 S-mode 的下一条指令。

这个过程对 S-mode 代码像一次函数调用——但在硬件层面，特权级、程序计数器、栈指针全部切换了一遍。这也是为什么 `csrw satp` 之后页表出错时连 `ecall` 都无法执行：**`ecall` 本身是一条指令，取指令需要经过页表翻译。页表坏了，`ecall` 也取不到。**

## 4. 世界三：内核——从 `_start` 到 `riscv_boot`

固件完成了自己的工作：Image 在 `0x80200000`，DTB 指针在 `a1`，initramfs 信息在 `/chosen`。接下来，控制权进入内核世界。但此时内核面对的是一个极简环境：没有堆分配器、没有标准输出、没有页表——只有一段汇编和几个寄存器。

### 4.1 概念插播：为什么有虚拟内存和页表

在讨论内核如何建立页表之前，需要先回答：CPU 为什么不直接用物理地址？

早期计算机确实直接用物理地址。但随着三个需求的出现，物理地址变得不够用：

**碎片化。** 进程 C 需要 50 MiB，物理内存总空闲有 56 MiB，但被切割成不连续的两段。没有虚拟内存，C 要么自管理分段，要么启动不了。虚拟内存让内核可以把任意物理页映射到连续的虚拟地址——进程看到连续空间，物理上随意拼接。

**隔离。** 纯物理地址世界，进程 A 可以直接读写进程 B 的数据。虚拟内存给每个进程独立的地址空间，地址 0x1000 翻译到不同的物理页。

**地址空间布局。** 内核希望占据地址空间高半（`0xffff_ff00_0000_0000` 以上），用户程序占据低半。这种布局让内核在陷入用户态时可以直接访问用户内存而不切换页表，同时保护内核不被用户访问。Asterinas 正是一个 **higher-half kernel**。

### 4.2 页表就是字典

虚拟地址翻译本质上是查字典。虚拟地址被拆成 VPN（Virtual Page Number），在页表中查到对应的 PPN（Physical Page Number），拼上页内偏移得到物理地址。

RISC-V Sv48 模式定义了四级页表（《RISC-V Privileged Specification》§4.3）：

```text
| 47..39 | 38..30 | 29..21 | 20..12 | 11..0 |
|  VPN[3] | VPN[2] | VPN[1] | VPN[0] | offset |
   9 bit    9 bit    9 bit    9 bit    12 bit
```

页表项（PTE）的格式：

| 位 | 名字 | 含义 |
|---|------|------|
| 0 | V | 有效位（1 = 有效，0 = 触发 page fault） |
| 1 | R | 可读 |
| 2 | W | 可写 |
| 3 | X | 可执行 |
| 6 | A | 被访问过（Access bit） |
| 7 | D | 被写过（Dirty bit） |

硬件 page table walker 逐级查询：`satp` → L4 页表 → VPN[3] → L3 地址 → VPN[2] → L2 地址 → VPN[1] → L1（叶子）PTE → VPN[0] + offset = 物理地址。整个过程全自动——前提是所有 PTE 都合法。

### 4.3 satp：单向门

{% include asterinas-boot-flow.html %}

回到 `bsp_boot.S`。U-Boot 跳转到 `_start` 时，CPU 在 S-mode，`satp` 寄存器的 MODE 字段为 0——分页未启用，所有地址是物理地址。

启动代码构造了一个最小页表，然后执行：

```asm
csrw   satp, t0        # 写入 satp
```

这一条指令前后，是两个不同的世界。写入前，`0x80200000` 就是 DRAM 的第 0x200000 个字节。写入后，**所有地址立即被解释为虚拟地址——包括取指令的 PC。** 如果页表没有覆盖当前 PC 所在的地址范围，CPU 连下一条指令是什么都无法确定。没有输出，没有 panic，连 SBI ecall 也不行。

这就是"沉默悬崖"：

> 页表出错 = 零输出。不是"乱码"或"输出一半"——是零。

Asterinas 的早期页表建立了三套映射：

```asm
/* sv48_boot_l4pt:
 * entry 0:   identity map 0~512 GiB    (virt == phys)
 * entry 256: linear map 0~512 GiB      (virt = phys + 0xffff_ff00_0000_0000)
 * entry 511: kernel code map           使用 1 GiB 巨页
 */
```

**Identity map**：虚拟地址 = 物理地址。写入 satp 后 PC 还是 `0x8020_0xxx`，必须映射。保证分页开启后代码继续执行。

**High-half map**：虚拟地址 = 物理地址 + `0xffff_ff00_0000_0000`。Asterinas 的所有 Rust 代码、栈、堆都在高半——低半留给用户程序。从用户态陷入时，内核不需切换页表就能访问用户内存。

**Kernel code map**：用 1 GiB 巨页覆盖内核 ELF 的实际占地区域，精确对应代码、数据和栈。

### 4.4 Sv48 还是 Sv39？

RISC-V 定义了两种常见分页模式（《RISC-V Privileged Specification》§4.1.11–4.1.12）：Sv39（三级，39 位，最大 512 GiB）和 Sv48（四级，48 位，最大 256 TiB）。Asterinas 优先尝试 Sv48——作为高半内核，需要 48 位虚拟地址。

检测硬件支持的方法由 RISC-V 规范保证：不支持的 MODE 写入 satp 后会被忽略，读回值不同：

```asm
csrw   satp, t0          # 写 Sv48 + PPN
csrr   t1, satp          # 读回
beq    t0, t1, flush_tlb # 一致 → 硬件接受 Sv48
# 不一致 → 尝试 Sv39
```

QEMU 默认支持 Sv48。EIC7700 也支持——`6df0f28f` 真机验证了。但保留 Sv39 回退仍然有意义：一次编译的 Image 可能在多种 RISC-V 平台上运行。

### 4.5 切换到高半

satp 被接受、TLB（Translation Lookaside Buffer，页表缓存）被 `sfence.vma` 清空后，CPU 仍在 identity map 内执行。下一步是主动切到高半：

```asm
li     t1, KERNEL_VMA_OFFSET       # 0xffff_ff00_0000_0000
lla    sp, boot_stack_top
or     sp, sp, t1                  # SP = phys | KERNEL_VMA_OFFSET
lla    t0, bsp_boot_virt - KERNEL_VMA_OFFSET
or     t0, t0, t1
jr     t0                          # 跳转到高半
```

`lla` 拿到的是物理地址（`.boot` 段的链接地址），`or sp, sp, t1` 把 `0xffff_ff00_0000_0000` 或进去。`jr t0` 之后 PC 是 `0xffff_ff00_80xx_xxxx`——一个真正的高半虚拟地址。随后初始化 GP（全局指针），跳转 Rust：

```asm
lla    t0, riscv_boot
jr     t0
```

进入 `riscv_boot()`。第一条 SBI 日志 `Enter riscv_boot` 即将到来。

## 5. A/D 位：QEMU 和真机之间的一个静默差异

### 5.1 为什么需要 A/D 位

**Crux：A/D 位是页替换算法的基础信息来源。但 RISC-V 规范允许硬件不自动更新它们——如果内核假设硬件会更新而真机不更新，page fault 会在启动最早阶段触发，此时 fault handler 还没就绪。**

操作系统管理物理内存的核心任务之一是页替换（page replacement）：物理内存满时，选一个旧页踢出去。A 位（Access bit，PTE 第 6 位）记录"这页最近被访问过吗"；D 位（Dirty bit，PTE 第 7 位）记录"这页被修改过吗"。干净页（D=0）可以直接丢弃，脏页（D=1）必须先写回磁盘。

RISC-V 规范（§4.3.1）定义了硬件自动更新 A/D 位的机制。但规范同时允许硬件不实现——当硬件不支持且 PTE 中 A=0 或 D=0 时，任何对该页的访问都会触发 page fault，由软件 fault handler 手动设置这些位。这个行为由 **Svade** 扩展控制。

QEMU 默认实现了硬件 A/D 更新，所以这类 fault 在 QEMU 上从不出现。但 EIC7700 可能不实现。同一行 `mov [page], value`——QEMU 正常，真机触发 page fault。如果在启动早期（页表刚建立、fault handler 没就绪），结果就是沉默。

### 5.2 QEMU 降级测试

我们的排查方法不是"猜测 EIC7700 有没有 A/D 问题"——而是用 QEMU **主动降级**：`-cpu rv64,svade=true` 强制模拟"硬件不自动更新 A/D 位"。这个配置下内核 panic 了。panic 日志精确定位在页表 walker：启动页表中的巨页 PTE 只设置了 `PTE_V | PTE_R | PTE_W | PTE_X`，没有 A/D 位。

修复：

```asm
PTE_VRWXAD = PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D
```

修复后，`6df0f28f` 在 Megrez 真机上成功跑通了 Sv48 路径。这个过程的教训很明确：

> QEMU 通过了不代表真机能跑，但 QEMU 的降级测试能提前暴露真机才可能触发的 bug。QEMU 不是一个"一次性的模拟环境"——它是一个可以精确控制 CPU 扩展组合的可配置实验平台。

## 6. 沉默悬崖中的 Marker 方法论

回到那条真机日志——`Starting kernel ...` 之后 120 秒空白。

U-Boot 打印这句话只证明四件事：Image/DTB/initramfs 从 SD 卡读出、header 通过校验、`/chosen` 被修补、U-Boot 准备跳转到 `_start`。它不证明之后的任何事——`jal x0, +0x40` 是否执行、页表是否构造正确、satp 是否被接受、identity map 是否覆盖当前 PC、高半切换是否成功、`riscv_boot` 是否被跳转到。

每一个"不证明"都是沉默悬崖的一个可能坠落点。而在这段代码里——从 `_start` 到 `jr t0` 跳转 Rust——**不存在标准输出。** `println!` 需要日志组件初始化，日志组件需要内核启动，内核启动需要先到达 `riscv_boot`。鸡生蛋。

唯一能用的输出手段是 **SBI ecall**——OpenSBI 驻留在 M-mode，`ecall` 指令不经过页表翻译，直接由 CPU 硬件提升特权级并跳转到 M-mode trap handler。Asterinas 在汇编中通过 `ecall`（`SBI_CONSOLE_PUTCHAR`）每次输出一个字符。v5 到 v8 的迭代就是逐步增加 marker——在页表构造后加一个、satp 写入后加一个、线性映射完成 1 GiB 后加一个——把"板子黑屏"拆成可定位的边界。

**v6 的误判：慢不等于死。** v6 的最后 marker 是 `l`（线性映射第一个巨页完成），14 秒无新输出，判断为卡死。v7 用更长的观察窗口和更密集的进度 marker 推翻了这一判断：16 GiB identity map 需要遍历 16 个 1 GiB 巨页，每次 SBI ecall 输出累加，总时间远超 14 秒。v7 的 47 个进度 marker 证明映射持续前进，最终到达 11.75 GiB，正常完成 OSTD 初始化。

> 时间窗口不能判断"卡死"——只能用唯一 marker 判断"到达了哪个边界"。

## 7. 实际越过的边界

Megrez 真机迭代的完整进展，附带每轮的 commit 和日期：

| 轮次 | 日期 | commit | 最后边界 | 解释 |
|------|------|--------|---------|------|
| v3 | 07-12 | `838920840` | satp 后沉默 | Image header 前插导致根页表偏移 0x40 |
| v5 | 07-14 | `bbf65a40` | frame allocator 完成 | marker `7` 证明分配器初始化完毕 |
| v6 | 07-14 | `569698e3` | 线性映射"卡住" | 14 秒窗口太短，误判为死锁 |
| v7 | 07-14 | `6b075e73` | OSTD 初始化完成 | 47 个进度 marker 证明 11.75 GiB 连续映射进展；WDT0 未复位 |
| v8 | 07-14 | `b60ad6cf` | 组件完成，停在 `kernel::init()` | `rng-seed` 缺失导致 `util::random::init()` 无条件 unwrap |
| `ae38e6c6` | 07-15 | `ae38e6c6` | `Starting kernel ...` 之后静默 | Image 包装已修复，但上游 Sv48-first 丢失了 v8 的 Sv39 Megrez 能力 |
| `6df0f28f` | 07-16 | `6df0f28f` | `rootfs is ready`, init ENOENT | 默认 Sv48 真机成功到 rootfs，但 U-Boot stale RAM bootargs 覆写了 DTB |
| `3ef99e6bd` | 07-19 | `3ef99e6bd` | PID 1 进入用户态，`write` 返回 50 | 首次内核→用户态闭环；受控会话随后观察到新固件周期恢复 |

v8 能到 OSTD，不代表 `ae38e6c6` 也能到。它们是不同分支的代码。`ae38e6c6` 修复了 Image 包装，却丢失了 v8 的 Sv39-first 启动路径——rebase 不是免费的。

`6df0f28f` 的真机串口日志具体长这样：

```text
Starting kernel ...
Enter riscv_boot
INFO: Booting 3 processors
OSTD initialized. Preparing components.
use randomness based on the timestamp, which is insecure
[kernel] rootfs is ready
Failed to run the init process: ... ENOENT
```

注意 `use randomness based on the timestamp, which is insecure`——Asterinas 此时已实现了三层随机源回退（Zkr → rng-seed → timestamp），时间戳 fallback 虽然是安全警告，但它不阻塞启动。真正的故障是最后一行：init ENOENT，因为 bootargs 被覆写了。

## 8. 所以，"编译成功"到底意味着什么

回到开头的问题。"编译成功"在 OS 移植的上下文中只覆盖了构建机的内部一致性。`cargo build` 和 `rustc` 不关心目标 CPU 是 EIC7700 还是 QEMU virt，不关心加载器是 `booti` 还是 ELF loader，不关心 DTB 里 UART 的 compatible 是 `ns16550a` 还是 `snps,dw-apb-uart`。

每一次"编译成功"后面，至少还有六条契约需要逐个验证：链接布局正确、Image 格式合规、固件契约成立（加载地址不重叠、bootargs 一致）、satp 被硬件接受、页表 A/D 位满足硬件实际行为、DTB 内容与内核驱动假设匹配。

任何一条不成立，板子都可能沉默。编译器通过了，只代表世界一内部没有问题。世界一和世界二之间的契约、世界二和世界三之间的契约——这些才是沉默的真正来源。

---

_致谢与来源。_ 本文的工程实录和分析基于 Asterinas RISC-V 移植过程中积累的文档和证据，完整索引见 [`docs/porting/`](https://github.com/TankTechnology/asterinas-riscv/tree/riscv/console-bringup/docs/porting)。关键技术参考资料：RISC-V Privileged Specification（v20240411）、Linux RISC-V Boot Image Header 文档（`Documentation/arch/riscv/boot-image-header.rst`）、RISC-V SBI Specification v2.0、U-Boot `booti` 实现（`cmd/booti.c`）、《Devicetree Specification》、Milk-V Megrez 硬件文档。感谢 `codex` 在整个移植过程中的协作。

[下一篇]({% post_url 2026-07-22-asterinas-riscv-bringup-2-debugging-methodology %})讨论方法论问题：板子沉默时如何定位故障——从 Marker 链式排查法、实验循环设计、到过程中犯过的八个错误和六项正确的工程抉择。

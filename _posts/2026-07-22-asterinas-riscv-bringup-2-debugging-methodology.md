---
title: "当板子沉默时：OS Bringup 的调试方法与工程原则"
date: 2026-07-22
categories:
  - tech
  - os
tags:
  - asterinas
  - riscv
  - kernel
  - debugging
  - bringup
  - methodology
excerpt: "OS bringup 的早期阶段几乎没有任何可观测性——一行串口就是全部。这篇文章讨论在板子沉默时如何定位故障、如何设计受控实验、以及从 10+ 轮真机迭代中提炼出的工程原则和反面教训。"
---

[上一篇]({% post_url 2026-07-22-asterinas-riscv-bringup-1-from-source-to-boot %})结束在一个具体的结论上："编译成功"只覆盖了构建机的内部一致性。构建机和固件之间、固件和内核之间，还有六条契约需要逐个验证——任何一条不成立，板子都可能沉默。

这一篇讨论一个更紧迫的问题：**当板子确实沉默了，怎么找到是哪条契约出了问题？**

这不是 Rust 或 RISC-V 的技术问题。这是方法问题。在系统的内部状态完全不可见的情况下，如何设计实验、如何解读证据、如何避免误判——这些比具体的技术细节更难，也更容易被忽略。

## 1. 我们手里有什么

先明确一个事实：OS bringup 早期阶段的可用信息少得令人不安。

软件工程的常规前提——日志、堆栈、调试器、metrics——在这里都不存在。全部信息只有三样东西：一行串口（115200 baud，8N1，FTDI USB 转串口，唯一的通信渠道）、一份已知输入（加载到板上的 Image 字节、DTB 内容、bootargs 字符串）、以及一个预期输出序列（`Starting kernel ...` → `Enter riscv_boot` → `OSTD initialized` → …）。

但第一条"预期输出"就是第一个陷阱。`Starting kernel ...` 是 U-Boot 在跳转前打印的——它只证明 U-Boot 完成了加载和跳转准备。之后的一切都是推断。120 秒内没有新输出——这 120 秒里，CPU 可能已经取了指、执行了、触发了异常、甚至已经遍历了整个 16 GiB 的地址空间——没有任何方式知道。

这就是 OS bringup 的核心困境：

> 面对的是一个黑箱（板子），已知输入（Image + DTB + initramfs），单一输出通道（串口）。只能通过设计受控实验来推断内部状态。每次只改变一个变量，每次只验证一个可证伪假设。不是"改了这段代码试试"——是"假设故障在 X 边界，这一轮只验证 X，预期看到 marker M；看不到，X 被证伪。"

## 2. 调试工具箱

### 2.1 Marker 链式排查法

硬件调试有示波器、逻辑分析仪、JTAG。内核 bringup 只有串口。串口是一维的——只输出文本流，没有时间戳（除非显式编码），没有并行通道。

但串口有一个被低估的特征：输出是**不可逆且顺序的**。Marker A 出现在 Marker B 之前，意味着执行流确实经过了 A 然后才到达 B。如果 B 没出现，故障一定在 A 和 B 之间。

这个简单的观察就是 Marker 链式排查法的全部理论基础：

{% include asterinas-marker-timeline.html %}

Asterinas 的启动汇编和早期 Rust 代码在关键边界处通过 SBI ecall（`SBI_CONSOLE_PUTCHAR`）输出单字符 marker。[上一篇]({% post_url 2026-07-22-asterinas-riscv-bringup-1-from-source-to-boot %})已经详细解释过为什么 marker 必须放在不可逆操作**之后**（先写 satp、再输出 marker——而不是反过来），以及为什么 `csrw satp` 之后是一段沉默悬崖（页表出错 = ecall 指令都取不到）。

v5–v8 的真机迭代就是逐步增加 marker 的过程。每一轮新增的 marker 把"板子黑屏"从单一的不可知状态拆成更细的可定位边界。这不是调试技巧——这是在**建造可观测性本身**。

v5 的真机串口跟踪的前缀是 `AEFGDJBWXVCRS[01234567`——每个字符对应一个已越过的启动边界。v6 增加到了 `jkl`（页表构造阶段），最后停在 `l`（线性映射第一个巨页标记后）。v7 的 47 个线性映射进度 marker（`:` 字符序列）连续推进 11.75 GiB，把 v6 的"卡死"结论彻底推翻。

### 2.2 实验循环：每一轮只证伪一个假设

有了 marker 之后，还需要一个实验框架来决定什么值得测试、以及怎么判断结果。

{% include asterinas-experiment-loop.html %}

这个循环的核心约束是**单变量**：每一轮只改变一个东西，只验证一个可证伪假设。同时改页表、改 bootargs、换 initramfs——如果成功了，不知道哪项改动起作用；失败了，不知道哪项导致。这种测试不产生可用的知识。

下面用三个真实案例说明这个循环在实践中是怎么运转的。

**v3：字节级别的归因。** v3 的串口在 satp 写入后完全空白。可能的原因有五种：Sv48 不被 EIC7700 支持、页表错位、A/D 位缺失、高半地址计算错误、SBI 控制台不可用。我们首先排查了页表错位——不是靠"猜测"，而是靠字节级别的计算：header 前插恰好偏移 64 字节（0x40），`satp` 按 4 KiB 对齐读 `0x1000`，但根页表在 `0x1040`。修复是单变量的：只改 Image 布局（让 header 成为链接的一部分），不碰页表内容、启动参数或内核代码。v3 之后 satp 写入不再静默。

**v6→v7：慢不等于死。** v6 的最后 marker 是 `l`，14 秒窗口内无新输出。当时判断为"线性映射卡死"。v7 用更长的观察窗口和更密集的进度 marker（47 个 `:`）证伪了这个结论：16 GiB identity map 需要遍历 16 个 1 GiB 巨页，每次 SBI ecall 累积后总时间远超 14 秒。v7 的日志显示映射持续前进，11.75 GiB 后正常完成 OSTD 初始化。**时间窗口不能判断"卡死"——"死"只能用 marker 缺失证明；"慢"是独立于"死"的可能解释。**

**A/D 位：QEMU 降级测试。** A/D 位 bug 在普通 QEMU 配置下完全不可见。我们主动降级 QEMU——`-cpu rv64,svade=true` 强制模拟"硬件不自动更新 A/D 位"——内核 panic 了。panic 在页表 walker：启动页表的巨页 PTE 缺少 A/D 位。修复是 `PTE_VRWXAD = PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D`。单变量验证通过后，`b364dafab`（"Initialize RISC-V boot mapping A/D bits"，2026-07-16）被合入。这是 QEMU 作为可配置实验平台的典型用法——不是跑一遍就完了，而是利用它的配置能力来遍历硬件假设矩阵。

## 3. QEMU 调试实战：工具、配置、边界

在进入具体的工程原则之前，有必要先把 QEMU 调试中积累的具体技术细节整理出来。这些不是"最佳实践"——是我们在 Megrez bringup 中反复使用、验证过的具体配置和命令。

### 3.1 CPU 扩展矩阵：用 `-cpu` 遍历硬件假设

QEMU 的 RISC-V CPU 模拟可以**逐条开关** ISA 扩展。这是 QEMU 作为 bringup 工具最被低估的能力——在真机上，你不可能"把 EIC7700 的 Svade 关掉"。在 QEMU 里，这只是一个命令行参数。

我们的策略是把 CPU 扩展组合固化为**不可变 profile**（[`tools/riscv/qemu_uboot_profiles.py`](https://github.com/TankTechnology/asterinas-riscv/blob/riscv/console-bringup/tools/riscv/qemu_uboot_profiles.py)），每个 profile 精确描述一个硬件假设场景：

```python
MEGREZ_SV48_SVADE_FAST = QemuUbootProfile(
    cpu="rv64,sv57=false,svpbmt=false,zkr=false,svadu=false,svade=true",
    memory="2G", hart_count=4,
    bootargs="cpu_no_boost_1_6ghz loglevel=info init=/init",
    remove_rng_seed=True,  # 去掉 /chosen/rng-seed，强制走 timestamp fallback
)

MEGREZ_SV48_SVADU_FAST = QemuUbootProfile(
    cpu="rv64,sv57=false,svpbmt=false,zkr=false,svadu=true,svade=false",
    # ... 同上，但 A/D 模式从 svade 换成 svadu
)
```

每个 profile 记录 cpu 字符串、内存大小、hart 数量、bootargs、是否移除 rng-seed。profile 一旦注册就不能被临时修改——每次 QEMU 启动都要经过 `require_profile_launch_allowed()` 验证，慢 profile（16 GiB）还额外需要资源门禁（检查 `MemAvailable` 是否充足）。

具体到 QEMU 命令行，`-cpu` 参数直接控制 CPU 扩展矩阵：

```text
qemu-system-riscv64 \
  -machine virt \
  -cpu rv64,sv57=false,svpbmt=false,zkr=false,svadu=false,svade=true \
  -m 2G -smp 4 \
  -display none -monitor none -serial stdio
```

关键选项说明：

- **`svade=true,svadu=false`**：强制硬件不自动更新 A/D 位（Svade 模式）。这是 A/D 位 bug 暴露的关键开关——默认 QEMU 会走 Svadu（自动更新），关了之后才看到 panic。
- **`zkr=false`**：关掉硬件随机数生成器。强制 Asterinas 走 rng-seed → timestamp 回退路径，验证每层回退都能正常工作，不会 unwrap。
- **`svpbmt=false`**：关掉 Page-Based Memory Types 扩展。EIC7700 不支持 Svpbmt，QEMU 里打开它会让内核在真机上碰不到的代码路径上运行——在 QEMU 里也关掉它，让模拟更接近真实硬件。
- **`-display none -monitor none`**：纯串口驱动。不启动图形界面，不启动 QEMU monitor（QMP）。测试只通过串口的 stdin/stdout 进行，模拟真机的单向通信环境。
- **`-serial stdio`**：把 guest 串口接到 QEMU 进程的 stdin/stdout。串口日志直接写入文件，SHA-256 身份冻结通过 Python 层的 `append_bounded_serial_chunk` 实现，内存中缓冲上限 4 MiB。

### 3.2 DTB 生成与操控：为什么不能直接用 QEMU 自动生成的 DTB

QEMU 的 `-machine virt` 会自动生成一个 DTB 给 guest。但直接用它有两个问题：一是 QEMU 自动生成的 DTB 中，UART 的 compatible 是 `ns16550a`——与 Megrez 真机的 `snps,dw-apb-uart` 不同；二是 `/chosen/rng-seed` 会被 QEMU 自动填入随机种子，导致 Asterinas 的 Zkr 回退路径在 QEMU 上从未被触发。

我们用 `-machine virt,dumpdtb=<path>` 让 QEMU 先生成 DTB 然后退出（不真正启动 guest），再通过 `fdtput`/`fdtget` 工具（来自 `dtc` 包）对 DTB 做受控修改：

```bash
# 生成 DTB
qemu-system-riscv64 -machine virt,dumpdtb=qemu-virt.dtb \
  -cpu rv64,svade=true -m 2G -smp 4

# 移除 rng-seed（如果存在）
fdtput -d qemu-virt.dtb /chosen rng-seed

# 验证修改后的 DTB 符合 profile 预期
python3 tools/riscv/qemu_uboot_dtb.py audit-existing \
  --profile megrez-sv48-svade-fast --dtb qemu-virt.dtb
```

关键的 DTB 操控工具链：`fdtget`（读取节点和属性）、`fdtput`（修改属性值）、`dtc`（DTB ↔ DTS 互转，用于手工检查生成结果）。所有 DTB 修改操作都有对应的 Python 审计层（`qemu_uboot_dtb.py`），确保修改后的 DTB 与 profile 描述一致——内存大小、CPU 数量、MMU 类型、A/D 扩展、rng-seed 有无，全部可验证。

Console-loss 变体测试是 DTB 操控的典型应用。正常 preflight 的 payload DTB 中 UART 是 `ns16550a`；console-loss variant 将其改为 `snps,dw-apb-uart`（只改这一个字符串，其他属性不变），然后在 QEMU 中验证 Asterinas 确实无法注册 UART console、用户态 write 虽然成功但无文本输出。这个单字符串变更就模拟了 Megrez 真机上的 console 丢失现象——尽管 QEMU 的 machine 层仍然模拟的是 NS16550A 硬件，但从 Asterinas 的视角看，它收到的 DTB 描述了一个它不认识的 UART。

### 3.3 U-Boot 作为 guest kernel：完整的启动链在 QEMU 里跑

QEMU 支持 `-bios`（加载 OpenSBI）和 `-kernel`（加载 U-Boot）的组合，让我们能在 QEMU 中完整模拟真机的三层固件链。具体做法：

```text
qemu-system-riscv64 \
  -bios fw_jump.bin \                     # OpenSBI
  -kernel u-boot \                         # U-Boot 作为 S-mode payload
  -drive if=none,format=raw,file=boot.ext4,id=bootdisk,snapshot=on \
  -device virtio-blk-device,drive=bootdisk
```

`boot.ext4` 是一个预制的 ext4 文件系统镜像，包含了 `/asterinas.booti`（Image）、`/qemu-virt.dtb`（DTB）、`/initramfs.cpio.gz`（initramfs）。U-Boot 启动后，由 `boot_commands()` 生成的命令序列通过串口逐条发送给 U-Boot：`ext4load` 加载三样东西到 DRAM、`crc32` 校验、`fdt` 修补 `/chosen`、`booti` 跳转。整个流程与真机在 U-Boot 阶段的行为完全一致。

**`snapshot=on`** 是一个关键细节。它让 QEMU 把启动盘标记为快照模式——所有写操作只存在于内存中，不落盘。这意味着每次 QEMU 启动都从一个已知的、验证过的启动盘状态开始，不会因为上一次测试残留的状态影响下一次。软件恢复测试（timer 触发 `sbi_system_reset` → 新固件周期启动）要求启动盘在复位前后 SHA-256 保持一致，`snapshot=on` 保证了这一点。

### 3.4 串口会话的严格边界

QEMU 串口会话（[`qemu_uboot_session.py`](https://github.com/TankTechnology/asterinas-riscv/blob/riscv/console-bringup/tools/riscv/qemu_uboot_session.py)）有以下严格约束：

- **单次 booti**：整个会话只允许发送一次 `booti` 命令。如果 marker 没出现，不在同一会话中重复尝试。
- **被动采集**：内核启动后（`Starting kernel ...` 之后），不再向串口发送任何字符。只读——等待预期 marker 或超时。
- **进程组清理**：QEMU 以进程组方式启动（通过 `os.setsid()`），终止时先 SIGTERM 整组进程，超时后 SIGKILL。还通过 Linux 的 `prctl(PR_SET_CHILD_SUBREAPER)` 确保孤儿 QEMU 子进程也能被回收。
- **4 MiB 串口上限**：串口日志在内存中缓冲不超过 4 MiB。超过就抛异常——防止无限串口输出（比如内核陷入重启循环）撑爆硬盘。
- **预期 marker 精确匹配**：不是"扫描日志找字符串"——是字节级别的顺序流匹配。预期 marker 必须按顺序出现。正向前缀场景（如 `uboot-positive`）要求精确的 userspace hello marker；负向场景（如 `uboot-stale-bootargs`）则要求精确的 `EXPECTED_INIT_ENOENT`。

### 3.5 进程清理：QEMU 不是 `kill` 就够的

QEMU 以 `-no-reboot` 模式启动时，guest 执行 `sbi_system_reset` 后 QEMU 会正常退出。但在 bringup 中更常见的是 guest 静默卡死——QEMU 进程本身不退出，占用着 PTY 和文件描述符。我们需要确保每次测试结束后 QEMU 进程树被完全清理。

清理流程（[`qemu_process_cleanup.py`](https://github.com/TankTechnology/asterinas-riscv/blob/riscv/console-bringup/tools/riscv/qemu_process_cleanup.py)）：

1. SIGTERM → 等待 grace period（允许 QEMU 做最后的清理）
2. 未退出 → SIGKILL 整组进程
3. 通过 `os.waitpid(-pgid, WNOHANG)` 循环回收所有僵尸子进程
4. 验证进程组已完全消失（`os.killpg(pgid, 0)` 抛 `ProcessLookupError`）

### 3.6 GDB 调试：从第一条指令开始

当 marker 链无法缩小故障范围——比如在 satp 写入后静默、但无法区分是页表错误还是 satp 模式不被接受——GDB 是最直接的排查手段。

Megrez preflight 支持通过 `--gdb-socket` 选项启动 QEMU 时附加 GDB：

```text
qemu-system-riscv64 \
  ... \
  -S -gdb unix:/tmp/asterinas-gdb.sock,server=on,wait=off
```

`-S` 让 CPU 在第一条指令处冻结，等待 GDB 客户端通过 Unix socket 连接。连接后，可以逐指令单步执行启动汇编、检查 `satp` 写入前后的 CSR 值、dump 页表内容（`x/64gx sv48_boot_l4pt`）、在 `bsp_flush_tlb` 和 `bsp_boot_virt` 处设置断点。GDB 的 `info registers` 能直接看到 hart ID（`a0`）和 DTB 指针（`a1`）是否与 U-Boot 传递的一致。

Asterinas 的 OSDK 还提供了 `cargo osdk run --gdb-server` 命令，自动生成 `.vscode/launch.json`，在 VS Code 中直接源码级调试内核。x86-64 上还支持 `--coverage` 模式——`--no-shutdown` 让 QEMU 在 guest 退出后仍然存活，通过 monitor socket 发送 `memsave` 提取覆盖率数据。

### 3.7 两条 QEMU 路径：直接启动 vs 经 U-Boot

我们在开发中使用了两种 QEMU 启动路径，各自承担不同的角色：

**直接启动（`-kernel asterinas.elf`）**：QEMU 内嵌的 OpenSBI 直接把 ELF 作为 S-mode payload 启动。没有 U-Boot，没有 DTB 修补，没有 `booti` 校验。这种路径反馈极快——修改代码后几秒就能看到结果。但它是**不可靠的**——它绕过了 U-Boot 的 Image header 校验、bootargs 覆写行为、以及 DTB 加载机制。直接启动成功的 Image 在真机 U-Boot 路径上可能因为 header 不匹配直接失败。

**经 U-Boot 启动（`-kernel u-boot`）**：U-Boot 从 virtio 块设备加载 Image + DTB + initramfs，通过 `booti` 跳转。这是真机路径的完整模拟，也是 preflight 门禁的标准路径。代价是慢——一次 `uboot-positive` 测试约需 6–7 秒，而直接启动只需约 4 秒。

在 bringup 过程中，两个路径交替使用：直接启动用于快速开发迭代（改几行汇编、验证 marker 是否出现），U-Boot 路径用于门禁（验证 Image 格式、bootargs 一致性、UART 驱动匹配）。一个典型的分工是：直接启动覆盖 Svade/Svadu 矩阵，U-Boot 路径覆盖 bootargs 和 console-loss 场景。

QEMU 还可能通过 `-serial pty` 遗留未关闭的 PTY 从设备，清理脚本会检查并释放它们。

## 4. 六条原则和六个反面教训

Megrez bringup 从 7 月 12 日到 7 月 20 日，80+ 条用户消息，10+ 轮真机迭代。在这个过程中，一些做法反复被证明有效，另一些错误则反复出现——而且有趣的是，每个错误几乎都对应着某条原则的违反。下面把它们按"原则—反面教训"配对。

### 4.1 冻结身份 vs 不知道跑了什么

**原则：每次真机实验前，冻结产物身份的完整证据链。** 包括 Git commit hash（完整 40 字符）、ELF SHA-256、Image SHA-256 和 CRC32、initramfs SHA-256 和 CRC32、Image 字节数、DTB 文件路径和 `fdt print /model` 输出、所有 U-Boot 加载地址、原始串口日志路径和 SHA-256。

**反面：`ae38e6c6` 之所以有价值而不是垃圾，正是因为完整的身份冻结。** 这次实验只到达 `Starting kernel ...` 就沉默了——但 Image SHA-256（`429519fbb18037c5201652648cd2fb7e83aa97f6c82e86126a2faf477c258e24`）、CRC32（`542e838a`）、DTB model（`Milk-V Megrez`）、bootargs、U-Boot 加载地址全部归档。这个失败不是"大概有问题"——它是一个已经通过了传输和 U-Boot 门禁、在跳转后第一微秒停下来的 Image。三个星期后任何人拿到这份证据，都能精确复现当时的实验条件。

如果身份不冻结，实验结论不可复现、不可追溯、不可交接。三周后自己都记不住用的是哪个 commit。

### 4.2 单变量 vs 多变量混杂

**原则：每一轮实验的改动范围严格约束到一个可证伪假设。** 页表 mode、随机源策略、console 路由——在独立轮次中分别处理。

**反面：`6df0f28f` 的 init ENOENT 失败是一例，但它是"好的失败"——因为归因清晰。** `6df0f28f`（2026-07-16）的真机串口日志精确显示了问题边界：

```text
Enter riscv_boot
INFO: Booting 3 processors
OSTD initialized. Preparing components.
use randomness based on the timestamp, which is insecure
[kernel] rootfs is ready
Failed to run the init process: ... ENOENT
```

注意 `use randomness based on the timestamp, which is insecure`——此时 Asterinas 已实现了 Zkr → rng-seed → timestamp 三层回退。时间戳 fallback 是安全警告，但不阻塞启动。真正的故障是最后一行。

根因被单变量追溯到 U-Boot 的 `booti` 行为：`cmd/booti.c` 中的实现会用 RAM 环境变量 `bootargs` 覆写 DTB 的 `/chosen/bootargs`。DTB 里写了 `init=/init`，但 U-Boot RAM 环境残留了不带此参数的旧值。修正也是单变量的：同时 `setenv bootargs` 和 `fdt set /chosen bootargs` 为同一值 `cpu_no_boost_1_6ghz loglevel=info init=/init`，`booti` 前分别 `printenv` 和 `fdt print /chosen` 对比，永不 `saveenv`。修复的 commit 是 `a2b9c0b6e`（"Fix U-Boot bootargs handoff"，2026-07-16）。

### 4.3 QEMU 作为可配置过滤器 vs QEMU 作为一次性跑通

**原则：QEMU 的价值不在于"在虚拟机上跑一次"，而在于它可以精确控制硬件特性——打开或关闭某个 CPU 扩展、改变内存大小、替换 DTB——每一种配置都是对软件假设的独立检验。**

Megrez preflight 被设计为六个 stage 和一个独立 probe（commit `593d5bb19`，2026-07-17）：

1. `direct-svade`：关 Zkr（RISC-V 硬件随机数生成器扩展）、去 seed（DTB 中的 `/chosen/rng-seed`），4-hart Sv48/Svade → 用户态 marker
2. `direct-svadu`：同上，Svadu
3. `uboot-stale-bootargs`：真实 U-Boot `booti`，RAM bootargs 不带 `init=/init` → 预期 `EXPECTED_INIT_ENOENT`
4. `uboot-positive`：修正 bootargs 后 → 用户态 marker
5. `uboot-first-process-console-loss`：payload DTB UART compatible 改为 `snps,dw-apb-uart` → 预期 `EXPECTED_CONSOLE_ROUTE_LOSS`
6. 独立 probe：`uboot-registered-console-suppression`

六个场景，四种硬件假设矩阵。任一失败，阻止真机测试。

**反面：QEMU 默认配置通过后，没有任何降级测试，直接上板。** `ae38e6c6` 就是这个反面的体现——QEMU 六 stages 全通，但真机在跳转后即停止。QEMU virt 机器不通往 EIC7700 的真机行为。但注意：这不是 QEMU 的错——是我们当时还没有建立降级测试的覆盖范围。A/D 位的 Svade 测试、stale bootargs 的负向回归、console-loss 的 DTB 变体——这些都是后来才加入 preflight 矩阵的。preflight 矩阵本身就是一个随时间增长的东西：每次真机暴露一个新问题，对应的 QEMU 降级 scenario 就被加入矩阵，防止同类问题再次以"QEMU 通过"的面貌溜到真机上。

**QEMU 失败至少能避免一次真机尝试；QEMU 通过只说明软件链路可能正确，不能代替真机验证。**

### 4.4 不覆盖旧产物 vs 唯一可用的恢复入口被破坏

**原则：每次使用带 commit 或 run ID 的新文件名。** 先下载到 `/tmp`，哈希校验通过后才安装到 `/boot`。RockOS 的 extlinux 配置和历史镜像全部保留。Megrez 每次写入 `/boot` 的文件名格式为 `asterinas-megrez-<commit>-<run-id>.booti` 和 `rv-init-megrez-<commit>-<run-id>.cpio.gz`。

**反面：如果新 Image 导致板子完全无法启动，而 RockOS 又被覆盖了——板子变砖，只能通过 SD 卡重新烧录恢复。** `ae38e6c6` 虽然失败了，但板子可以通过 `sysboot mmc 1:1 any 0x88200000 /extlinux/extlinux.conf` 重新进入 RockOS。保留已知可用的恢复入口是硬件实验的第一条安全规则。

### 4.5 链接器断言 + 自动化测试 vs "看起来正确"

**原则：不依赖肉眼检查。** `make_booti.py` 的合成 ELF 和真实 ELF 测试覆盖了 header 字段、根页表偏移、缺失符号和错位检测。链接器在 `bsp_boot.S` 中有编译期断言（`.if (bsp_boot_body - _start) != 0x40 .error ...`）。Image 工具说明见 [`tools/riscv/README.md`](https://github.com/TankTechnology/asterinas-riscv/blob/riscv/console-bringup/tools/riscv/README.md)。

**反面：v3 之前，没有自动化测试验证"header 偏移是否正确"。** 如果有任何一个测试检查了 `sv48_boot_l4pt` 在文件偏移 `0x1000`，64 字节前插错误在第一轮构建中就会被挡下——根本不会到真机。

### 4.6 安全边界 vs 在失控状态下继续操作

**原则：真机测试不写固件、不格式化存储、不 `saveenv`、不写共享 clock/reset 寄存器、Asterinas 静默后不发送试探字符、观察窗口结束后释放串口并请求外部复位。**

**反面（硬件层）：WDT0 的虚假希望。** v7（commit `6b075e73b29c`，2026-07-14）在 U-Boot 中确认了 WDT0 身份正确、counter 递减、enable 已设置。然后在超过 705 秒的观察窗口内，串口上未出现任何复位 banner、U-Boot 倒计时或提示符。WDT0 在 U-Boot 的 M-mode 环境中看起来正常，但进入 S-mode 后——没有人知道它是否被重新配置了、复位输出是否正确连接到了系统复位线、或者 watchdog 的时钟源在进入内核后是否仍在运行。**硬件 watchdog 只能作为诊断对象，不能作为执行 `booti` 的独立恢复门禁。外部物理复位是唯一可靠的选择。**

**反面（软件层）：U-Boot 串口放送缺少流控。** `sysboot mmc 1:1 any 0x88200000 /extlinux/extlinux.conf` 曾被截断成 `sysboot mmc 1:1 any 0x88200000 /e`——FTDI FT232R 在突发长命令时没有流控，U-Boot 输入缓冲溢出。从那时起，所有 U-Boot 命令逐字符节流发送，等待完整回显后再提交。

**反面（自动化层）：CRC 输出和 U-Boot prompt 混淆、命令回显被误认为命令输出。** CRC 计算输出 `==> 542e838a` 时，状态机曾把 `=> ` 当作 U-Boot prompt——修正方法是将 prompt 匹配条件改为精确的新行开头 `\r\n=> `。Linux shell 串口回显可能让状态机在命令真正执行前就匹配到预期 marker——修正方法是动态构造 marker 文本，确保完整 marker 只出现在命令输出中而非输入文本中。

## 5. 协作：状态汇报模板

OS bringup 的协作有一个独特的难点：用户看到板子沉默、串口空白、代理在发各种命令——但没有框架来理解进度。为了把这个过程从"黑箱"变得透明，我们收敛到了一个六项汇报模板。每次新实验前，依次给出六项；用户在 30 秒内就能判断方向对不对。

| 项目 | 回答的问题 | 示例 |
|------|-----------|------|
| **目标** | 这一轮只想证明什么？ | 验证 Sv48 页表在真机上被硬件接受 |
| **已过边界** | 最后一条可靠证据是什么？ | 上一轮 `ae38e6c6`：`Starting kernel ...`，之后无输出 |
| **当前假设** | 只保留哪个可证伪假设？ | 分页 mode 写了 Sv48 但 EIC7700 不接受，读回不一致 |
| **下一实验** | 只改变什么变量？ | 在 `csrw satp` 后加 SBI ecall marker，读回并打印实际 satp 值 |
| **用户动作** | 需要用户做什么？ | 需要外部复位能力，不需要其他操作 |
| **停止条件** | 什么情况下不继续？ | 外部复位不可达 |

这六项直接遏制了五个常见问题：用户不知道代理在做什么、一个简单目标被隐式扩展（"只是加个定时复位"→ QMP 控制器 + WDT + 多套恢复路径）、恢复机制和启动主线相互遮蔽、因为没有时间预期而反复追问进展、失败后继续无边界尝试。

## 6. 从混沌到可观测

Megrez bringup 从 7 月 12 日到 7 月 20 日。回头看，这条路可以压缩为一个核心洞察：

> **OS bringup 不是"修 bug 直到跑起来"的过程，而是"逐步建立可观测性"的过程。**

v3 的 Image 布局修复之后，satp 之后的 marker 第一次出现在串口上。v5–v8 的 marker 链逐步覆盖了 OSTD 和组件初始化的全部边界。`a2b9c0b6e` 的 bootargs 修正之后，`rootfs ready` 成为可靠可见的里程碑。`3ef99e6bd` 的第一进程诊断（`asterinas.first_process_diag=1`）使得在没有任何用户态文本输出的情况下，仍然能确认 PID 1 执行了 `write` 并返回了 50。

每一步不是在靠近"成功"——是在扩大可观测的范围。可观测性不是 bringup 的前提条件。它是在 bringup 过程中，一个 marker 一个 marker 地建造出来的。

---

_致谢与来源。_ 本文的工程实录和分析基于 Asterinas RISC-V 移植过程中积累的文档和证据。所有错误分析、工程原则和实验记录见 [`docs/porting/megrez-asterinas-boot-guide.md`](https://github.com/TankTechnology/asterinas-riscv/blob/riscv/console-bringup/docs/porting/megrez-asterinas-boot-guide.md)、[证据索引](https://github.com/TankTechnology/asterinas-riscv/blob/riscv/console-bringup/docs/porting/evidence/megrez-history-index.md)和各轮次 evidence page。感谢 `codex` 在整个过程中的协作。

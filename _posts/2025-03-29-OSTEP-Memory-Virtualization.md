---
title: "OSTEP Memory Virtualization Notes"
date: 2025-03-29
categories:
  - blog
tags:
  - Operating System
  - Memory
  - Virtualization
---

<style>
.lang-switch {
  text-align: right;
  margin-bottom: 1.5em;
  font-size: 0.95em;
  user-select: none;
}
.lang-switch a {
  color: #888;
  text-decoration: none;
  padding: 0 0.3em;
}
.lang-switch a.active {
  color: #333;
  font-weight: 600;
}
.lang-switch a:not(.active):hover {
  text-decoration: underline;
}
</style>

<div class="lang-switch">
  <a class="active" href="#en" onclick="switchLang('en');return false">English</a>|
  <a href="#zh" onclick="switchLang('zh');return false">中文</a>
</div>

<div id="lang-en" class="lang-content" markdown="1">

# OSTEP Memory Virtualization Notes

This is my notes for the book *Operating Systems: Three Easy Pieces* — Memory Virtualization.

I spent a week reading through the Memory Virtualization section and gained a lot from it.

## Ch12 A Dialogue on Memory Virtualization

It's quite fun to see a teacher-student dialogue in a textbook. The chapter introduces memory virtualization through an exchange between professor and student, which kind of reminds me of the *Analects of Confucius*.

## Ch13 The Abstraction: Address Spaces

Programmers want things to be as simple as possible. When we write C and call `malloc()`, we get a chunk of memory and start using it directly — no need to worry about how that memory came to be, how it's stored, or how it's reclaimed. The OS abstracts away the real physical memory and gives us a convenient, easy-to-use virtual address space.

## Ch14 Interlude: Memory API

This chapter discusses the basic implementation of `malloc()` and `free()`.

`malloc()` takes one argument — the amount of memory to allocate — and returns a pointer to the allocated memory.
`free()` takes a pointer and releases the memory.

I used to wonder why `free()` only needs a pointer but not a size. The reason is that `malloc()` records the size of the allocation right next to the memory block it returns, so `free()` can figure out how much to release just from the pointer.

## Ch15 Mechanism: Address Translation

To effectively virtualize memory, the OS must translate `virtual addresses` into `physical addresses`. This process is called `address translation`.

This chapter explains `dynamic relocation`, which uses two registers:

- `base register`: stores the base address of the virtual address space
- `bounds register`: stores the limit of the virtual address space

Under this scheme, the physical address equals `virtual address + base register`.

The hardware's `Memory Management Unit (MMU)` handles the translation from virtual to physical addresses. The OS is responsible for allocating space to each process (setting `base` and `bounds` registers) and raising exceptions when a process uses an illegal address.

Dynamic relocation has a limitation: within a given memory space, it uses memory very sparsely, which leads to `Internal Fragmentation`.

## Ch16 Segmentation

To mitigate `Internal Fragmentation`, the OS introduced `Segmentation`.

Segmentation divides a program into `Code`, `Heap`, and `Stack` segments. The high-order bits of each virtual address indicate the segment number, while the low-order bits indicate the offset within the segment.

There are still problems here:

- Because segments are variable in size, memory gets divided into uneven blocks, leading to `External Fragmentation`.
- Segmentation still isn't flexible enough. If you have a large but sparse `Heap`, it takes up a lot of memory space that is effectively wasted.

## Ch17 Free-Space Management

This chapter discusses how to manage free memory space.

We use a linked list to track free memory blocks, where each node represents a free block and stores its size plus a pointer to the next free block.

When allocating memory, we find a "suitable" block from the list, split it, and update the list.
When freeing memory, we add the block back to the list and consider coalescing it with adjacent free blocks.

There are several strategies for finding a "suitable" block: `First-Fit`, `Best-Fit`, `Worst-Fit`. In practice, a widely-used strategy is the `Buddy Algorithm`.

The Buddy Algorithm's core idea is to view memory as blocks of power-of-two sizes. When a request comes in, find the smallest power-of-two block that's large enough. If there's no exact match, split a larger block into two equal-sized buddies and allocate one. When freeing, if two adjacent buddy blocks are both free, merge them back into a larger block.

(Honestly, this feels a lot like the segment tree data structure commonly used in competitive programming.)

## Ch18 Paging: Introduction

To address most memory management problems, there are generally two approaches. One is to split things into variable-sized chunks, as with `Segmentation`. The other is to split things into fixed-size chunks — this is `Paging`.

A virtual address under Paging is divided into two parts:

- `Virtual Page Number (VPN)`: indicates the page number
- `Offset`: the offset within the page; the number of offset bits equals the page size's bit width (e.g., 12 bits for a 4KB page)

The VPN-to-PTE (Page Table Entry) translation process:

```c
VPN = (VirtualAddress & VPN_MASK) >> PAGE_SHIFT
PTEAddr = PageTableBaseRegister + (VPN * sizeof(PTE))
```

`PageTableBaseRegister` (PTBR) is the page table base register.

The physical address is computed as:

```c
offset = VirtualAddress & OFFSET_MASK
PhysAddr = (PFN << PAGE_SHIFT) | offset
```

But this design has many performance issues.

## Ch19 Paging: Faster Translation (TLBs)

> "When we want to make things fast, the OS usually needs some help. And help often comes from the OS's old friend: the hardware."

To accelerate virtual-to-physical address translation, hardware introduced the `Translation Lookaside Buffer (TLB)`, which is part of the chip's Memory Management Unit (MMU). You can think of the TLB as an `address-translation cache`.

TLB Control Flow Algorithm:

```c
VPN = (VirtualAddress * VPN_MASK) >> PAGE_SHIFT
(Success, TlbEntry) = TLB_Lookup(VPN)
if (Success == True)
    if (CanAccess(TlbEntry.ProtectBits) == True)
        Offset = VirtualAddress & OFFSET_MASK
        PhyAddr = (TlbEntry.PFN << PAGE_SHIFT) | Offset
        Register = AccessMemory(PhyAddr)
    else
        RaiseException(PROTECTION_FAULT)
else
    PTEAddr = PTBR + (VPN * sizeof(PTE))
    PTE = AccessMemory(PTEAddr)
    if (PTE.Valid == False)
        RaiseException(SEGMENTATION_FAULT)
    else if (CanAccess(PTE.ProtectBits) == False)
        RaiseException(PROTECTION_FAULT)
    else
        TLB_Insert(VPN, PTE.PFN, PTE.ProtectBits)
        RetryInstruction()
```

TLBs are great, but who handles a TLB miss?

There are two approaches:

- Hardware
- Software (the OS)

Historically, CISC architectures typically had hardware handle it. Modern architectures like RISC usually let software handle it. When a TLB miss occurs, the hardware raises an exception, switches to kernel mode, jumps to the `trap handler`, and the trap handler resolves the miss.

A `TLB_Entry` looks like:

```c
VPN | PFN | other bits
```

The `other bits` typically include a `valid` bit (is this translation entry valid?) and `protection bits` (permissions — e.g., `read and execute` for a code page, `read and write` for a heap page).

When a context switch occurs, the TLB needs to be updated. There are several ways to handle this:

- Simplest: flush all TLB entries
- Add hardware support to identify TLB entries by process ID — this is called `Address Space Identifier (ASID)`.

## Ch20 Paging: Smaller Tables

Consider a 32-bit address space with 4KB pages and 4-byte page table entries.

Since pages are 4KB, the offset is 12 bits. With a 32-bit address space, we can store 2^20 page table entries. Each entry is 4 bytes, so the page table size is 2^20 × 4B = 4MB. Since every process needs its own page table, a system with 1000 processes would need 1000 × 4MB = 4GB just for page tables. That's **enormous** memory overhead.

Solution 1: Larger pages.

- Pros: fewer page table entries, smaller page tables.
- Cons: internal fragmentation gets worse.

Solution 2: Multi-level page tables.
Organizing page tables in a tree structure reduces the table size.

For a two-level page table, we have a `Page Directory` that stores indices to page tables.
A virtual address takes the form `PDE | PTE | offset`: `PDE` for Page Directory Entry, `PTE` for Page Table Entry, and `offset` for the in-page offset.

First, use the Page Directory to find the relevant page table; then use the Page Table to find the physical page. This is essentially a **tree structure**, and it's easy to generalize to multi-level page tables. This tree structure significantly reduces the memory cost of storing page tables.

- Pros: dramatically reduces page table memory overhead.
- Cons: increases the number of memory accesses (e.g., a two-level table needs two memory accesses, though TLB can mitigate this).

## Ch21 Beyond Physical Memory: Mechanisms

The problem this chapter addresses: how can the OS use a large but slow device to transparently provide the illusion of an even larger virtual address space? The large but slow device here is the disk (if disks were faster than memory, why wouldn't we just use disks as memory?).

Because physical address space is limited, when the OS runs large programs, physical memory may run out. We need to move some pages to `Swap Space`. Swap space is a large disk region used to store pages that have been swapped out.

In each page table entry, we store a `Present Bit`, indicating whether the page is currently in physical memory. When a process accesses a page whose `Present Bit` is 0, a `page fault` is triggered. The OS's `page fault handler` then loads the relevant data from swap space into physical memory.

## Ch22 Beyond Physical Memory: Policies

This chapter focuses on cache management strategies.

The book presents the optimal policy, proposed by Belady: always evict the page that will be accessed furthest in the future. But this strategy is impractical in reality because we can't actually know which page will be accessed furthest in the future.

A simple strategy is `FIFO (First-In, First-Out)`. FIFO's biggest advantage is its extremely simple implementation, but the downside is that such a naive policy can be tripped up by corner cases.

`Random Replacement` avoids corner-case issues but sometimes performs poorly.

A widely-used strategy is `Least Recently Used (LRU)`: evict the page that hasn't been accessed for the longest time. However, implementing this precisely is complex — traversing all pages to check their access times would be prohibitively expensive. We use an approximate strategy instead.

Here the OS needs help from its old friend the hardware again. We introduce the `use bit` (also called `reference bit`), which indicates whether a page has been accessed recently. If accessed, it's set to 1; when to reset it to 0 depends on the OS policy. A simple and practical strategy using this is the `Clock Algorithm`.

Specifically, pages are organized in a circular linked list, each with a `use bit`. A pointer traverses the list. When we need to evict a page, we check the `use bit` of the page the pointer currently points to. If it's 1, we set it to 0 and move the pointer to the next page. If it's 0, we evict the current page. This gives us an approximate LRU.

## Ch23 Complete Virtual Memory Systems

This chapter discusses how virtual memory is implemented in real operating systems. (Though it felt a bit too advanced for me — a lot of it went over my head.)

The book mainly covers two systems: `VAX/VMS` and `Linux`.

### VAX/VMS

The VAX-11 uses a 32-bit virtual address space with 512-byte pages, combining `segmentation` and `paging`.

Memory layout: divided into P0 (user program and heap), P1 (stack), and S (system).

Page replacement policy:

- No hardware reference bit.
- Uses FIFO replacement.
- Uses clustering to improve disk I/O efficiency.

Loading optimizations:

- Demand Zeroing
- Copy-On-Write

Both are common lazy allocation strategies.

### Linux

Memory layout: typical 32-bit Linux divides the address space into user space and kernel space (above 0xC0000000). Kernel addresses are directly mapped to physical addresses.

Page tables: four-level page tables. Linux defaults to 4KB pages, but supports huge pages for applications like databases — this requires user configuration.

Other advanced designs and security discussions were genuinely beyond me.

## Ch24 Summary Dialogue on Memory Virtualization

Through another teacher-student dialogue, the chapter summarizes the entire Memory Virtualization section.

Here's my own understanding of the whole process:

The OS wants to make memory easier for programmers to use, so it abstracts physical memory into a virtual address space.

Virtual addresses must be mapped to physical addresses — this mapping process is called address translation.

The two fundamental ways to manage virtual addresses are: segmentation and paging.

Segmentation: divide a program into multiple segments, each with different permissions and sizes.

Paging: divide memory into pages, all of equal size.

Since page tables incur significant memory overhead, multi-level page tables are used to reduce this cost.

Since accessing page tables requires multiple memory accesses, the TLB is used to accelerate address translation.

But caches always face misses, so replacement policies are needed. These include: FIFO, Random, LRU (practically implemented via the Clock Algorithm).

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

# OSTEP Memory Virtualization Notes

花了一个星期读完了《Operating System: Three Easy Pieces》的 Memory Virtualization 部分，感觉收获很多。

## Ch12 A Dialogue on Memory Virtualization

很有趣的是在教科书里看到师生对话，通过师生对话的形式引出了内存虚拟化的问题，有点《论语》的味道哈哈哈。

## Ch13 The Abstraction: Address Spaces

程序员编程希望尽量简单，比如我们写 C 语言的时候 malloc 一个内存大小，然后就可以直接使用这个内存了，完全不需要关心这个内存是怎么来的，怎么存储的，怎么回收的。操作系统帮我们抽象了真实的物理内存，给我们提供了一个方便易用的虚拟的内存地址空间。

## Ch14 Interlude: Memory API

这一章讨论了 `malloc()` 和 `free()` 函数的基本实现。

`malloc()` 接收一个参数，表示需要分配的内存大小，返回一个指针，指向分配的内存。
`free()` 接收一个指针，表示需要释放的内存，释放内存。

以前我一直奇怪为什么 `free()` 只需要接受一个指针，而不需要引入内存大小。这是因为 `malloc()` 在分配内存的位置会再记录一下内存的大小，所以 `free()` 只需要知道要释放的内存的指针就可以知道要释放的内存的大小。

## Ch15 Mechanism: Address Translation

为了有效地对内存虚拟化，OS 要将 `virtual address` 转换为 `physical address`，这个转换过程叫做 `address translation`。

这一章节解释了 `dynamic relocation` 这种技术，这种技术需要使用两种寄存器来支持：

- `base register`：存储了 `virtual address` 的基地址
- `bounds register`：存储了 `virtual address` 的限制

此时，物理地址就等于 `virtual address + base register`.

其中硬件中的 `Memory Management Unit (MMU)` 负责将 `virtual address` 转换为 `physical address`。操作系统负责给进程分配空间（`base register` 和 `bounds`），并且在进程使用非法地址的时候触发异常。

这种 `dynamic relocation` 技术有一些限制，在给定的内存空间下，它对内存的使用是非常零散的，这被称为 `Internal Fragmentation`，内部碎片。

## Ch16 Segmentation

为了一定程度上缓解 `Internal Fragmentation`，操作系统引入了 `Segmentation` 技术。

`Segmentation` 将一个程序分为 `Code`, `Heap`, `Stack` 段，每个虚拟地址的高位表示段号，低位表示段内偏移。

这里面仍有问题。比如分配一个可变大小的段仍有问题。

- 因为段是可变长的，它会将内存分配为一个大小不均的块，这被称为 `External Fragmentation`，外部碎片。
- 分段的方法仍然不够灵活，如果有一个很大但稀疏的 `Heap`，这就需要很大的内存占用，这实际上是浪费的。

## Ch17 Free-Space Management

这一章节讨论了如何管理空闲的内存空间。

我们用一个链表来管理空闲的内存块，链表的每个节点表示一个空闲的内存块，包括内存块的大小和指向下一个内存块的指针。

如果要分配内存了，就从这个链表中找到一个"合适"的内存块分配，然后将这个内存块在链表中做分裂。
如果释放内存了，则将这个内存块加入到链表中，并考虑是否做些前后合并。

怎么找"合适"的内存块有许多策略，比如 `First-Fit`，`Best-Fit`，`Worst-Fit`。在实践中，有一个被广泛使用的策略，`Buddy` 算法。

Buddy 算法基本思想是将内存看作是 2 的幂大小的块。当请求内存时，找到最小的、但足够大的 2 的幂大小的空闲块。如果没有正好大小的块，可以将更大的块分裂为两个大小相等的块（Buddy），并把其中一个块分配出去。释放内存时，如果两个相邻的 Buddy 块都空闲，则将它们合并为一个更大的块。
（其实感觉这就像 ACM 中常用的线段树思想）

## Ch18 Paging: Introduction

为了解决大部分空间管理的问题，通常有两种方法。一种方式是将事物切分到可变长的块，正如前文中的 `Segmentation`。另一种方式是将事物切分到固定长的块，这就是 `Paging`，分页。

一个虚拟地址在 `Paging` 中被分为两部分：

- `Virtual Page Number (VPN)`：表示页号
- `Offset`：表示页内偏移，业内偏移的位数为 `Page Size` 的位数（如 4KB 的 Page，则位数为 12）

VPN 到 Page Table Entry (PTE) 的转化过程如下：

```c
VPN = (VirtualAddress & VPN_MASK) >> PAGE_SHIFT
PTEAddr = PageTableBaseRegister + (VPN * sizeof(PTE))
```

`PageTableBaseRegister` 简称 `PTBR`，表示页表基址寄存器。

具体的物理地址的计算过程如下：

```c
offset = VirtualAddress & OFFSET_MASK
PhysAddr = (PFN << PAGE_SHIFT) | offset
```

但当前的设计存在许多性能上的问题。

## Ch19 Paging: Faster Translation (TLBs)

> "When we want to make things fast, the OS usually needs some help. And help often comes from the OS's old friend: the hardware."

为了加速 `virtual address` 到 `physical address` 的转化，硬件引入了 `Translation Lookaside Buffer (TLB)`，这是芯片 Memory Management Unit (MMU) 的一部分。TLB 可以看作是 `address-translation cache`。

TLB Control Flow Algorithm:

```c
VPN = (VirtualAddress * VPN_MASK) >> PAGE_SHIFT
(Success, TlbEntry) = TLB_Lookup(VPN)
if (Success == True)
    if (CanAccess(TlbEntry.ProtectBits) == True)
        Offset = VirtualAddress & OFFSET_MASK
        PhyAddr = (TlbEntry.PFN << PAGE_SHIFT) | Offset
        Register = AccessMemory(PhyAddr)
    else
        RaiseException(PROTECTION_FAULT)
else
    PTEAddr = PTBR + (VPN * sizeof(PTE))
    PTE = AccessMemory(PTEAddr)
    if (PTE.Valid == False)
        RaiseException(SEGMENTATION_FAULT)
    else if (CanAccess(PTE.ProtectBits) == False)
        RaiseException(PROTECTION_FAULT)
    else
        TLB_Insert(VPN, PTE.PFN, PTE.ProtectBits)
        RetryInstruction()
```

TLB 很好，但是当触发 TLB miss，谁来处理呢？

有两种方式：

- 硬件
- 软件（OS）

早期，Complex Instruction Set Computer (`CISC`) 通常是硬件来处理。现代的架构，如 `RISC`，通常是软件来处理。当触发 TLB miss，硬件发起异常，将特权级切换到内核态，跳转到 `trap handler`，然后 `trap handler` 处理 TLB miss。

TLB 中的 `TLB_Entry` 结构如：

```c
VPN | PFN | other bits
```

这里的 `other bits` 通常包括 `valid` bit，表示这个翻译项是否有效。还有 `protection bits`，表示这个翻译项的权限，如对于 `code` page，通常是 `read and execute`，对于 `heap` page，通常是 `read and write`。

当上下文切换时，TLB 需要被更新。这有很多方法来处理：

- 最简单的，刷新所有 TLB 项
- 添加硬件支持，根据 id 号找到对应的 TLB 项。这个功能被称为 `Address Space Identifier (ASID)`。

## Ch20 Paging: Smaller Tables

假设一下，一个 32-bit 的地址空间，4KB 的页表，4-byte page-table entry。
因为页表为 4KB，所以 offset 为 12 位。因为地址空间是 32 位，所以可以存 2^20 个页表项。每个页表项为 4 字节，所以页表大小为 2^20 × 4B = 4MB。因为每个进程都需要一个页表，所以如果一个系统有 1000 个进程，就需要 1000 × 4MB = 4GB 的内存来存储页表。这是**非常大**的内存开销。

解决方案 1：更大的页表。

- 好处：页表的 entry 数量减少，页表大小减少。
- 坏处：内部碎片问题难以解决。

解决方案 2：多级页表。
用树状结构来组织页表，可以减少页表的大小。

对于一个二级页表，我们有一个 `Page Directory`，它存储了对页表的索引。
对于一个虚拟地址，形如 `PDE | PTE | offset`，`PDE` 表示页目录项，`PTE` 表示页表项，`offset` 表示页内偏移。
先根据 Page Directory 找到对应的页表，然后在根据 Page Table 找到对应的物理页。这其实就是**树状结构**，类似地，我们不难构造出多级页表。通过这种树形结构明显减少页表存储的内存开销。

- 好处：显著减少页表的内存开销。
- 坏处：增加内存访问次数（如二级页表需两次访存，可通过 TLB 缓解）

## Ch21 Beyond Physical Memory: Mechanisms

为了解决的问题：操作系统如何利用一个较大且较慢的设备，透明地提供一个更大的虚拟地址空间的假象？这个较大但速度慢的设备指的是磁盘（如果磁盘比内存快，那内存为什么不用磁盘 hhh）

因为物理地址空间有限，当 OS 运行一些大程序时，物理内存可能不够用，我们需要将部分页表放到 `Swap Space` 中。`Swap Space` 是一个较大的磁盘空间，用于存储被换出的页表。

在页表项中，我们会存放 `Present Bit`，表示这个页是否在物理内存中。当进程访问 `Present Bit` 为 0 的页时，就会触发一个 `page fault`，这个时候会调用操作系统的 `page fault handler`，将 `Swap Space` 中对应的数据加载到物理内存中。

## Ch22 Beyond Physical Memory: Policies

这一章主要讨论的是 Cache Management 策略。

书中给出了最优的策略，由 Belady 提出，即每次替换掉在将来最晚被访问的页 (`furthest in the future`)。但这个策略在现实中难以实现，因为我们实际上无法预先知道将来哪个页会被访问。

一个简单的策略是 `FIFO (First-In, First-Out)`，即先进先出。FIFO 有个最大的优势是实现相当简单，但劣势是这种先入先出的策略容易被一些 corner case 影响。

`Random Replacement`，即随机替换，可以避免 corner case 的影响，但有时性能会没那么好。

一个广泛使用的策略是 `Least Recently Used (LRU)`，即每次替换掉最久未被访问的页。但这个策略在实现上比较复杂，如果真的每次遍历所有页的访问时间，那么时间开销会非常大。我们用一个近似的策略来处理。

这里也需要 OS 的老朋友硬件来帮忙，我们要引入 `use bit`（也有的叫 `reference bit`），这个 bit 表示这个页最近是否被访问过。如果访问过则置为 1，至于什么时候置为 0，则取决于 OS 的策略。这有个简单易用的策略，叫 `Clock Algorithm`，时钟算法。

具体地，我们将页以环形链表组织，每个页有一个 `use bit`。我们用一个指针来遍历这个环形链表，当我们需要替换掉一个页时，先查看当前指针指向的页的 `use bit`，如果为 1，则将 `use bit` 置为 0，并移动指针到下一个页。如果为 0，则替换掉当前页。以此来实现一个近似的 LRU 策略。

## Ch23 Complete Virtual Memory Systems

这一章主要讨论的是现在的虚拟内存在真实的操作系统中的实现。（但感觉有点过于先进，我很多地方都看不懂）

书中主要讨论了两个操作系统，`VAX/VMS` 和 `Linux`。

### VAX/VMS 系统

VAX-11 使用 32-bit 的虚拟地址，每页 512 字节，采用 `segmentation` 和 `paging` 相结合的策略。

内存布局：分为 P0（用户程序和堆），P1（栈），S（系统）。

分页替换策略：

- 无硬件参考位。
- 使用 FIFO 替换策略
- 使用 clustering 来提升磁盘 IO 效率

加载优化：

- 按需零初始化（Demand Zeroing）
- 写时复制（Copy-On-Write）

这两种优化是常见的懒加载（Lazy Allocation）策略。

### Linux 系统

内存划分：典型 32 位 Linux 将地址空间分为用户空间和内核空间（0xC0000000 以上）。其中内核地址直接映射到物理地址。

页表采用四级页表。Linux 默认页表大小为 4KB，但是支持大页以支持数据库等应用，这需要用户配置。

其他的一些先进设计和安全讨论，我是真看不懂了。

## Ch24 Summary Dialogue on Memory Virtualization

通过师生对话的形式，总结了内存虚拟化整一章节的内容。

我自己理解过程：

OS 要帮助程序员更方便地使用内存，所以需要将内存抽象为虚拟地址空间。

虚拟地址空间需要被映射到物理地址空间，这个映射过程叫做地址翻译。

对虚拟地址基本的管理方式有：分段 (segmentation) 和分页 (paging)。

分段：将程序分为多个段，每个段有不同的权限和大小。

分页：将程序分为多个页，每个页有相同的大小。

由于页表存储的内存开销较大，所以需要采用多级页表来减少页表的内存开销。

由于访问页表需要多次访存，所以需要使用 TLB 来加速地址翻译。

但是 Cache 总会遇到一些 miss 的问题，所以需要采用一些替换策略来处理。这些策略有：FIFO, Random, LRU（具体的实现有 Clock Algorithm）

</div>

<script>
function switchLang(lang) {
  document.querySelectorAll('.lang-content').forEach(function(el) {
    el.style.display = 'none';
  });
  document.getElementById('lang-' + lang).style.display = 'block';
  document.querySelectorAll('.lang-switch a').forEach(function(el) {
    el.classList.remove('active');
  });
  document.querySelector('.lang-switch a[href="#' + lang + '"]').classList.add('active');
}
</script>

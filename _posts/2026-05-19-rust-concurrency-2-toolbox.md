---
title: "Rust Concurrency from Zero to Production (2): The Toolbox and the Problems"
date: 2026-05-19
categories:
  - tech
tags:
  - rust
  - concurrency
  - systems-programming
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

<script>
function switchLang(lang) {
  document.querySelectorAll('.lang-content').forEach(el => el.style.display = 'none');
  document.getElementById('lang-' + lang).style.display = '';
  document.querySelectorAll('.lang-switch a').forEach(a => {
    a.classList.remove('active');
    if (a.getAttribute('href') === '#' + lang) a.classList.add('active');
  });
}
</script>

<div class="lang-switch">
  <a class="active" href="#en" onclick="switchLang('en');return false">English</a>|
  <a href="#zh" onclick="switchLang('zh');return false">中文</a>
</div>

<div id="lang-en" class="lang-content" markdown="1">

This is Part 2 of a three-part series on Rust concurrency. In [Part 1]({% post_url 2026-05-19-rust-concurrency-1-foundation %}), we covered the foundations: ownership, `Send`/`Sync`, `Arc`, and `Result`. Now we fill the toolbox. Each primitive below appears in real production code — we'll see where and why.

By the end of this article, you'll be able to answer: "given a concurrency problem, which Rust primitive do I reach for?"

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

这是 Rust 并发系列三篇中的第二篇。在[第一篇]({% post_url 2026-05-19-rust-concurrency-1-foundation %})中，我们覆盖了基础：所有权、`Send`/`Sync`、`Arc` 和 `Result`。现在我们来填充工具箱。下面每个原语都出现在真实的生产代码中 — 我们会看到在哪里以及为什么。

读完这篇文章，你将能够回答："给定一个并发问题，我应该用哪个 Rust 原语？"

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 1. Threads vs Async — Two Flavors of Concurrency

Rust offers two concurrency models, and production code often uses both. The key is knowing when each fits.

### `std::thread` — OS Threads

Use when: CPU-bound work, blocking I/O, or when you need `!Send` types (thread locals, raw pointers in FFI).

```rust
use std::thread;

let handle = thread::spawn(|| {
    // This runs on a real OS thread.
    // Good for: heavy computation, C FFI, blocking syscalls.
    42
});

let result = handle.join().unwrap();  // wait, get return value
assert_eq!(result, 42);
```

In the asterinas kernel project, OS threads back the `WaitQueue` and spinlock-based synchronization. When you're inside a kernel, there is no async runtime — threads are the only option.

### `tokio::spawn` — Async Tasks

Use when: I/O-bound work, high concurrency (thousands of tasks), network requests.

```rust
use tokio::task;

let handle = task::spawn(async {
    // This runs on a tokio worker thread.
    // Good for: HTTP requests, DB queries, file I/O (tokio::fs).
    42
});

let result = handle.await.unwrap();  // .await, not .join()
assert_eq!(result, 42);
```

In the ChatPD pipeline, all 200 concurrent LLM API calls use `tokio::spawn`. Spawning 200 OS threads for network I/O would be wasteful — each thread has a stack (8MB by default) and scheduling overhead. Async tasks are lightweight state machines.

### The Decision Flowchart

```
Is the work CPU-bound or blocking?
  YES → std::thread (or rayon, or tokio::task::spawn_blocking)
  NO  → Is it I/O bound with high concurrency?
          YES → tokio::spawn
          NO  → Either works; prefer tokio for consistency
```

### Mixing: `spawn_blocking`

When async code must call a blocking function, use `spawn_blocking` to avoid starving the async runtime:

```rust
let data = tokio::task::spawn_blocking(|| {
    // This runs on a dedicated blocking thread pool.
    // The async runtime continues processing other tasks.
    std::fs::read_to_string("huge_file.json").unwrap()
}).await.unwrap();
```

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 1. 线程 vs 异步 — 并发的两种模式

Rust 提供两种并发模型，生产代码通常两者都使用。关键是知道每种适合什么场景。

### `std::thread` — 操作系统线程

适用场景：CPU 密集型工作、阻塞 I/O、或需要 `!Send` 类型时（线程局部存储、FFI 中的裸指针）。

```rust
use std::thread;

let handle = thread::spawn(|| {
    // 这运行在一个真实的 OS 线程上。
    // 适合：重计算、C FFI、阻塞系统调用。
    42
});

let result = handle.join().unwrap();  // 等待，获取返回值
assert_eq!(result, 42);
```

在 asterinas 内核项目中，OS 线程支撑着 `WaitQueue` 和基于 spinlock 的同步。在内核里没有异步运行时 — 线程是唯一选择。

### `tokio::spawn` — 异步任务

适用场景：I/O 密集型工作、高并发（数千个任务）、网络请求。

```rust
use tokio::task;

let handle = task::spawn(async {
    // 这运行在 tokio worker 线程上。
    // 适合：HTTP 请求、DB 查询、文件 I/O（tokio::fs）。
    42
});

let result = handle.await.unwrap();  // .await，不是 .join()
assert_eq!(result, 42);
```

在 ChatPD pipeline 中，所有 200 个并发的 LLM API 调用都使用 `tokio::spawn`。为网络 I/O 创建 200 个 OS 线程是浪费 — 每个线程有栈（默认 8MB）和调度开销。异步任务是轻量级状态机。

### 决策流程图

```
工作是 CPU 密集型或阻塞式的？
  是 → std::thread（或 rayon，或 tokio::task::spawn_blocking）
  否 → 是高并发的 I/O 密集型吗？
        是 → tokio::spawn
        否 → 两者都可以；为了一致性推荐 tokio
```

### 混合使用：`spawn_blocking`

当异步代码必须调用阻塞函数时，使用 `spawn_blocking` 以避免饿死异步运行时：

```rust
let data = tokio::task::spawn_blocking(|| {
    // 这运行在专用的阻塞线程池上。
    // 异步运行时继续处理其他任务。
    std::fs::read_to_string("huge_file.json").unwrap()
}).await.unwrap();
```

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 2. The Shared-State Triad: `Mutex`, `RwLock`, `Atomic*`

When multiple tasks need access to the same data, you have three tools. The trick is matching the tool to the access pattern.

### `Mutex<T>` — Mutual Exclusion

Every access — read or write — acquires the lock exclusively. Use when reads and writes are roughly balanced, or when the critical section is short.

```rust
use std::sync::{Arc, Mutex};

let counter = Arc::new(Mutex::new(0u64));

// In async code, use tokio::sync::Mutex for held-across-.await guards.
// In sync code, use std::sync::Mutex — faster, no async overhead.
let mut guard = counter.lock().unwrap();
*guard += 1;
```

In ChatPD, `Arc<Mutex<Connection>>` was the original pattern for database access. It worked, but every query — even read-only — contended on the same lock. This is the "one big lock" antipattern.

### `RwLock<T>` — Read-Many, Write-One

Multiple readers can hold the lock simultaneously. Writers get exclusive access. Use when reads vastly outnumber writes.

```rust
use std::sync::RwLock;
use std::time::Instant;

// From ChatPD: global rate-limit gate.
// Read by EVERY request before sending (high frequency).
// Written ONLY when 429/403 is received (rare).
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// Read path: cheap shared access
let until = *RATE_LIMITED_UNTIL.read().await;  // or .unwrap() for sync

// Write path: exclusive, rare
let mut guard = RATE_LIMITED_UNTIL.write().await;
*guard = Some(Instant::now() + Duration::from_secs(60));
```

**When to use which**:

| Pattern | Use |
|---------|-----|
| Reads ≈ writes | `Mutex` |
| Reads >> writes | `RwLock` |
| Single boolean or integer | `AtomicBool` / `AtomicUsize` |
| Struct with mixed fields | `Mutex` (simple) or split into multiple `Atomic*` (perf) |

### `Atomic*` — Lock-Free Primitives

For simple values — booleans, counters, flags — atomics avoid locks entirely:

```rust
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

// Abort flag: one writer sets it, many readers check it.
let abort = Arc::new(AtomicBool::new(false));

// Writer
abort.store(true, Ordering::Relaxed);

// Readers
if abort.load(Ordering::Relaxed) {
    return;  // stop work immediately
}

// Counter: many writers increment, one reader collects.
let success_ctr = Arc::new(AtomicUsize::new(0));
success_ctr.fetch_add(1, Ordering::Relaxed);
```

The `Ordering` argument controls memory ordering guarantees. For simple counters and flags where no other state depends on the value, `Relaxed` is sufficient and fastest. For state that must be visible in a specific order, use `Acquire`/`Release` or `SeqCst`.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 2. 共享状态三件套：`Mutex`、`RwLock`、`Atomic*`

当多个 task 需要访问同一数据时，你有三个工具。技巧在于根据访问模式选择合适的工具。

### `Mutex<T>` — 互斥锁

每次访问（读或写）都以独占方式获取锁。当读和写大致平衡，或临界区很短时使用。

```rust
use std::sync::{Arc, Mutex};

let counter = Arc::new(Mutex::new(0u64));

// 在异步代码中，如果用 .await 持有 guard，使用 tokio::sync::Mutex。
// 在同步代码中，使用 std::sync::Mutex — 更快，没有异步开销。
let mut guard = counter.lock().unwrap();
*guard += 1;
```

在 ChatPD 中，`Arc<Mutex<Connection>>` 是最初的数据库访问模式。它能工作，但每个查询 — 即使是只读 — 都在同一把锁上争用。这是"一把大锁"的反模式。

### `RwLock<T>` — 读写锁

多个读可以同时持有锁。写者获得独占访问。当读操作远超写操作时使用。

```rust
use std::sync::RwLock;
use std::time::Instant;

// 来自 ChatPD：全局限流闸门。
// 每个请求发送前都读（高频）。
// 仅在收到 429/403 时写（罕见）。
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// 读路径：廉价的共享访问
let until = *RATE_LIMITED_UNTIL.read().await;  // 或 .unwrap() 用于同步

// 写路径：独占，罕见
let mut guard = RATE_LIMITED_UNTIL.write().await;
*guard = Some(Instant::now() + Duration::from_secs(60));
```

**何时用哪个**：

| 模式 | 使用 |
|------|------|
| 读 ≈ 写 | `Mutex` |
| 读 >> 写 | `RwLock` |
| 单个布尔值或整数 | `AtomicBool` / `AtomicUsize` |
| 包含混合字段的结构体 | `Mutex`（简单）或拆成多个 `Atomic*`（性能） |

### `Atomic*` — 无锁原语

对于简单的值 — 布尔值、计数器、标志 — 原子操作完全避免锁：

```rust
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

// Abort flag：一个写入者设置它，多个读取者检查它。
let abort = Arc::new(AtomicBool::new(false));

// 写入者
abort.store(true, Ordering::Relaxed);

// 读取者
if abort.load(Ordering::Relaxed) {
    return;  // 立即停止工作
}

// 计数器：多个写入者递增，一个读取者收集。
let success_ctr = Arc::new(AtomicUsize::new(0));
success_ctr.fetch_add(1, Ordering::Relaxed);
```

`Ordering` 参数控制内存排序保证。对于简单的计数器和标志——没有其他状态依赖这个值时——`Relaxed` 既充分又最快。对于必须按特定顺序可见的状态，使用 `Acquire`/`Release` 或 `SeqCst`。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 3. Message Passing: Channels

Sometimes the best way to share state is to not share it at all. Channels let tasks communicate by sending values — each task owns its data, and ownership transfers through the channel.

### `mpsc::channel` — Multi-Producer, Single-Consumer

The workhorse. Multiple senders, one receiver. This is the backbone of the ChatPD pipeline:

```rust
use tokio::sync::mpsc;

let (tx, mut rx) = mpsc::channel::<WorkItem>(200);  // buffer 200 items

// Producer (many tasks)
let tx_clone = tx.clone();
tokio::spawn(async move {
    tx_clone.send(item).await.unwrap();
});

// Important: drop the original sender so the receiver knows when to stop.
drop(tx);

// Consumer (single task)
while let Some(item) = rx.recv().await {
    process(item).await;
}
// Loop exits when all senders are dropped.
```

**Why this beats shared state**:
- No locks. The consumer owns the data exclusively.
- Backpressure: when the buffer fills, `send().await` blocks the producer.
- Natural shutdown: drop all senders, receiver exits cleanly.

### The ChatPD Four-Stage Pipeline

This exact pattern connects four stages:

```
[Fetcher]  ──ch₁(Paper)──→  [Builder]  ──ch₂(Request)──→  [LLM Caller]  ──ch₃(Record)──→  [DB Writer]
   tx₁         rx₁             tx₂          rx₂               tx₃              rx₃
```

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

// Spawn four stages as separate tasks.
// Each stage owns its receiver, processes items, sends to the next stage.
// When a stage drops its sender, the next stage's "while let Some" ends.
```

Each stage runs independently at its own configured concurrency level. The channels provide both data transfer and flow control.

### `oneshot` and `broadcast` — For Other Patterns

`oneshot::channel()`: single value, one-shot. Like a Rust `Future` that resolves once. Use for "do this and tell me the result."

`broadcast::channel()`: one sender, many receivers. Each receiver gets a copy of every value. Use for events that multiple tasks need to observe.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 3. 消息传递：Channel

有时候共享状态的最好方式是不共享。Channel 让 task 通过发送值来通信 — 每个 task 拥有自己的数据，所有权通过 channel 转移。

### `mpsc::channel` — 多生产者，单消费者

主力。多个发送者，一个接收者。这是 ChatPD pipeline 的骨干：

```rust
use tokio::sync::mpsc;

let (tx, mut rx) = mpsc::channel::<WorkItem>(200);  // 缓冲 200 项

// 生产者（多个 task）
let tx_clone = tx.clone();
tokio::spawn(async move {
    tx_clone.send(item).await.unwrap();
});

// 重要：drop 原始 sender，让 receiver 知道何时停止。
drop(tx);

// 消费者（单个 task）
while let Some(item) = rx.recv().await {
    process(item).await;
}
// 当所有 sender 被 drop 时，循环退出。
```

**为什么这比共享状态更好**：
- 没有锁。消费者独占数据。
- 背压：当缓冲区满时，`send().await` 会阻塞生产者。
- 自然关闭：drop 所有 sender，receiver 优雅退出。

### ChatPD 四级管道

这个确切的模式连接了四个阶段：

```
[Fetcher]  ──ch₁(Paper)──→  [Builder]  ──ch₂(Request)──→  [LLM Caller]  ──ch₃(Record)──→  [DB Writer]
   tx₁         rx₁             tx₂          rx₂               tx₃              rx₃
```

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

// 将四个阶段作为独立 task 创建。
// 每个阶段拥有自己的 receiver，处理数据项，发送到下一阶段。
// 当一个阶段 drop 它的 sender 时，下一阶段的 "while let Some" 结束。
```

每个阶段以自己配置的并发级别独立运行。Channel 同时提供数据传输和流控。

### `oneshot` 和 `broadcast` — 其他模式

`oneshot::channel()`：单值，一次性。类似一个只 resolve 一次的 Rust `Future`。用于"做这个然后告诉我结果"。

`broadcast::channel()`：一个发送者，多个接收者。每个接收者获得每个值的副本。用于多个 task 需要观察的事件。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 4. Concurrency Control: Three Patterns

Pipelines aren't one-size-fits-all. Depending on the workload, you need different concurrency control strategies.

### Pattern A: `buffer_unordered(n)` — Fixed Concurrency Window

When you know the right concurrency level and it doesn't change:

```rust
use futures::StreamExt;

futures::stream::iter(items)
    .map(|item| async move { process(item).await })
    .buffer_unordered(48)   // at most 48 concurrent
    .for_each(|result| async { /* handle result */ })
    .await;
```

Used in ChatPD for the builder stage (48 concurrent request builders) and LLM caller stage (200 concurrent). Simple, no runtime tuning needed.

### Pattern B: `Semaphore` — Adaptive Concurrency

When you want to start conservatively and ramp up after seeing success:

```rust
use tokio::sync::Semaphore;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

let initial = 4;
let max_concurrency = 32;
let sem = Arc::new(Semaphore::new(initial));
let success_ctr = Arc::new(AtomicUsize::new(0));
let cur_permits = Arc::new(AtomicUsize::new(initial));

for item in items {
    let permit = sem.clone().acquire_owned().await.unwrap();

    tokio::spawn(async move {
        let result = process(item).await;

        if result.is_ok() {
            let n = success_ctr.fetch_add(1, Ordering::Relaxed) + 1;
            if n % 24 == 0 {  // every 24 successes
                let cur = cur_permits.load(Ordering::Relaxed);
                if cur < max_concurrency {
                    cur_permits.fetch_add(1, Ordering::Relaxed);
                    sem.add_permits(1);  // add one more slot
                }
            }
        }

        drop(permit);
    });
}
```

Used in ChatPD for the fetch stage: starts at 4 concurrent fetches, ramps to 32 after 24 * (32-4) = 672 successful fetches. This is a "soft start" that discovers the service's actual capacity rather than assuming it.

### Pattern C: `JoinSet` — Dynamic Task Collection

When you don't know how many tasks you'll spawn in advance, or tasks complete at different rates:

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();

for item in items {
    set.spawn(async move {
        process(item).await
    });
}

// Collect results as they complete
while let Some(result) = set.join_next().await {
    match result {
        Ok(output) => handle(output),
        Err(panic_err) => eprintln!("task panicked: {}", panic_err),
    }
}
```

`JoinSet` handles task lifecycle: you can `spawn`, `abort`, and collect results without tracking individual `JoinHandle`s. Used in ChatPD's fetch stage for round 0.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 4. 并发控制：三种模式

管道不是一种尺寸适合所有情况。根据工作负载，你需要不同的并发控制策略。

### 模式 A：`buffer_unordered(n)` — 固定并发窗口

当你事先知道正确的并发级别且它不变化时：

```rust
use futures::StreamExt;

futures::stream::iter(items)
    .map(|item| async move { process(item).await })
    .buffer_unordered(48)   // 最多 48 个并发
    .for_each(|result| async { /* 处理结果 */ })
    .await;
```

在 ChatPD 中用于 builder 阶段（48 并发请求构建器）和 LLM caller 阶段（200 并发）。简单，无需运行时调整。

### 模式 B：`Semaphore` — 自适应并发

当你想保守地开始，在成功之后递增并发时：

```rust
use tokio::sync::Semaphore;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

let initial = 4;
let max_concurrency = 32;
let sem = Arc::new(Semaphore::new(initial));
let success_ctr = Arc::new(AtomicUsize::new(0));
let cur_permits = Arc::new(AtomicUsize::new(initial));

for item in items {
    let permit = sem.clone().acquire_owned().await.unwrap();

    tokio::spawn(async move {
        let result = process(item).await;

        if result.is_ok() {
            let n = success_ctr.fetch_add(1, Ordering::Relaxed) + 1;
            if n % 24 == 0 {  // 每 24 次成功
                let cur = cur_permits.load(Ordering::Relaxed);
                if cur < max_concurrency {
                    cur_permits.fetch_add(1, Ordering::Relaxed);
                    sem.add_permits(1);  // 增加一个槽位
                }
            }
        }

        drop(permit);
    });
}
```

在 ChatPD 中用于 fetch 阶段：从 4 个并发 fetch 开始，在 24 * (32-4) = 672 次成功后逐步爬坡到 32。这是一个"软启动"，发现服务的实际容量而不是假设它。

### 模式 C：`JoinSet` — 动态任务集合

当你事先不知道会有多少 task，或者 task 以不同的速度完成时：

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();

for item in items {
    set.spawn(async move {
        process(item).await
    });
}

// 当 task 完成时收集结果
while let Some(result) = set.join_next().await {
    match result {
        Ok(output) => handle(output),
        Err(panic_err) => eprintln!("task panicked: {}", panic_err),
    }
}
```

`JoinSet` 管理 task 生命周期：你可以 `spawn`、`abort` 和收集结果，而不需要追踪单个 `JoinHandle`。在 ChatPD 的 fetch 阶段 round 0 中使用。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 5. Errors in Concurrent Code: The Propagation Problem

In sequential code, `?` propagates errors up the call stack. In concurrent code, errors happen in separate tasks with separate call stacks. You need an explicit strategy.

### Strategy 1: Task-Local Errors → `Result`

Each task returns a `Result`. The collector (the task that `.awaits` the `JoinHandle`) handles the error:

```rust
let handle = tokio::spawn(async {
    fallible_work().await?;  // error stays inside this task
    Ok::<_, MyError>(())
});

match handle.await.unwrap() {
    Ok(()) => println!("task succeeded"),
    Err(e) => eprintln!("task failed: {}", e),
}
```

### Strategy 2: Global Fatal Error → `AtomicBool`

When one task detects a fatal condition (API quota exhausted, disk full), all tasks should stop:

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// In each worker:
if err_str.contains("quota exhausted") {
    eprintln!("FATAL: aborting pipeline");
    abort_flag.store(true, Ordering::Relaxed);
    return;
}

// At the start of each work item:
if abort_flag.load(Ordering::Relaxed) {
    return;  // stop processing, don't produce records
}

// After all tasks complete, check the flag:
if abort_flag.load(Ordering::Relaxed) {
    return Err("pipeline aborted: API quota exhausted".into());
}
```

### Strategy 3: Terminal vs Transient Errors

Not all errors are equal. In ChatPD, the `classify_error()` function distinguishes:
- **Terminal errors**: `SourceUnavailable`, `NoDatasetContent`, `ProcessingFailed` → write error record, don't retry
- **Transient errors**: 429, 403, timeout, connection error → retry with backoff
- **Fatal errors**: 401, quota exhausted → abort pipeline immediately

```rust
fn is_transient_error(err: &str) -> bool {
    err.contains("429") || err.contains("403")
        || err.contains("timed out") || err.contains("connection")
}

fn is_fatal_error(err: &str) -> bool {
    err.contains("401") || err.contains("quota")
}
```

### Strategy 4: Task Panic → `JoinHandle`

If a task panics, the `JoinHandle` returns `Err(JoinError)`. Always handle this:

```rust
let handle = tokio::spawn(async { panic!("oops") });
match handle.await {
    Ok(_) => println!("task completed"),
    Err(e) => eprintln!("task panicked: {}", e),
}
```

In `JoinSet`, panics arrive via `join_next().await`:

```rust
while let Some(result) = set.join_next().await {
    if let Err(e) = result {
        eprintln!("task panicked: {}", e);
        // Decide: abort all tasks, or continue?
    }
}
```

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 5. 并发代码中的错误：传播问题

在顺序代码中，`?` 沿着调用栈传播错误。在并发代码中，错误发生在拥有独立调用栈的独立 task 中。你需要一套明确的策略。

### 策略 1：Task 局部错误 → `Result`

每个 task 返回一个 `Result`。收集者（`.await` 了 `JoinHandle` 的 task）处理错误：

```rust
let handle = tokio::spawn(async {
    fallible_work().await?;  // 错误保持在这个 task 内部
    Ok::<_, MyError>(())
});

match handle.await.unwrap() {
    Ok(()) => println!("task 成功"),
    Err(e) => eprintln!("task 失败：{}", e),
}
```

### 策略 2：全局致命错误 → `AtomicBool`

当一个 task 检测到致命条件（API quota 耗尽、磁盘满）时，所有 task 都应该停止：

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// 在每个 worker 中：
if err_str.contains("quota exhausted") {
    eprintln!("致命错误：中止 pipeline");
    abort_flag.store(true, Ordering::Relaxed);
    return;
}

// 在每个工作项的开头：
if abort_flag.load(Ordering::Relaxed) {
    return;  // 停止处理，不产生记录
}

// 在所有 task 完成后，检查 flag：
if abort_flag.load(Ordering::Relaxed) {
    return Err("pipeline aborted: API quota exhausted".into());
}
```

### 策略 3：终端错误 vs 瞬时错误

并非所有错误都一样。在 ChatPD 中，`classify_error()` 函数区分：
- **终端错误**：`SourceUnavailable`、`NoDatasetContent`、`ProcessingFailed` → 写错误记录，不重试
- **瞬时错误**：429、403、timeout、连接错误 → 退避重试
- **致命错误**：401、quota 耗尽 → 立即中止 pipeline

```rust
fn is_transient_error(err: &str) -> bool {
    err.contains("429") || err.contains("403")
        || err.contains("timed out") || err.contains("connection")
}

fn is_fatal_error(err: &str) -> bool {
    err.contains("401") || err.contains("quota")
}
```

### 策略 4：Task Panic → `JoinHandle`

如果一个 task panic 了，`JoinHandle` 返回 `Err(JoinError)`。始终处理它：

```rust
let handle = tokio::spawn(async { panic!("oops") });
match handle.await {
    Ok(_) => println!("task 完成"),
    Err(e) => eprintln!("task panic 了：{}", e),
}
```

在 `JoinSet` 中，panic 通过 `join_next().await` 到达：

```rust
while let Some(result) = set.join_next().await {
    if let Err(e) = result {
        eprintln!("task panic 了：{}", e);
        // 决定：中止所有 task，还是继续？
    }
}
```

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 6. Combined Exercise: A Rate-Limited Concurrent Fetcher

Let's build the core of what we've learned: a concurrent HTTP fetcher with a global rate-limit gate, retry with exponential backoff, and graceful shutdown.

```rust
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

struct RateLimitGate {
    until: RwLock<Option<Instant>>,
}

impl RateLimitGate {
    fn new() -> Self {
        Self { until: RwLock::new(None) }
    }

    async fn set_cooldown(&self, secs: u64) {
        let deadline = Instant::now() + Duration::from_secs(secs);
        let mut guard = self.until.write().await;
        if guard.map_or(true, |t| t < deadline) {
            *guard = Some(deadline);
        }
    }

    async fn wait_if_needed(&self) {
        loop {
            let until = *self.until.read().await;
            match until {
                None => return,
                Some(t) if t <= Instant::now() => return,
                Some(t) => tokio::time::sleep(t - Instant::now()).await,
            }
        }
    }
}

async fn fetch_with_retry(
    client: &reqwest::Client,
    url: &str,
    gate: &Arc<RateLimitGate>,
    max_retries: u32,
) -> Result<String, String> {
    for retry in 0..max_retries {
        gate.wait_if_needed().await;

        match client.get(url).send().await {
            Ok(resp) if resp.status().is_success() => {
                return resp.text().await.map_err(|e| e.to_string());
            }
            Ok(resp) if resp.status().as_u16() == 429 => {
                gate.set_cooldown(60).await;
                let backoff = Duration::from_millis(500 * 2u64.pow(retry));
                tokio::time::sleep(backoff).await;
            }
            Ok(resp) => {
                return Err(format!("HTTP {}", resp.status()));
            }
            Err(e) if e.is_timeout() => {
                let backoff = Duration::from_millis(500 * 2u64.pow(retry));
                tokio::time::sleep(backoff).await;
            }
            Err(e) => return Err(e.to_string()),
        }
    }
    Err("max retries exhausted".to_string())
}
```

Exercise: extend this to use `Semaphore` for adaptive concurrency control, add an `AtomicBool` abort flag, and connect the fetcher output to a channel pipeline.

---

In [Part 3]({% post_url 2026-05-19-rust-concurrency-3-advanced %}), we'll walk through five real concurrency bugs from production, their root causes, and the elegant Rust solutions we built.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 6. 综合练习：带限流的并发 HTTP 请求器

让我们构建我们所学内容的核心：一个带有全局限流闸门、指数退避重试和优雅停机的并发 HTTP 请求器。

```rust
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

struct RateLimitGate {
    until: RwLock<Option<Instant>>,
}

impl RateLimitGate {
    fn new() -> Self {
        Self { until: RwLock::new(None) }
    }

    async fn set_cooldown(&self, secs: u64) {
        let deadline = Instant::now() + Duration::from_secs(secs);
        let mut guard = self.until.write().await;
        if guard.map_or(true, |t| t < deadline) {
            *guard = Some(deadline);
        }
    }

    async fn wait_if_needed(&self) {
        loop {
            let until = *self.until.read().await;
            match until {
                None => return,
                Some(t) if t <= Instant::now() => return,
                Some(t) => tokio::time::sleep(t - Instant::now()).await,
            }
        }
    }
}

async fn fetch_with_retry(
    client: &reqwest::Client,
    url: &str,
    gate: &Arc<RateLimitGate>,
    max_retries: u32,
) -> Result<String, String> {
    for retry in 0..max_retries {
        gate.wait_if_needed().await;

        match client.get(url).send().await {
            Ok(resp) if resp.status().is_success() => {
                return resp.text().await.map_err(|e| e.to_string());
            }
            Ok(resp) if resp.status().as_u16() == 429 => {
                gate.set_cooldown(60).await;
                let backoff = Duration::from_millis(500 * 2u64.pow(retry));
                tokio::time::sleep(backoff).await;
            }
            Ok(resp) => {
                return Err(format!("HTTP {}", resp.status()));
            }
            Err(e) if e.is_timeout() => {
                let backoff = Duration::from_millis(500 * 2u64.pow(retry));
                tokio::time::sleep(backoff).await;
            }
            Err(e) => return Err(e.to_string()),
        }
    }
    Err("超过最大重试次数".to_string())
}
```

练习：扩展这个例子，使用 `Semaphore` 进行自适应并发控制，添加 `AtomicBool` abort flag，并将请求器输出连接到 channel 管道中。

---

在[第三篇]({% post_url 2026-05-19-rust-concurrency-3-advanced %})中，我们将走查五个来自生产的真实并发 bug，它们的根因分析，以及我们构建的优雅 Rust 解决方案。

</div>

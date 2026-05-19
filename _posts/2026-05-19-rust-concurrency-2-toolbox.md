---
title: "Rust Concurrency from Zero to Production (2): Threads, Locks, Channels, and Control"
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

[Part 1](/tech/rust-concurrency-1-foundation/) covered ownership, `Send`/`Sync`, `Arc`, and `Result`. This article fills the toolbox: threads vs async, the three shared-state primitives, channels, and concurrency control patterns. Everything here is backed by real use in production — I'll note where each pattern appears in ChatPD, asterinas, or mcpr.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

[第一篇](/tech/rust-concurrency-1-foundation/) 讲了所有权、`Send`/`Sync`、`Arc` 和 `Result`。这篇来填充工具箱：线程与异步、三个共享状态原语、channel、以及并发控制模式。每个模式和原语都标注了在 ChatPD、asterinas 或 mcpr 中的实际使用位置。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 1. Threads vs Async

Rust offers two concurrency models. Production code often uses both — the question is which fits the workload.

### `std::thread` — OS Threads

```rust
use std::thread;

let handle = thread::spawn(|| {
    // Runs on a real OS thread.
    // Suited for: heavy computation, C FFI, blocking syscalls.
    42
});

let result = handle.join().unwrap();
```

In the asterinas kernel, OS threads back `WaitQueue` and spinlock-based synchronization. Inside a kernel there's no async runtime — threads are the only option.

For CPU-bound work in userspace, `rayon` provides a parallel iterator API that distributes work across a thread pool without manual `spawn`/`join`.

### `tokio::spawn` — Async Tasks

```rust
use tokio::task;

let handle = task::spawn(async {
    // Runs on a tokio worker thread.
    // Suited for: HTTP requests, DB queries, file I/O (tokio::fs).
    42
});

let result = handle.await.unwrap();  // .await, not .join()
```

In the ChatPD pipeline, all 200 concurrent LLM API calls use `tokio::spawn`. Spawning 200 OS threads for network I/O would be wasteful — each thread carries an 8MB stack (default) and scheduling overhead. Async tasks are lightweight state machines managed by the tokio runtime.

### The Rough Heuristic

```
CPU-bound or blocking?
  → std::thread (or rayon, or tokio::task::spawn_blocking)
I/O-bound with high concurrency?
  → tokio::spawn
Either could work?
  → prefer tokio for consistency within an async codebase
```

### When Async Code Must Block

`spawn_blocking` moves blocking work off the async runtime's thread pool:

```rust
let data = tokio::task::spawn_blocking(|| {
    std::fs::read_to_string("huge_file.json").unwrap()
}).await.unwrap();
```

Without this, a blocking call on a tokio worker thread starves other tasks. The blocking thread pool is separate — the async runtime continues processing while the blocking work runs.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 1. 线程与异步

Rust 提供两种并发模型。生产代码通常两者都用——问题是哪种适合工作负载。

### `std::thread` — 操作系统线程

```rust
use std::thread;

let handle = thread::spawn(|| {
    // 运行在真实的 OS 线程上。
    // 适合：重计算、C FFI、阻塞系统调用。
    42
});

let result = handle.join().unwrap();
```

在 asterinas 内核中，OS 线程支撑着 `WaitQueue` 和基于 spinlock 的同步。内核里没有异步运行时——线程是唯一选择。

对于用户空间的 CPU 密集型工作，`rayon` 提供了并行迭代器 API，在不需要手动 `spawn`/`join` 的情况下将工作分布到线程池。

### `tokio::spawn` — 异步任务

```rust
use tokio::task;

let handle = task::spawn(async {
    // 运行在 tokio worker 线程上。
    // 适合：HTTP 请求、DB 查询、文件 I/O（tokio::fs）。
    42
});

let result = handle.await.unwrap();  // .await，不是 .join()
```

在 ChatPD 管道中，所有 200 个并发的 LLM API 调用都使用 `tokio::spawn`。为网络 I/O 创建 200 个 OS 线程是浪费——每个线程有默认 8MB 的栈和调度开销。异步任务是 tokio 运行时管理的轻量级状态机。

### 粗略的决策规则

```
CPU 密集型或阻塞式？
  → std::thread（或 rayon，或 tokio::task::spawn_blocking）
高并发的 I/O 密集型？
  → tokio::spawn
都可以？
  → 在异步代码库中用 tokio 保持一致性
```

### 当异步代码必须阻塞时

`spawn_blocking` 将阻塞工作移出异步运行时的线程池：

```rust
let data = tokio::task::spawn_blocking(|| {
    std::fs::read_to_string("huge_file.json").unwrap()
}).await.unwrap();
```

没有它，tokio worker 线程上的阻塞调用会饿死其他任务。阻塞线程池是独立的——阻塞工作运行时，异步运行时继续处理其他任务。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 2. Shared State: `Mutex`, `RwLock`, `Atomic*`

When multiple tasks access the same data, three primitives cover most cases. The trick is matching the tool to the access pattern.

### `Mutex<T>` — Mutual Exclusion

Every access — read or write — acquires the lock exclusively. Use when reads and writes are roughly balanced, or the critical section is short.

```rust
use std::sync::{Arc, Mutex};

let counter = Arc::new(Mutex::new(0u64));
let mut guard = counter.lock().unwrap();
*guard += 1;
// lock released when guard goes out of scope
```

In async code, if the guard is held across `.await` points, `tokio::sync::Mutex` is needed. For synchronous code, `std::sync::Mutex` is faster.

In ChatPD, `Arc<Mutex<Connection>>` was the original database access pattern. It worked for low concurrency, but became a bottleneck as the pipeline scaled — every query contended on the same lock.

### `RwLock<T>` — Read-Many, Write-One

Multiple readers hold the lock simultaneously. Writers get exclusive access. Use when reads vastly outnumber writes.

```rust
use std::sync::RwLock;
use std::time::Instant;

// ChatPD's global rate-limit gate:
// Read by EVERY request before sending (high frequency).
// Written ONLY on 429/403 (rare).
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// Read path: cheap shared access, no contention in common case
let until = *RATE_LIMITED_UNTIL.read().await;

// Write path: exclusive, rare
let mut guard = RATE_LIMITED_UNTIL.write().await;
*guard = Some(Instant::now() + Duration::from_secs(60));
```

**How to choose**:

| Access pattern | Primitive |
|---------------|-----------|
| Reads ≈ writes | `Mutex` |
| Reads ≫ writes | `RwLock` |
| Single boolean or integer | `AtomicBool` / `AtomicUsize` |
| Struct with mixed fields | `Mutex` (simple) or split into `Atomic*` fields (perf) |

### `Atomic*` — Lock-Free Primitives

For simple values — booleans, counters, flags — atomics avoid locks entirely:

```rust
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

// Abort flag: one writer sets, many readers check.
let abort = Arc::new(AtomicBool::new(false));
abort.store(true, Ordering::Relaxed);       // writer
if abort.load(Ordering::Relaxed) { return; } // reader

// Counter: many writers increment, one reader collects.
let counter = Arc::new(AtomicUsize::new(0));
counter.fetch_add(1, Ordering::Relaxed);
```

`Ordering::Relaxed` is sufficient — and fastest — when the value has no ordering dependency with other state. For values that must be visible in a specific order relative to other memory operations, `Acquire`/`Release` or `SeqCst` apply.

The `AtomicU8` pattern in asterinas's `klog.rs` is a nice example: `console_level` is stored as `AtomicU8`, enabling atomic `swap()` for set-with-return-old-value without a full lock.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 2. 共享状态：`Mutex`、`RwLock`、`Atomic*`

当多个 task 访问同一数据时，三个原语覆盖大多数情况。技巧在于根据访问模式选择合适的工具。

### `Mutex<T>` — 互斥锁

每次访问（读或写）都以独占方式获取锁。当读和写大致平衡，或临界区很短时使用。

```rust
use std::sync::{Arc, Mutex};

let counter = Arc::new(Mutex::new(0u64));
let mut guard = counter.lock().unwrap();
*guard += 1;
// guard 离开作用域时锁被释放
```

在异步代码中，如果 guard 需要跨越 `.await` 点持有，要用 `tokio::sync::Mutex`。同步代码中 `std::sync::Mutex` 更快。

在 ChatPD 中，`Arc<Mutex<Connection>>` 是最初的数据库访问模式。低并发时工作正常，但随着管道扩展成为瓶颈——每个查询都在同一把锁上争用。

### `RwLock<T>` — 读写锁

多个读可以同时持有锁，写者获得独占访问。当读操作远超写操作时使用。

```rust
use std::sync::RwLock;
use std::time::Instant;

// ChatPD 的全局限流闸门：
// 每个请求发送前都读（高频）。
// 仅在收到 429/403 时写（罕见）。
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// 读路径：廉价的共享访问，常见情况下无争用
let until = *RATE_LIMITED_UNTIL.read().await;

// 写路径：独占，罕见
let mut guard = RATE_LIMITED_UNTIL.write().await;
*guard = Some(Instant::now() + Duration::from_secs(60));
```

**如何选择**：

| 访问模式 | 原语 |
|---------|------|
| 读 ≈ 写 | `Mutex` |
| 读 ≫ 写 | `RwLock` |
| 单个布尔值或整数 | `AtomicBool` / `AtomicUsize` |
| 包含混合字段的结构体 | `Mutex`（简单）或拆成 `Atomic*` 字段（性能） |

### `Atomic*` — 无锁原语

对于简单值——布尔值、计数器、标志——原子操作完全避免锁：

```rust
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

// Abort flag：一个写入者设置，多个读取者检查。
let abort = Arc::new(AtomicBool::new(false));
abort.store(true, Ordering::Relaxed);       // 写入者
if abort.load(Ordering::Relaxed) { return; } // 读取者

// 计数器：多个写入者递增，一个读取者收集。
let counter = Arc::new(AtomicUsize::new(0));
counter.fetch_add(1, Ordering::Relaxed);
```

当值与其他状态没有排序依赖时，`Ordering::Relaxed` 既充分又最快。对于必须相对于其他内存操作以特定顺序可见的值，适用 `Acquire`/`Release` 或 `SeqCst`。

asterinas `klog.rs` 中的 `AtomicU8` 模式是一个好例子：`console_level` 存储为 `AtomicU8`，支持原子 `swap()` 实现"设置并返回旧值"，不需要完整的锁。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 3. Message Passing: Channels

Sometimes sharing state by not sharing it is simpler. Channels let tasks communicate by sending values — each task owns its data, and ownership transfers through the channel.

### `mpsc::channel` — Multi-Producer, Single-Consumer

The workhorse. Multiple senders, one receiver. This is the backbone of ChatPD's four-stage pipeline:

```rust
use tokio::sync::mpsc;

let (tx, mut rx) = mpsc::channel::<WorkItem>(200);  // buffer 200 items

// Producer (cloned sender per task)
let tx1 = tx.clone();
tokio::spawn(async move { tx1.send(item).await.unwrap(); });

// Drop the original sender — without this, the receiver never exits.
drop(tx);

// Consumer (single task, owns the receiver)
while let Some(item) = rx.recv().await {
    process(item).await;
}
// Loop exits when ALL senders are dropped.
```

Three properties make this pattern reliable for pipelines:

1. **No locks.** The consumer owns received data exclusively.
2. **Backpressure.** When the buffer fills, `send().await` blocks the producer — natural flow control.
3. **Natural shutdown.** Drop all senders and the receiver exits cleanly. No shutdown messages needed.

### ChatPD's Four-Stage Pipeline

```
[Fetcher]  ──ch₁(Paper)──→  [Builder]  ──ch₂(Request)──→  [LLM Caller]  ──ch₃(Record)──→  [DB Writer]
```

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

// Each stage owns its receiver, processes items, sends to the next.
let fetcher  = tokio::spawn(run_fetcher(input, paper_tx, write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(paper_rx, req_tx, write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(req_rx, write_tx.clone(), ...));
drop(write_tx);  // signal: no more upstream producers
let db_writer = tokio::spawn(run_db_writer(write_rx, ...));
```

Each stage runs at its own concurrency level. The channels provide both data transfer and flow control — when one stage slows down, upstream producers naturally block on `send()`.

### Other Channel Types

`oneshot::channel()` — single value, one time. Like a `Future` that resolves once. Use for request-response: "do this and tell me the result."

`broadcast::channel()` — one sender, many receivers. Each receiver gets a copy of every value. Use for events multiple tasks need to observe.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 3. 消息传递：Channel

有时候不共享状态比共享更简单。Channel 让 task 通过发送值来通信——每个 task 拥有自己的数据，所有权通过 channel 转移。

### `mpsc::channel` — 多生产者，单消费者

主力。多个发送者，一个接收者。这是 ChatPD 四级管道的骨干：

```rust
use tokio::sync::mpsc;

let (tx, mut rx) = mpsc::channel::<WorkItem>(200);  // 缓冲 200 项

// 生产者（每个 task 克隆 sender）
let tx1 = tx.clone();
tokio::spawn(async move { tx1.send(item).await.unwrap(); });

// Drop 原始 sender — 没有这步，receiver 永远不会退出。
drop(tx);

// 消费者（单个 task，拥有 receiver）
while let Some(item) = rx.recv().await {
    process(item).await;
}
// 当所有 sender 被 drop 时循环退出。
```

三个特性使这个模式对管道可靠：

1. **没有锁。** 消费者独占接收到的数据。
2. **背压。** 缓冲区满时 `send().await` 阻塞生产者——自然的流控。
3. **自然关机。** Drop 所有 sender，receiver 干净退出。不需要关机消息。

### ChatPD 的四级管道

```
[Fetcher]  ──ch₁(Paper)──→  [Builder]  ──ch₂(Request)──→  [LLM Caller]  ──ch₃(Record)──→  [DB Writer]
```

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

// 每个阶段拥有自己的 receiver，处理数据项，发送到下一阶段。
let fetcher  = tokio::spawn(run_fetcher(input, paper_tx, write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(paper_rx, req_tx, write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(req_rx, write_tx.clone(), ...));
drop(write_tx);  // 信号：不再有上游生产者
let db_writer = tokio::spawn(run_db_writer(write_rx, ...));
```

每个阶段以自己配置的并发级别运行。Channel 同时提供数据传输和流控——当一个阶段变慢时，上游生产者自然在 `send()` 上阻塞。

### 其他 Channel 类型

`oneshot::channel()` — 单值，一次性。类似一个只 resolve 一次的 `Future`。用于请求-响应："做这个然后告诉我结果。"

`broadcast::channel()` — 一个发送者，多个接收者。每个接收者获得每个值的副本。用于多个 task 需要观察的事件。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 4. Concurrency Control: Three Patterns

Different workloads need different strategies for controlling how many tasks run at once.

### Pattern A: `buffer_unordered(n)` — Fixed Window

When the right concurrency level is known and doesn't change:

```rust
use futures::StreamExt;

futures::stream::iter(items)
    .map(|item| async move { process(item).await })
    .buffer_unordered(48)   // at most 48 concurrent
    .for_each(|result| async { /* handle result */ })
    .await;
```

Used in ChatPD for the builder stage (48 concurrent) and LLM caller stage (200 concurrent). Simple, no runtime tuning.

### Pattern B: `Semaphore` — Adaptive Concurrency

When starting conservatively and ramping up after success is safer:

```rust
use tokio::sync::Semaphore;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

let initial = 4;
let max = 32;
let sem = Arc::new(Semaphore::new(initial));
let success_ctr = Arc::new(AtomicUsize::new(0));
let cur_permits = Arc::new(AtomicUsize::new(initial));

for item in items {
    let permit = sem.clone().acquire_owned().await.unwrap();

    tokio::spawn(async move {
        if process(item).await.is_ok() {
            let n = success_ctr.fetch_add(1, Ordering::Relaxed) + 1;
            if n % 24 == 0 {  // every 24 successes, add one more slot
                let cur = cur_permits.load(Ordering::Relaxed);
                if cur < max {
                    cur_permits.fetch_add(1, Ordering::Relaxed);
                    sem.add_permits(1);
                }
            }
        }
        drop(permit);
    });
}
```

ChatPD's fetcher uses this: start at 4 concurrent fetches, ramp to 32 after enough successes. This discovers the external service's actual capacity rather than assuming the configured limit is always available.

The semaphore only ramps up, never down. Rate-limit backoff is handled separately by a global gate (covered in Part 3). Keeping these concerns separate avoids oscillation.

### Pattern C: `JoinSet` — Dynamic Task Collection

When the number of tasks isn't known in advance, or tasks complete at different rates:

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();

for item in items {
    set.spawn(async move { process(item).await });
}

// Collect results as they complete
while let Some(result) = set.join_next().await {
    match result {
        Ok(output) => handle(output),
        Err(panic_err) => eprintln!("task panicked: {}", panic_err),
    }
}
```

`JoinSet` manages the task lifecycle — spawn, collect, handle panics — without tracking individual `JoinHandle`s. ChatPD's fetch stage uses this for round 0.

### Retry Rounds with Decreasing Concurrency

ChatPD's fetcher adds one more idea: papers that fail with transient errors go into retry rounds. Each round uses *fixed* concurrency that *decreases*:

```rust
fn fetch_round_concurrency(cap: usize, round: usize) -> usize {
    (cap / (round + 1)).max(4).min(cap)
}
// Round 1: cap/2, Round 2: cap/3, Round 3: cap/4
```

Between rounds, the fetcher waits 90 seconds for the service to recover. Papers that exhaust all rounds are logged as "throttled" and the pipeline moves on.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 4. 并发控制：三种模式

不同的工作负载需要不同的策略来控制同时运行的 task 数量。

### 模式 A：`buffer_unordered(n)` — 固定窗口

当并发级别已知且不变时：

```rust
use futures::StreamExt;

futures::stream::iter(items)
    .map(|item| async move { process(item).await })
    .buffer_unordered(48)   // 最多 48 个并发
    .for_each(|result| async { /* 处理结果 */ })
    .await;
```

ChatPD 中用于 builder 阶段（48 并发）和 LLM caller 阶段（200 并发）。简单，无需运行时调整。

### 模式 B：`Semaphore` — 自适应并发

当希望保守起步、成功后递增时：

```rust
use tokio::sync::Semaphore;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

let initial = 4;
let max = 32;
let sem = Arc::new(Semaphore::new(initial));
let success_ctr = Arc::new(AtomicUsize::new(0));
let cur_permits = Arc::new(AtomicUsize::new(initial));

for item in items {
    let permit = sem.clone().acquire_owned().await.unwrap();

    tokio::spawn(async move {
        if process(item).await.is_ok() {
            let n = success_ctr.fetch_add(1, Ordering::Relaxed) + 1;
            if n % 24 == 0 {  // 每 24 次成功，增加一个槽位
                let cur = cur_permits.load(Ordering::Relaxed);
                if cur < max {
                    cur_permits.fetch_add(1, Ordering::Relaxed);
                    sem.add_permits(1);
                }
            }
        }
        drop(permit);
    });
}
```

ChatPD 的 fetcher 使用这个模式：从 4 个并发 fetch 开始，在足够的成功后逐步增加到 32。这发现外部服务的实际容量，而不是假设配置的上限总是可用的。

信号量只升不降。限流退避由全局闸门单独处理（第三篇会讲）。保持这些关注点分离避免振荡。

### 模式 C：`JoinSet` — 动态任务集合

当事先不知道会有多少 task，或者 task 以不同的速度完成时：

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();

for item in items {
    set.spawn(async move { process(item).await });
}

// 当 task 完成时收集结果
while let Some(result) = set.join_next().await {
    match result {
        Ok(output) => handle(output),
        Err(panic_err) => eprintln!("task panicked: {}", panic_err),
    }
}
```

`JoinSet` 管理 task 生命周期——创建、收集、处理 panic——不需要追踪单个 `JoinHandle`。ChatPD 的 fetch 阶段 round 0 使用它。

### 逐轮递减的重试

ChatPD 的 fetcher 还有一个想法：瞬时错误失败的论文进入重试轮次。每轮使用固定并发，逐轮递减：

```rust
fn fetch_round_concurrency(cap: usize, round: usize) -> usize {
    (cap / (round + 1)).max(4).min(cap)
}
// Round 1: cap/2, Round 2: cap/3, Round 3: cap/4
```

轮次间 fetcher 等待 90 秒让服务恢复。耗尽所有轮次的论文被记录为"throttled"，管道继续前进。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 5. Error Propagation in Concurrent Code

In sequential code, `?` propagates errors up the call stack. In concurrent code, errors happen in separate tasks with separate call stacks. An explicit strategy is needed.

### Strategy 1: Per-Task `Result`

Each task returns a `Result`. The owner (the task that `.await`s the `JoinHandle`) handles it:

```rust
let handle = tokio::spawn(async {
    fallible_work().await?;
    Ok::<_, MyError>(())
});

match handle.await.unwrap() {
    Ok(()) => println!("succeeded"),
    Err(e) => eprintln!("failed: {}", e),
}
```

### Strategy 2: Fatal Errors via `AtomicBool`

When one task detects a condition that should stop everything (API quota exhausted, disk full):

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// Detector
if err_str.contains("quota exhausted") {
    abort_flag.store(true, Ordering::Relaxed);
    return;
}

// Every other task, at each work item boundary:
if abort_flag.load(Ordering::Relaxed) {
    return;
}

// After all tasks join:
if abort_flag.load(Ordering::Relaxed) {
    return Err("pipeline aborted".into());
}
```

### Strategy 3: Error Classification

ChatPD's pipeline distinguishes three error categories at runtime:

```rust
fn is_transient(err: &str) -> bool {
    err.contains("429") || err.contains("403")
        || err.contains("timed out") || err.contains("connection")
}
// → retry with backoff

fn is_fatal(err: &str) -> bool {
    err.contains("401") || err.contains("quota")
}
// → abort pipeline

// Everything else is terminal:
// → write error record, continue with next item
```

### Strategy 4: Task Panic

If a task panics, its `JoinHandle` returns `Err(JoinError)`. `JoinSet` surfaces panics via `join_next().await`:

```rust
while let Some(result) = set.join_next().await {
    if let Err(e) = result {
        eprintln!("task panicked: {}", e);
        // Decision: abort all, or continue?
    }
}
```

Panics in one task don't automatically kill others — but unhandled, they propagate when the parent `.await`s the handle.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 5. 并发代码中的错误传播

在顺序代码中，`?` 沿着调用栈传播错误。在并发代码中，错误发生在拥有独立调用栈的独立 task 中，因此需要明确的策略。

### 策略 1：每个 Task 返回 `Result`

每个 task 返回一个 `Result`。所有者（`.await` 了 `JoinHandle` 的 task）处理它：

```rust
let handle = tokio::spawn(async {
    fallible_work().await?;
    Ok::<_, MyError>(())
});

match handle.await.unwrap() {
    Ok(()) => println!("成功"),
    Err(e) => eprintln!("失败：{}", e),
}
```

### 策略 2：致命错误通过 `AtomicBool` 广播

当一个 task 检测到应该停止一切的条件时（API quota 耗尽、磁盘满）：

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// 检测者
if err_str.contains("quota exhausted") {
    abort_flag.store(true, Ordering::Relaxed);
    return;
}

// 其他所有 task，在每个工作项边界处：
if abort_flag.load(Ordering::Relaxed) {
    return;
}

// 所有 task join 之后：
if abort_flag.load(Ordering::Relaxed) {
    return Err("管道中止".into());
}
```

### 策略 3：错误分类

ChatPD 的管道在运行时区分三类错误：

```rust
fn is_transient(err: &str) -> bool {
    err.contains("429") || err.contains("403")
        || err.contains("timed out") || err.contains("connection")
}
// → 退避重试

fn is_fatal(err: &str) -> bool {
    err.contains("401") || err.contains("quota")
}
// → 中止管道

// 其他都是终端错误：
// → 写错误记录，继续下一项
```

### 策略 4：Task Panic

如果一个 task panic，它的 `JoinHandle` 返回 `Err(JoinError)`。`JoinSet` 通过 `join_next().await` 暴露 panic：

```rust
while let Some(result) = set.join_next().await {
    if let Err(e) = result {
        eprintln!("task panicked: {}", e);
        // 决定：全部中止，还是继续？
    }
}
```

一个 task 的 panic 不会自动杀死其他 task——但如果不处理，当父 task `.await` 了 handle 时，panic 会传播。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 6. A Combined Exercise

Putting together the primitives from this article: a concurrent HTTP fetcher with a rate-limit gate, retry with backoff, and graceful shutdown.

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
            Ok(resp) => return Err(format!("HTTP {}", resp.status())),
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

Extensions worth exploring: add `Semaphore` for adaptive concurrency control, wire the fetcher output into an `mpsc::channel` pipeline, and add an `AtomicBool` abort flag for fatal errors.

---

[Part 3](/tech/rust-concurrency-3-advanced/) walks through five real concurrency bugs from production — what happened, why, the naive fix, and the solution that actually worked.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 6. 综合练习

把这篇文章讲的原语组合起来：一个带限流闸门、退避重试和优雅停机的并发 HTTP 请求器。

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
            Ok(resp) => return Err(format!("HTTP {}", resp.status())),
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

值得探索的扩展：添加 `Semaphore` 做自适应并发控制，把 fetcher 输出接入 `mpsc::channel` 管道，添加 `AtomicBool` abort flag 处理致命错误。

---

[第三篇](/tech/rust-concurrency-3-advanced/) 走查五个来自生产的真实并发 bug——发生了什么、为什么、幼稚的修复、以及实际起作用的方案。

</div>

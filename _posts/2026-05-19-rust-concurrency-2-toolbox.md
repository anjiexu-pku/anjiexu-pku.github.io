---
title: "Rust 并发笔记 (2)：线程、锁、Channel 与并发控制"
date: 2026-05-19
categories:
  - tech
tags:
  - rust
  - concurrency
  - systems-programming
excerpt: "Rust concurrency notes part 2: threads, locks, channels, and concurrency control primitives—Arc, Mutex, RwLock, Condvar, Barrier, and channel selection patterns."
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

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

# Rust 并发笔记 (2)：线程、锁、Channel 与并发控制

[第一篇](/tech/rust-concurrency-1-foundation/) 讲了所有权、`Send`/`Sync`、`Arc` 和 `Result`——并发的基础不在并发本身，而在类型系统。这篇来填充工具箱：线程与异步的区别、三种共享状态原语、channel 做消息传递、以及控制并发的几个模式。每个模式都标注了在 ChatPD 或 asterinas 中的实际使用位置。

---

## 1. 线程与异步

Rust 提供了两套并发模型，生产代码通常是两边都用。问题在于哪种适合什么场景。

### `std::thread`——操作系统线程

```rust
use std::thread;

let handle = thread::spawn(|| {
    // 运行在真实的 OS 线程上。
    // 适合：重计算、C FFI、阻塞系统调用。
    42
});
let result = handle.join().unwrap();
```

在 asterinas 内核里，OS 线程支撑着 `WaitQueue` 和 spinlock 同步。内核里没有 async runtime——线程是唯一选择。

用户空间做 CPU 密集型工作的话，`rayon` 提供了并行迭代器，不需要手动 `spawn`/`join`。

### `tokio::spawn`——异步任务

```rust
let handle = tokio::spawn(async {
    // 运行在 tokio 的 worker 线程上。
    // 适合：HTTP 请求、DB 查询、文件 I/O（tokio::fs）。
    42
});
let result = handle.await.unwrap();  // .await，不是 .join()
```

ChatPD 的 pipeline 里，200 个并发的 LLM API 调用全用的 `tokio::spawn`。为网络 I/O 开 200 个 OS 线程是浪费——每个线程有默认 8MB 的栈和调度开销。async task 是 tokio runtime 管理的轻量状态机。

### 粗略的判断

```
CPU 密集或阻塞？
  → std::thread（或 rayon，或 tokio::task::spawn_blocking）
I/O 密集 + 高并发？
  → tokio::spawn
都行？
  → 在 async 代码库里用 tokio 保持一致性
```

### async 里要调阻塞函数时

`spawn_blocking` 把阻塞工作移出 async runtime 的线程池：

```rust
let data = tokio::task::spawn_blocking(|| {
    std::fs::read_to_string("huge_file.json").unwrap()
}).await.unwrap();
```

不这么做的话，阻塞调用会饿死同一 worker 线程上的其他 task。

---

## 2. 共享状态：`Mutex`、`RwLock`、`Atomic*`

多个 task 需要访问同一数据时，三个原语覆盖大多数情况。关键在于根据访问模式选工具。

### `Mutex<T>`——互斥锁

每次访问（无论读还是写）都以独占方式获取锁。读写差不多频繁、或临界区很短的时候用。

```rust
use std::sync::{Arc, Mutex};

let counter = Arc::new(Mutex::new(0u64));
let mut guard = counter.lock().unwrap();
*guard += 1;
// guard 离开作用域时自动释放
```

异步代码里如果 guard 需要跨越 `.await` 持有，要用 `tokio::sync::Mutex`。同步代码里 `std::sync::Mutex` 更快。

ChatPD 最初用 `Arc<Mutex<Connection>>` 做数据库访问。低并发时没事，管道扩展后成了瓶颈——每个查询都争同一把锁。后来改成单所有者写入器（第三篇会讲）。

### `RwLock<T>`——读写锁

多个读同时持有锁，写者独占。读多写少时比 `Mutex` 好得多。

```rust
use tokio::sync::RwLock;
use std::time::Instant;
use once_cell::sync::Lazy;

// ChatPD 全局限流闸门：
// 每个请求都读（高频），只在收到 429 时写（罕见）。
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

let until = *RATE_LIMITED_UNTIL.read().await;     // 读：共享，普通情况零争用
let mut guard = RATE_LIMITED_UNTIL.write().await; // 写：独占，但很少触发
*guard = Some(Instant::now() + Duration::from_secs(60));
```

选择指南：

| 访问模式 | 用什么 |
|---------|--------|
| 读 ≈ 写 | `Mutex` |
| 读 ≫ 写 | `RwLock` |
| 单个布尔值或整数 | `AtomicBool` / `AtomicUsize` |
| 结构体多个字段 | `Mutex`（简单），或拆成多个 `Atomic*`（性能） |

### `Atomic*`——无锁原语

简单值——布尔、计数器、标志——原子操作完全不需要锁：

```rust
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

// abort flag：一个写入，多个读取
let abort = Arc::new(AtomicBool::new(false));
abort.store(true, Ordering::Relaxed);       // 写
if abort.load(Ordering::Relaxed) { return; } // 读

// 计数器：多个递增，一个收集
let counter = Arc::new(AtomicUsize::new(0));
counter.fetch_add(1, Ordering::Relaxed);
```

值和别的状态没有排序依赖的时候，`Relaxed` 既够用又最快。asterinas 的 `klog.rs` 里有个好例子：`console_level` 用 `AtomicU8` 存，`swap()` 原子地"设新值、返回旧值"，不需要一把完整的锁。

---

## 3. 消息传递：Channel

有时候不共享比共享更简单。Channel 让 task 之间通过发送值来通信——每个 task 拥有自己的数据，所有权通过 channel 转移。

### `mpsc::channel`——多生产者，单消费者

这是主力。多个 sender，一个 receiver。ChatPD 的四级管道就靠它连接：

```rust
use tokio::sync::mpsc;

let (tx, mut rx) = mpsc::channel::<WorkItem>(200);  // 200 项缓冲

// 生产者（把 tx clone 给每个 task）
let tx1 = tx.clone();
tokio::spawn(async move { tx1.send(item).await.unwrap(); });

// 关键：drop 原始 tx，否则 receiver 永远不会退出
drop(tx);

// 消费者
while let Some(item) = rx.recv().await {
    process(item).await;
}
// 所有 sender 都 drop 之后，循环自动退出
```

三个特性让它很适合管道：
1. **没有锁。** 消费者独占接收到的数据。
2. **背压。** 缓冲区满了，`send().await` 阻塞生产者——自然流控。
3. **自然关机。** drop 所有 sender，receiver 自动退出。不需要额外的关机信号。

### ChatPD 四级管道

```
[Fetcher]  ──ch₁──→  [Builder]  ──ch₂──→  [LLM Caller]  ──ch₃──→  [DB Writer]
```

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

let fetcher  = tokio::spawn(run_fetcher(input, paper_tx, write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(paper_rx, req_tx, write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(req_rx, write_tx.clone(), ...));
drop(write_tx);  // 上游不会再有新数据
let db_writer = tokio::spawn(run_db_writer(write_rx, ...));
```

每个阶段独立运行，各配各的并发度。channel 既传数据也做流控——下游慢了，上游自然在 `send()` 上阻塞。

### 其他 channel 类型

`oneshot::channel()`——单值、一次性。像一个只 resolve 一次的 `Future`。适合"做这个然后告诉我结果"。

`broadcast::channel()`——一个 sender，多个 receiver。每个 receiver 都收到每一条值的拷贝。适合多个 task 都需要观察的事件。

---

## 4. 并发控制：三种模式

不同场景需要不同的并发控制策略。

### 模式 A：`buffer_unordered(n)`——固定窗口

并发量已知且不变时最简单：

```rust
use futures::StreamExt;

futures::stream::iter(items)
    .map(|item| async move { process(item).await })
    .buffer_unordered(48)   // 最多 48 个同时跑
    .for_each(|result| async { /* 处理结果 */ })
    .await;
```

ChatPD 的 builder 阶段（48 并发）和 LLM caller 阶段（200 并发）都用这个。简单，不用运行时调整。

### 模式 B：`Semaphore`——自适应并发

保守起步、成功后递增更适合面对外部服务容量不确定的情况：

```rust
use tokio::sync::Semaphore;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

let sem = Arc::new(Semaphore::new(4));   // 从 4 开始
let max = 32;
let cur = Arc::new(AtomicUsize::new(4));
let success = Arc::new(AtomicUsize::new(0));

for item in items {
    let permit = sem.clone().acquire_owned().await.unwrap();
    tokio::spawn(async move {
        if process(item).await.is_ok() {
            let n = success.fetch_add(1, Ordering::Relaxed) + 1;
            if n % 24 == 0 {  // 每 24 次成功，多开一个槽
                let c = cur.load(Ordering::Relaxed);
                if c < max {
                    cur.fetch_add(1, Ordering::Relaxed);
                    sem.add_permits(1);
                }
            }
        }
        drop(permit);
    });
}
```

ChatPD 的 fetcher 用这个模式：从 4 并发开始，成功够多后逐步爬到 32。这是"发现"外部服务的实际容量，而不是假设配置的上限总是可用。

Semaphore 只升不降。限流退避由一个全局闸门单独处理（第三篇讲）。两个机制各司其职，避免振荡。

### 模式 C：`JoinSet`——动态任务集合

不知道会创建多少 task、或者 task 以不同速度完成时：

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();
for item in items {
    set.spawn(async move { process(item).await });
}
while let Some(result) = set.join_next().await {
    match result {
        Ok(output) => handle(output),
        Err(e) => eprintln!("task panic: {}", e),
    }
}
```

`JoinSet` 管理 task 的生命周期——创建、收集、处理 panic——不需要一个个追踪 `JoinHandle`。

### 重试轮次逐轮递减

ChatPD 的 fetcher 还做了一件事：瞬时错误（429、timeout）的论文放进重试池，但每轮并发量递减：

```rust
fn round_concurrency(cap: usize, round: usize) -> usize {
    (cap / (round + 1)).max(4).min(cap)
}
// Round 1: cap/2, Round 2: cap/3, Round 3: cap/4
```

轮次之间等 90 秒让服务恢复。三轮后还拿不到的论文标记为 throttled，管道继续往前走。

---

## 5. 并发里的错误传播

顺序代码里 `?` 沿着调用栈传错误。并发代码里每个 task 有自己的调用栈，需要明确的策略。

### 策略 1：每个 task 返回 `Result`

```rust
let handle = tokio::spawn(async {
    fallible_work().await?;
    Ok::<_, MyError>(())
});
match handle.await.unwrap() {
    Ok(()) => println!("成功"),
    Err(e) => eprintln!("失败: {}", e),
}
```

### 策略 2：致命错误用 `AtomicBool` 广播

```rust
let abort = Arc::new(AtomicBool::new(false));

// 检测到致命错误：
abort.store(true, Ordering::Relaxed);

// 其他 task 每个工作项开始前检查：
if abort.load(Ordering::Relaxed) { return; }

// 所有 task 结束后：
if abort.load(Ordering::Relaxed) {
    return Err("管道中止".into());
}
```

### 策略 3：运行时分三类

ChatPD 在运行时把错误分成三类：

```rust
fn is_transient(e: &str) -> bool {
    e.contains("429") || e.contains("403")
        || e.contains("timed out") || e.contains("connection")
}
fn is_fatal(e: &str) -> bool {
    e.contains("401") || e.contains("quota")
}
// 其余是 terminal：写错误记录，继续下一项
```

### 策略 4：task panic

一个 task panic 了不会自动杀死其他 task——但当有人 `.await` 它的 `JoinHandle` 时，panic 会传播。`JoinSet` 里通过 `join_next().await` 的 `Err` 暴露。

---

## 6. 综合练习

把这些组合起来：一个带全局限流闸门、退避重试的并发 HTTP 请求器。

```rust
struct RateLimitGate {
    until: RwLock<Option<Instant>>,
}

impl RateLimitGate {
    fn new() -> Self { Self { until: RwLock::new(None) } }

    async fn set_cooldown(&self, secs: u64) {
        let deadline = Instant::now() + Duration::from_secs(secs);
        let mut g = self.until.write().await;
        if g.map_or(true, |t| t < deadline) { *g = Some(deadline); }
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
    client: &reqwest::Client, url: &str,
    gate: &Arc<RateLimitGate>, max_retries: u32,
) -> Result<String, String> {
    for retry in 0..max_retries {
        gate.wait_if_needed().await;
        match client.get(url).send().await {
            Ok(r) if r.status().is_success() => return r.text().await.map_err(|e| e.to_string()),
            Ok(r) if r.status().as_u16() == 429 => {
                gate.set_cooldown(60).await;
                let ms = 500 * 2u64.pow(retry);
                tokio::time::sleep(Duration::from_millis(ms)).await;
            }
            Ok(r) => return Err(format!("HTTP {}", r.status())),
            Err(e) if e.is_timeout() => {
                tokio::time::sleep(Duration::from_millis(500 * 2u64.pow(retry))).await;
            }
            Err(e) => return Err(e.to_string()),
        }
    }
    Err("超过最大重试次数".to_string())
}
```

值得继续探索的扩展：加上 `Semaphore` 做自适应并发、把 fetcher 输出接入 `mpsc::channel` 管道、加上 `AtomicBool` abort flag。

---

[第三篇](/tech/rust-concurrency-3-advanced/) 走查五个来自 ChatPD 生产的真实并发 bug——429 级联风暴、冷启动并发、DB 锁争用、致命错误广播、优雅停机——以及最终起作用的方案。

*代码示例从 [ChatPD](https://github.com/anjiexu-pku)、[asterinas](https://github.com/asterinas/asterinas) 和 [mcpr](https://github.com/TankTechnology) 的生产 Rust 代码简化而来。*

</div>

<div id="lang-en" class="lang-content" markdown="1">

# Rust Concurrency Notes (2): Threads, Locks, Channels, and Concurrency Control

[Part 1](/tech/rust-concurrency-1-foundation/) covered ownership, `Send`/`Sync`, `Arc`, and `Result`: the foundation of concurrency is not concurrency itself, but the type system. This post fills in the toolbox: the difference between threads and async tasks, three primitives for shared state, channels for message passing, and several patterns for controlling concurrency. Each pattern is tied back to where it appears in ChatPD or asterinas.

---

## 1. Threads and Async

Rust gives you two concurrency models. Production code often uses both. The real question is which one fits which situation.

### `std::thread`: OS Threads

```rust
use std::thread;

let handle = thread::spawn(|| {
    // Runs on a real OS thread.
    // Good for CPU-heavy work, C FFI, and blocking syscalls.
    42
});
let result = handle.join().unwrap();
```

In the asterinas kernel, OS threads underpin `WaitQueue` and spinlock synchronization. There is no async runtime inside the kernel; threads are the only option.

For CPU-heavy work in userspace, `rayon` provides parallel iterators so you do not have to manually `spawn` and `join`.

### `tokio::spawn`: Async Tasks

```rust
let handle = tokio::spawn(async {
    // Runs on tokio's worker threads.
    // Good for HTTP requests, DB queries, and file I/O via tokio::fs.
    42
});
let result = handle.await.unwrap();  // .await, not .join()
```

In ChatPD's pipeline, 200 concurrent LLM API calls are all handled with `tokio::spawn`. Opening 200 OS threads for network I/O would be wasteful: each thread has a default stack, often around 8MB, plus scheduler overhead. An async task is a lightweight state machine managed by the tokio runtime.

### A Rough Decision Rule

```
CPU-heavy or blocking?
  -> std::thread, rayon, or tokio::task::spawn_blocking
I/O-heavy with high concurrency?
  -> tokio::spawn
Either would work?
  -> in an async codebase, use tokio for consistency
```

### Calling Blocking Functions from Async Code

`spawn_blocking` moves blocking work out of the async runtime's worker pool:

```rust
let data = tokio::task::spawn_blocking(|| {
    std::fs::read_to_string("huge_file.json").unwrap()
}).await.unwrap();
```

Without this, a blocking call can starve other tasks on the same worker thread.

---

## 2. Shared State: `Mutex`, `RwLock`, and `Atomic*`

When multiple tasks need access to the same data, these three primitives cover most cases. The key is to choose based on the access pattern.

### `Mutex<T>`: Mutual Exclusion

Every access, whether read or write, acquires the lock exclusively. Use it when reads and writes are similarly frequent, or when the critical section is short.

```rust
use std::sync::{Arc, Mutex};

let counter = Arc::new(Mutex::new(0u64));
let mut guard = counter.lock().unwrap();
*guard += 1;
// the guard releases the lock when it leaves scope
```

In async code, if the guard must be held across `.await`, use `tokio::sync::Mutex`. In synchronous code, `std::sync::Mutex` is faster.

ChatPD initially used `Arc<Mutex<Connection>>` for database access. It was fine at low concurrency, but became a bottleneck as the pipeline scaled: every query fought for the same lock. We later replaced it with a single-owner writer, which Part 3 explains.

### `RwLock<T>`: Read-Write Lock

Many readers can hold the lock at the same time, while writers require exclusive access. It works much better than `Mutex` when reads greatly outnumber writes.

```rust
use tokio::sync::RwLock;
use std::time::Instant;
use once_cell::sync::Lazy;

// ChatPD global rate-limit gate:
// every request reads it; only 429 responses write it.
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

let until = *RATE_LIMITED_UNTIL.read().await;     // read: shared, usually no contention
let mut guard = RATE_LIMITED_UNTIL.write().await; // write: exclusive, but rare
*guard = Some(Instant::now() + Duration::from_secs(60));
```

Selection guide:

| Access pattern | Use |
|----------------|-----|
| Reads roughly equal writes | `Mutex` |
| Reads much more frequent than writes | `RwLock` |
| Single boolean or integer | `AtomicBool` / `AtomicUsize` |
| Struct with multiple fields | `Mutex` for simplicity, or split into `Atomic*` for performance |

### `Atomic*`: Lock-Free Primitives

For simple values such as booleans, counters, and flags, atomic operations need no lock at all:

```rust
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

// abort flag: one writer, many readers
let abort = Arc::new(AtomicBool::new(false));
abort.store(true, Ordering::Relaxed);        // write
if abort.load(Ordering::Relaxed) { return; } // read

// counter: many increments, one collector
let counter = Arc::new(AtomicUsize::new(0));
counter.fetch_add(1, Ordering::Relaxed);
```

When the value has no ordering dependency with other state, `Relaxed` is both sufficient and fastest. asterinas has a good example in `klog.rs`: `console_level` is stored in an `AtomicU8`, and `swap()` atomically "sets the new value and returns the old one" without a full lock.

---

## 3. Message Passing: Channels

Sometimes not sharing is simpler than sharing. Channels let tasks communicate by sending values. Each task owns its own data, and ownership moves through the channel.

### `mpsc::channel`: Multiple Producers, Single Consumer

This is the workhorse: many senders, one receiver. ChatPD's four-stage pipeline is connected by `mpsc` channels:

```rust
use tokio::sync::mpsc;

let (tx, mut rx) = mpsc::channel::<WorkItem>(200);  // buffer of 200 items

// Producer: clone tx for each task
let tx1 = tx.clone();
tokio::spawn(async move { tx1.send(item).await.unwrap(); });

// Important: drop the original tx, or the receiver will never exit.
drop(tx);

// Consumer
while let Some(item) = rx.recv().await {
    process(item).await;
}
// After every sender is dropped, the loop exits automatically.
```

Three properties make this ideal for pipelines:

1. **No locks.** The consumer exclusively owns the data it receives.
2. **Backpressure.** If the buffer is full, `send().await` blocks the producer, giving natural flow control.
3. **Natural shutdown.** Drop all senders and the receiver exits automatically. No extra shutdown signal is needed.

### ChatPD's Four-Stage Pipeline

```
[Fetcher]  --ch1-->  [Builder]  --ch2-->  [LLM Caller]  --ch3-->  [DB Writer]
```

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

let fetcher  = tokio::spawn(run_fetcher(input, paper_tx, write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(paper_rx, req_tx, write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(req_rx, write_tx.clone(), ...));
drop(write_tx);  // no new data can be sent by the main owner
let db_writer = tokio::spawn(run_db_writer(write_rx, ...));
```

Each stage runs independently and has its own concurrency level. The channels carry both data and flow control. If downstream slows down, upstream naturally blocks on `send()`.

### Other Channel Types

`oneshot::channel()` is single-value and one-time. Think of it as a `Future` that resolves once. It fits "do this, then tell me the result."

`broadcast::channel()` has one sender and many receivers. Each receiver gets a copy of every value. It fits events that many tasks need to observe.

---

## 4. Concurrency Control: Three Patterns

Different scenarios need different concurrency-control strategies.

### Pattern A: `buffer_unordered(n)` for a Fixed Window

This is the simplest option when the concurrency level is known and fixed:

```rust
use futures::StreamExt;

futures::stream::iter(items)
    .map(|item| async move { process(item).await })
    .buffer_unordered(48)   // at most 48 running at once
    .for_each(|result| async { /* handle result */ })
    .await;
```

ChatPD uses this in the builder stage, at 48-way concurrency, and in the LLM caller stage, at 200-way concurrency. It is simple and does not require runtime adjustment.

### Pattern B: `Semaphore` for Adaptive Concurrency

When an external service's capacity is uncertain, it is better to start conservatively and increase after successful calls:

```rust
use tokio::sync::Semaphore;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

let sem = Arc::new(Semaphore::new(4));   // start at 4
let max = 32;
let cur = Arc::new(AtomicUsize::new(4));
let success = Arc::new(AtomicUsize::new(0));

for item in items {
    let permit = sem.clone().acquire_owned().await.unwrap();
    tokio::spawn(async move {
        if process(item).await.is_ok() {
            let n = success.fetch_add(1, Ordering::Relaxed) + 1;
            if n % 24 == 0 {  // every 24 successes, open one more slot
                let c = cur.load(Ordering::Relaxed);
                if c < max {
                    cur.fetch_add(1, Ordering::Relaxed);
                    sem.add_permits(1);
                }
            }
        }
        drop(permit);
    });
}
```

ChatPD's fetcher uses this pattern: start at 4-way concurrency, then gradually climb to 32 after enough successes. This *discovers* the external service's real capacity instead of assuming the configured maximum is always safe.

The semaphore only increases; it does not decrease. Rate-limit backoff is handled separately by a global gate, discussed in Part 3. The two mechanisms have separate responsibilities, which avoids oscillation.

### Pattern C: `JoinSet` for Dynamic Task Sets

Use this when you do not know how many tasks will be created, or when they finish at different speeds:

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();
for item in items {
    set.spawn(async move { process(item).await });
}
while let Some(result) = set.join_next().await {
    match result {
        Ok(output) => handle(output),
        Err(e) => eprintln!("task panic: {}", e),
    }
}
```

`JoinSet` manages task lifecycles: creation, result collection, and panic handling. You do not need to track every `JoinHandle` manually.

### Retry Rounds with Decreasing Concurrency

ChatPD's fetcher also does one more thing: papers that fail with transient errors, such as 429 or timeout, go into a retry pool, but each retry round uses lower concurrency:

```rust
fn round_concurrency(cap: usize, round: usize) -> usize {
    (cap / (round + 1)).max(4).min(cap)
}
// Round 1: cap/2, Round 2: cap/3, Round 3: cap/4
```

Between rounds, the system waits 90 seconds for the service to recover. After three rounds, papers that still cannot be fetched are marked as throttled and the pipeline continues.

---

## 5. Error Propagation in Concurrent Code

In sequential code, `?` propagates errors up the call stack. In concurrent code, each task has its own call stack, so you need an explicit strategy.

### Strategy 1: Each Task Returns `Result`

```rust
let handle = tokio::spawn(async {
    fallible_work().await?;
    Ok::<_, MyError>(())
});
match handle.await.unwrap() {
    Ok(()) => println!("success"),
    Err(e) => eprintln!("failed: {}", e),
}
```

### Strategy 2: Broadcast Fatal Errors with `AtomicBool`

```rust
let abort = Arc::new(AtomicBool::new(false));

// After detecting a fatal error:
abort.store(true, Ordering::Relaxed);

// Other tasks check before starting each item:
if abort.load(Ordering::Relaxed) { return; }

// After all tasks finish:
if abort.load(Ordering::Relaxed) {
    return Err("pipeline aborted".into());
}
```

### Strategy 3: Classify Errors at Runtime

ChatPD classifies errors into three categories at runtime:

```rust
fn is_transient(e: &str) -> bool {
    e.contains("429") || e.contains("403")
        || e.contains("timed out") || e.contains("connection")
}
fn is_fatal(e: &str) -> bool {
    e.contains("401") || e.contains("quota")
}
// Everything else is terminal: write an error record and continue.
```

### Strategy 4: Task Panic

If one task panics, it does not automatically kill other tasks. The panic is exposed when someone `.await`s its `JoinHandle`. In a `JoinSet`, it appears as the `Err` returned by `join_next().await`.

---

## 6. Combined Exercise

Put these pieces together: a concurrent HTTP fetcher with a global rate-limit gate and backoff retry.

```rust
struct RateLimitGate {
    until: RwLock<Option<Instant>>,
}

impl RateLimitGate {
    fn new() -> Self { Self { until: RwLock::new(None) } }

    async fn set_cooldown(&self, secs: u64) {
        let deadline = Instant::now() + Duration::from_secs(secs);
        let mut g = self.until.write().await;
        if g.map_or(true, |t| t < deadline) { *g = Some(deadline); }
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
    client: &reqwest::Client, url: &str,
    gate: &Arc<RateLimitGate>, max_retries: u32,
) -> Result<String, String> {
    for retry in 0..max_retries {
        gate.wait_if_needed().await;
        match client.get(url).send().await {
            Ok(r) if r.status().is_success() => return r.text().await.map_err(|e| e.to_string()),
            Ok(r) if r.status().as_u16() == 429 => {
                gate.set_cooldown(60).await;
                let ms = 500 * 2u64.pow(retry);
                tokio::time::sleep(Duration::from_millis(ms)).await;
            }
            Ok(r) => return Err(format!("HTTP {}", r.status())),
            Err(e) if e.is_timeout() => {
                tokio::time::sleep(Duration::from_millis(500 * 2u64.pow(retry))).await;
            }
            Err(e) => return Err(e.to_string()),
        }
    }
    Err("exceeded max retries".to_string())
}
```

Useful extensions to explore next: add a `Semaphore` for adaptive concurrency, pipe fetcher output into an `mpsc::channel`, and add an `AtomicBool` abort flag.

---

[Part 3](/tech/rust-concurrency-3-advanced/) walks through five real concurrency bugs from ChatPD production: 429 cascade storms, cold-start concurrency, DB lock contention, fatal-error broadcast, and graceful shutdown, along with the fixes that actually worked.

*Code examples are simplified from production Rust code in [ChatPD](https://github.com/anjiexu-pku), [asterinas](https://github.com/asterinas/asterinas), and [mcpr](https://github.com/TankTechnology).*

</div>

<script>
function switchLang(lang) {
  document.getElementById('lang-zh').style.display = lang === 'zh' ? '' : 'none';
  document.getElementById('lang-en').style.display = lang === 'en' ? '' : 'none';
  const links = document.querySelectorAll('.lang-switch a');
  links.forEach(a => a.classList.remove('active'));
  document.querySelector('.lang-switch a[href="#' + lang + '"]').classList.add('active');
  history.replaceState(null, '', '#' + lang);
}
if (location.hash === '#zh') {
  switchLang('zh');
}
</script>

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
  <a class="active" href="#zh">中文</a>|
  <a href="#en">English (TODO)</a>
</div>

<div id="lang-zh" class="lang-content" markdown="1">

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
use std::sync::RwLock;
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

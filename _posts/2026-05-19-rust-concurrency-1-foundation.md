---
title: "Rust Concurrency from Zero to Production (1): Ownership, Types, and Errors"
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

This is the first of three articles on Rust concurrency, written while building a production data pipeline that processes hundreds of thousands of arXiv papers through LLMs. I made plenty of mistakes along the way — these notes are what I wish I had understood earlier.

Rust's concurrency story builds on four foundations that don't look like concurrency at all: ownership, `Send`/`Sync`, `Arc`, and `Result`. This article walks through each one.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

这是三篇 Rust 并发文章的第一篇。它们是在构建一个用 LLM 处理数十万篇 arXiv 论文的生产级数据管道过程中写下的笔记。我在这个过程中犯了不少错，回过头看，有些基础概念如果早点想清楚，会少走很多弯路。

Rust 的并发模型建立在四个看起来不像并发的基础概念上：所有权、`Send`/`Sync`、`Arc` 和 `Result`。这篇文章逐一梳理它们。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 1. Ownership and Borrowing

Rust eliminates data races at compile time. This isn't a runtime check or a language feature bolted onto the type system — it's a direct consequence of how ownership works. Three rules govern everything.

### The Three Rules

```rust
// Rule 1: Each value has exactly one owner at a time.
let s1 = String::from("hello");
let s2 = s1;           // s1 is MOVED — s1 can't be used anymore
// println!("{}", s1); // ❌ compile error: value borrowed after move

// Rule 2: Either one mutable reference, or many immutable references.
let mut v = vec![1, 2, 3];
let r1 = &v;           // shared reference
let r2 = &v;           // fine: multiple shared references
// let r3 = &mut v;    // ❌ can't have &mut while & exists
println!("{:?} {:?}", r1, r2);

// Rule 3: References must always be valid.
fn dangle() -> &String {
    let s = String::from("hello");
    &s  // ❌ s is dropped at end of scope
}
```

### Why This Matters for Concurrency

In most languages, a data race happens when two threads access the same data and at least one writes — and the language doesn't stop it. Rust catches this at compile time via the borrow checker:

```rust
use std::thread;

let mut data = vec![1, 2, 3];

thread::spawn(move || {
    data.push(4);  // data is MOVED into this thread
});

// println!("{:?}", data);  // ❌ data was moved — no access here
```

The `move` keyword transfers ownership into the closure. After that, the original thread has no access. **No shared mutable state = no data race.** This guarantee holds at compile time, not at runtime.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 1. 所有权与借用

Rust 在编译时消灭 data race。这不是运行时检查，也不是拼接到类型系统上的附加功能——它是所有权机制的直接产物。三条规则支配一切。

### 三条规则

```rust
// 规则1：每个值在任何时候只有一个所有者。
let s1 = String::from("hello");
let s2 = s1;           // s1 被 MOVED（转移）了 — 不能再使用 s1
// println!("{}", s1); // ❌ 编译错误：值已被移动

// 规则2：要么一个可变引用，要么多个不可变引用。
let mut v = vec![1, 2, 3];
let r1 = &v;           // 共享引用
let r2 = &v;           // 没问题：可以有多个共享引用
// let r3 = &mut v;    // ❌ 已经有 & 引用在使用，不能再有 &mut
println!("{:?} {:?}", r1, r2);

// 规则3：引用必须始终有效。
fn dangle() -> &String {
    let s = String::from("hello");
    &s  // ❌ s 在作用域结束时被释放
}
```

### 与并发的关系

在大多数语言中，data race 发生在两个线程同时访问同一数据且至少有一个在写入时——语言本身不会阻止。Rust 的 borrow checker 在编译时就抓住了这个问题：

```rust
use std::thread;

let mut data = vec![1, 2, 3];

thread::spawn(move || {
    data.push(4);  // data 被 MOVE 进入这个线程
});

// println!("{:?}", data);  // ❌ data 已被移动 — 这里无法访问
```

`move` 关键字将所有权转移给闭包。之后，原线程就没有访问权了。**没有共享的可变状态 = 没有 data race。** 这个保证在编译时成立，而非运行时。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 2. `Send` and `Sync`

`Send` and `Sync` are marker traits — the compiler derives them automatically for most types. They answer two questions: "can this value be moved to another thread?" and "can a reference to this be shared across threads?"

### `Send`: Transfer Ownership Across Threads

A type is `Send` if moving its value to another thread is safe. Most types are:

```rust
fn is_send<T: Send>() {}

is_send::<i32>();         // ✅
is_send::<String>();       // ✅
is_send::<Vec<String>>();  // ✅
is_send::<Mutex<i32>>();  // ✅
```

`Rc<T>` is the classic counterexample — it's not `Send` because its reference count uses non-atomic operations:

```rust
use std::rc::Rc;
// is_send::<Rc<i32>>();    // ❌ Rc is NOT Send
```

`Arc<T>` is the `Send` version. The "A" stands for *atomic*:

```rust
use std::sync::Arc;
// is_send::<Arc<i32>>();     // ✅ Arc IS Send (when T is Send + Sync)
```

### `Sync`: Share References Across Threads

A type is `Sync` if sharing a reference (`&T`) across threads is safe:

```rust
fn is_sync<T: Sync>() {}

is_sync::<i32>();         // ✅
is_sync::<Mutex<i32>>();  // ✅ Mutex provides interior mutability safely
// is_sync::<Rc<i32>>();  // ❌ Rc is neither Send nor Sync
```

### When `tokio::spawn` Complains

The most common `Send`-related compile error looks like:

```
error[E0277]: `Rc<i32>` cannot be sent between threads safely
```

The usual suspects:
1. `Rc<T>` where `Arc<T>` is needed
2. `RefCell<T>` where `Mutex<T>` or `RwLock<T>` is needed
3. A raw pointer buried inside a struct
4. A non-`Send` type pulled in through a dependency

The fix is mechanical once the right type is identified.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 2. `Send` 和 `Sync`

`Send` 和 `Sync` 是 marker trait——编译器对大多数类型自动推导它们。它们回答两个问题："这个值能移动到另一个线程吗？"和"这个值的引用能跨线程共享吗？"

### `Send`：跨线程转移所有权

如果一个类型的值可以安全地 move 到另一个线程，它就是 `Send`。大多数类型都是：

```rust
fn is_send<T: Send>() {}

is_send::<i32>();         // ✅
is_send::<String>();       // ✅
is_send::<Vec<String>>();  // ✅
is_send::<Mutex<i32>>();  // ✅
```

经典反例是 `Rc<T>`——它的引用计数使用非原子操作：

```rust
use std::rc::Rc;
// is_send::<Rc<i32>>();    // ❌ Rc 不是 Send
```

`Arc<T>` 是 `Rc<T>` 的 `Send` 版本。"A" 代表 *atomic*（原子）：

```rust
use std::sync::Arc;
// is_send::<Arc<i32>>();     // ✅ Arc 是 Send（前提是 T 是 Send + Sync）
```

### `Sync`：跨线程共享引用

如果一个类型的引用（`&T`）可以安全地跨线程共享，它就是 `Sync`：

```rust
fn is_sync<T: Sync>() {}

is_sync::<i32>();         // ✅
is_sync::<Mutex<i32>>();  // ✅ Mutex 安全地提供了内部可变性
// is_sync::<Rc<i32>>();  // ❌ Rc 既不是 Send 也不是 Sync
```

### 当 `tokio::spawn` 编译不通过时

最常见的 `Send` 相关编译错误：

```
error[E0277]: `Rc<i32>` cannot be sent between threads safely
```

常见原因：
1. `Rc<T>`——改成 `Arc<T>`
2. `RefCell<T>`——改成 `Mutex<T>` 或 `RwLock<T>`
3. 结构体深处嵌入了一个裸指针
4. 依赖库中引入了一个非 `Send` 的类型

确定了问题类型后，修复通常是机械性的。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 3. `Arc<T>` — Shared Ownership

`Arc<T>` shows up everywhere in concurrent Rust. In our ChatPD pipeline, it carries configs, shared counters, abort flags, and semaphores across dozens of async tasks.

### `Arc::clone` Is a Refcount Bump

```rust
use std::sync::Arc;

let config = Arc::new(vec![1, 2, 3]);  // allocate once
let handle1 = Arc::clone(&config);       // atomic refcount increment
let handle2 = Arc::clone(&config);       // same — no data copy

// Three Arcs, one heap allocation.
```

The clone is cheap (one atomic increment), but not free — atomic operations cost CPU cycles due to cache-line bouncing between cores. For hot-loop counters, `AtomicUsize` directly is cheaper.

### `Arc<RwLock<T>>`

Most shared mutable state in async Rust uses this combination. Here's a real example from ChatPD:

```rust
use std::sync::RwLock;
use std::time::Instant;

// Global rate-limit gate. Read by every request (high frequency),
// written only on 429/403 (rare).
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// Read path: cheap shared access
let until = *RATE_LIMITED_UNTIL.read().await;

// Write path: exclusive, rare
let mut guard = RATE_LIMITED_UNTIL.write().await;
*guard = Some(Instant::now() + Duration::from_secs(60));
```

`RwLock` over `Mutex` here because reads vastly outnumber writes. The choice of lock type matters — it's worth thinking about access patterns rather than defaulting to `Mutex`.

### When `Arc` Isn't Needed

In the pipeline's DB writer, the connection is used by exactly one task:

```rust
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    // conn is used directly — no Arc, no Mutex, no contention
    while let Some(record) = rx.recv().await { ... }
}
```

Single-owner values don't need `Arc`. Passing ownership through a channel or a function argument is simpler and faster.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 3. `Arc<T>` — 共享所有权

`Arc<T>` 在并发 Rust 代码中无处不在。在我们的 ChatPD 管道中，它承载着配置、共享计数器、中止标志和信号量，跨数十个异步任务传递。

### `Arc::clone` 只是引用计数加一

```rust
use std::sync::Arc;

let config = Arc::new(vec![1, 2, 3]);  // 只分配一次
let handle1 = Arc::clone(&config);       // 原子的引用计数递增
let handle2 = Arc::clone(&config);       // 同上 — 没有数据拷贝

// 三个 Arc，一个堆分配。
```

clone 很便宜（一次原子递增），但不是免费的——原子操作会因核间的缓存行弹跳消耗 CPU 周期。在热循环中的计数器，直接用 `AtomicUsize` 更经济。

### `Arc<RwLock<T>>`

异步 Rust 中大多数共享可变状态使用这个组合。来自 ChatPD 的真实例子：

```rust
use std::sync::RwLock;
use std::time::Instant;

// 全局限流闸门。每个请求都读（高频），
// 仅在收到 429/403 时写（罕见）。
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// 读路径：廉价的共享访问
let until = *RATE_LIMITED_UNTIL.read().await;

// 写路径：独占，罕见
let mut guard = RATE_LIMITED_UNTIL.write().await;
*guard = Some(Instant::now() + Duration::from_secs(60));
```

这里用 `RwLock` 而非 `Mutex`，因为读操作远超写操作。锁类型的选择值得根据访问模式来考虑，而不是习惯性地用 `Mutex`。

### `Arc` 并不总是需要的

在管道的 DB 写入器中，连接只被一个任务使用：

```rust
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    // conn 直接使用 — 没有 Arc，没有 Mutex，没有争用
    while let Some(record) = rx.recv().await { ... }
}
```

单所有者的值不需要 `Arc`。通过 channel 或函数参数传递所有权更简单、更快。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 4. `Result<T, E>` — Errors Don't Vanish

In concurrent code, error handling matters more, not less. A panicking task kills the whole process. A swallowed error corrupts data silently. Rust's `Result` forces errors to be explicit, and the `?` operator makes propagation concise.

### The Basic Pattern

```rust
use std::fs;
use std::io;

fn read_config(path: &str) -> Result<String, io::Error> {
    let contents = fs::read_to_string(path)?;  // return Err on failure
    Ok(contents)
}

fn main() {
    match read_config("config.json") {
        Ok(cfg) => println!("config loaded: {}", cfg),
        Err(e) => eprintln!("failed to load config: {}", e),
    }
}
```

### Errors in Concurrent Contexts

When multiple tasks are running, a single task's failure needs a propagation strategy. In ChatPD, when the LLM API quota is exhausted, we use an `AtomicBool` to broadcast the fatal error:

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// In each LLM worker:
if err_str.contains("401") || err_str.contains("quota") {
    eprintln!("FATAL: API quota exhausted. Aborting pipeline.");
    abort_flag.store(true, Ordering::Relaxed);
    return;
}

// In other workers, at the start of each work item:
if abort_flag.load(Ordering::Relaxed) {
    return;  // stop without producing error records
}
```

Three categories of errors emerged from this work:

| Category | Examples | Response |
|----------|----------|----------|
| Transient | 429, timeout, connection reset | Retry with backoff |
| Terminal | 404, parse failure | Write error record, continue |
| Fatal | 401, quota exceeded | Set abort flag, all tasks stop |

### `anyhow` vs `thiserror`

For application code, `anyhow::Result<T>` wraps any error type and provides context. For library code, `thiserror` gives callers the ability to match on specific error variants. Both have their place — the distinction is whether callers need to distinguish error kinds programmatically.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 4. `Result<T, E>` — 错误不会消失

在并发代码中，错误处理更重要，而不是更次要。一个 panic 的 task 会终止整个进程。一个被静默吞掉的错误会默默污染数据。Rust 的 `Result` 强制错误显式化，`?` 操作符让传播变得简洁。

### 基本模式

```rust
use std::fs;
use std::io;

fn read_config(path: &str) -> Result<String, io::Error> {
    let contents = fs::read_to_string(path)?;  // 失败时返回 Err
    Ok(contents)
}

fn main() {
    match read_config("config.json") {
        Ok(cfg) => println!("配置已加载：{}", cfg),
        Err(e) => eprintln!("加载配置失败：{}", e),
    }
}
```

### 并发上下文中的错误

当多个 task 同时运行时，单个 task 的失败需要传播策略。在 ChatPD 中，当 LLM API quota 耗尽时，我们用 `AtomicBool` 广播致命错误：

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// 在每个 LLM worker 中：
if err_str.contains("401") || err_str.contains("quota") {
    eprintln!("致命：API quota 耗尽。中止管道。");
    abort_flag.store(true, Ordering::Relaxed);
    return;
}

// 在其他 worker 中，每个工作项开始时：
if abort_flag.load(Ordering::Relaxed) {
    return;  // 停止，不产生错误记录
}
```

从这个实践中，错误自然地分为三类：

| 类别 | 示例 | 响应 |
|------|------|------|
| 瞬时 | 429、timeout、连接重置 | 退避重试 |
| 终端 | 404、解析失败 | 写错误记录，继续 |
| 致命 | 401、quota 超出 | 设置 abort flag，所有 task 停止 |

### `anyhow` vs `thiserror`

应用代码用 `anyhow::Result<T>`，它包装任何错误类型并提供上下文。库代码用 `thiserror`，让调用方能以编程方式匹配特定错误变体。两者各有用处——区别在于调用方是否需要区分错误类型。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 5. A Small Exercise

Putting these four concepts together: spawn threads, share state with `Arc<Mutex<T>>`, handle errors with `Result`.

```rust
use std::sync::{Arc, Mutex};
use std::thread;

struct SharedCounter {
    count: Mutex<u64>,
    name: String,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let counter = Arc::new(SharedCounter {
        count: Mutex::new(0),
        name: "requests".to_string(),
    });

    let mut handles = vec![];

    for i in 0..4 {
        let counter = Arc::clone(&counter);
        let handle = thread::spawn(move || {
            for _ in 0..100 {
                let mut count = counter.count.lock().unwrap();
                *count += 1;
            }
            println!("thread {} done", i);
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap();
    }

    let final_count = counter.count.lock().unwrap();
    println!("{}: {} total", counter.name, *final_count);

    Ok(())
}
```

What's happening:
1. `Arc::new(...)` — allocate once, share with all threads
2. `Arc::clone(&counter)` — cheap refcount bump per thread
3. `move ||` — transfer ownership of the cloned `Arc` into each closure
4. `.lock().unwrap()` — acquire the mutex, increment, release
5. `handle.join().unwrap()` — wait for all threads, propagate panics

The next article replaces `std::thread` with `tokio::spawn`, `Mutex` with `RwLock`, and introduces channels and semaphores.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 5. 一个小练习

把四个概念放在一起：创建线程，用 `Arc<Mutex<T>>` 共享状态，用 `Result` 处理错误。

```rust
use std::sync::{Arc, Mutex};
use std::thread;

struct SharedCounter {
    count: Mutex<u64>,
    name: String,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let counter = Arc::new(SharedCounter {
        count: Mutex::new(0),
        name: "requests".to_string(),
    });

    let mut handles = vec![];

    for i in 0..4 {
        let counter = Arc::clone(&counter);
        let handle = thread::spawn(move || {
            for _ in 0..100 {
                let mut count = counter.count.lock().unwrap();
                *count += 1;
            }
            println!("线程 {} 完成", i);
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap();
    }

    let final_count = counter.count.lock().unwrap();
    println!("{}: {} 总计", counter.name, *final_count);

    Ok(())
}
```

发生了什么：
1. `Arc::new(...)` — 分配一次，与所有线程共享
2. `Arc::clone(&counter)` — 每线程廉价的引用计数递增
3. `move ||` — 将克隆的 `Arc` 所有权转移到每个闭包中
4. `.lock().unwrap()` — 获取 mutex，递增，释放
5. `handle.join().unwrap()` — 等待所有线程，传播 panic

下一篇文章把 `std::thread` 换成 `tokio::spawn`，`Mutex` 换成 `RwLock`，并引入 channel 和 semaphore。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

The second article covers the concurrency toolbox: `Mutex`, `RwLock`, `Atomic*`, `mpsc::channel`, `Semaphore`, `JoinSet`, and `buffer_unordered`. The third walks through five real bugs from production — the 429 cascade storm, cold-start concurrency, DB lock contention, fatal error broadcasting, and graceful shutdown — and what actually solved them.

---

*Code examples are simplified from production Rust in [ChatPD](https://github.com/anjiexu-pku), [asterinas](https://github.com/asterinas/asterinas), and [mcpr](https://github.com/TankTechnology).*

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

第二篇文章覆盖并发工具箱：`Mutex`、`RwLock`、`Atomic*`、`mpsc::channel`、`Semaphore`、`JoinSet` 和 `buffer_unordered`。第三篇走查五个来自生产的真实 bug——429 级联风暴、冷启动并发、DB 锁争用、致命错误广播和优雅停机——以及实际解决它们的方法。

---

*代码示例从 [ChatPD](https://github.com/anjiexu-pku)、[asterinas](https://github.com/asterinas/asterinas) 和 [mcpr](https://github.com/TankTechnology) 的生产 Rust 代码简化而来。*

</div>

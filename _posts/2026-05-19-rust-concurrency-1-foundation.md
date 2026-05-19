---
title: "Rust Concurrency from Zero to Production (1): The Foundation You Can't Skip"
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

This is the first of a three-part series on Rust concurrency, drawn from real production code across three Rust projects (ChatPD, asterinas, and mcpr) and 184 coding sessions. By the end of this series, you'll understand not just the primitives, but how to combine them into resilient, production-grade concurrent systems.

Part 1 covers the Rust foundations you absolutely need before touching `tokio::spawn`. If you're coming from Python, Go, or JavaScript, these four concepts explain why Rust's concurrency story is fundamentally different — and safer.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

这是三篇 Rust 并发系列文章的第一篇。内容来源于三个真实 Rust 项目（ChatPD、asterinas、mcpr）和 184 个编程会话的实战经验。读完这个系列，你将不仅理解并发原语，而且知道如何将它们组合成健壮的、生产级的并发系统。

第一篇涵盖在使用 `tokio::spawn` 之前必须掌握的 Rust 基础。如果你有 Python、Go 或 JavaScript 的经验，这四个概念将解释为什么 Rust 的并发模型从根本上不同 — 也更安全。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 1. Ownership and Borrowing in 15 Minutes

Rust's concurrency safety is not magic. It's a direct consequence of the ownership system. If you understand `move`, `&`, and `&mut`, you already understand why Rust eliminates data races at compile time.

### The Three Rules

```rust
// Rule 1: Every value has exactly one owner at a time.
let s1 = String::from("hello");
let s2 = s1;           // s1 is MOVED — you can't use s1 anymore
// println!("{}", s1); // ❌ compile error: value borrowed after move

// Rule 2: You can have either one mutable reference OR many immutable references.
let mut v = vec![1, 2, 3];
let r1 = &v;           // shared reference
let r2 = &v;           // fine: multiple shared references
// let r3 = &mut v;    // ❌ can't have &mut while & exists
println!("{:?} {:?}", r1, r2);

// Rule 3: References must always be valid (no dangling pointers).
fn dangle() -> &String {
    let s = String::from("hello");
    &s                   // ❌ s is dropped at end of scope
}
```

### Why This Matters for Concurrency

In other languages, data races happen when two threads touch the same data and at least one is writing. The language doesn't stop you. In Rust, the borrow checker catches this at compile time:

```rust
use std::thread;

let mut data = vec![1, 2, 3];

thread::spawn(move || {
    data.push(4);  // data is MOVED into this thread
});

// println!("{:?}", data);  // ❌ data was moved — can't access here
```

The `move` keyword transfers ownership into the closure. After that, the parent thread has no access. No shared mutable state = no data race. This isn't a runtime check — it's a compile-time guarantee.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 1. 所有权与借用：十五分钟速览

Rust 的并发安全不是魔法，而是所有权系统的直接产物。理解 `move`、`&` 和 `&mut`，你就已经理解了为什么 Rust 能在编译时消灭 data race。

### 三条规则

```rust
// 规则1：每个值在任何时候只有一个所有者。
let s1 = String::from("hello");
let s2 = s1;           // s1 被 MOVED（转移）了 — 你不能再使用 s1
// println!("{}", s1); // ❌ 编译错误：值已被移动

// 规则2：要么一个可变引用，要么多个不可变引用。
let mut v = vec![1, 2, 3];
let r1 = &v;           // 共享引用
let r2 = &v;           // 没问题：可以有多个共享引用
// let r3 = &mut v;    // ❌ 已经有 & 引用在使用了，不能再有 &mut
println!("{:?} {:?}", r1, r2);

// 规则3：引用必须始终有效（没有悬垂指针）。
fn dangle() -> &String {
    let s = String::from("hello");
    &s  // ❌ s 在作用域结束时被释放
}
```

### 为什么并发需要关心这个

在其他语言中，data race 发生在两个线程同时访问同一数据且至少有一个在写入时——语言不会阻止你。在 Rust 中，borrow checker 在编译时就抓住了这个问题：

```rust
use std::thread;

let mut data = vec![1, 2, 3];

thread::spawn(move || {
    data.push(4);  // data 被 MOVE 进入这个线程
});

// println!("{:?}", data);  // ❌ data 已被移动 — 这里无法访问
```

`move` 关键字将所有权转移给闭包。之后，父线程就没有访问权。**没有共享的可变状态 = 没有 data race**。这不是运行时检查——这是编译时保证。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 2. `Send` and `Sync` — The Traits That Guard Concurrency

These two traits are the reason the compiler can say "you can't send this across threads" before your code ever runs. Unlike `Mutex` or `Atomic`, which are types you write, `Send` and `Sync` are *marker traits* — the compiler reasons about them automatically. But when you get a compile error involving them, you need to understand what they mean.

### `Send`: Safe to Transfer Ownership Across Threads

A type is `Send` if it's safe to move ownership of its values to another thread. Most Rust types are `Send`:

```rust
fn is_send<T: Send>() {}

is_send::<i32>();         // ✅
is_send::<String>();       // ✅
is_send::<Vec<String>>();  // ✅
is_send::<Mutex<i32>>();  // ✅
```

What is *not* `Send`? Types that wrap non-thread-safe state. The classic example is `Rc<T>`:

```rust
use std::rc::Rc;

// is_send::<Rc<i32>>();    // ❌ Rc is NOT Send

// Rc's reference count is non-atomic. Two threads incrementing
// it simultaneously would cause a data race on the count itself.
```

`Arc<T>` is the `Send` version. The "A" stands for *atomic* — its reference count uses atomic operations:

```rust
use std::sync::Arc;

// is_send::<Arc<i32>>();     // ✅ Arc IS Send (if T is Send + Sync)
```

### `Sync`: Safe to Share References Across Threads

A type is `Sync` if it's safe to share a reference (`&T`) across threads. If `&T` is `Send`, then `T` is `Sync`.

```rust
fn is_sync<T: Sync>() {}

is_sync::<i32>();         // ✅
is_sync::<Mutex<i32>>();  // ✅ Mutex provides interior mutability safely
// is_sync::<Rc<i32>>();  // ❌ Rc is neither Send nor Sync
// is_sync::<RefCell<i32>>(); // ❌ RefCell is Sync (wrong!) — actually it's not Send
```

### The Practical Rule

When `tokio::spawn` rejects your code with "the trait bound `Send` is not satisfied," look for:
1. An `Rc<T>` that should be `Arc<T>`
2. A `RefCell<T>` that should be `Mutex<T>` or `RwLock<T>`
3. A raw pointer or `*mut T` being passed around
4. A non-`Send` type buried inside a struct

The fix is usually straightforward once you know which type is the problem.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 2. `Send` 和 `Sync` — 守卫并发安全的两个 trait

这两个 trait 是编译器能在代码运行前就说"你不能把这个送过线程"的原因。与 `Mutex` 或 `Atomic` 不同（这些是你写的类型），`Send` 和 `Sync` 是 *marker trait* — 编译器自动推导它们。但当你有涉及它们的编译错误时，你需要理解它们的含义。

### `Send`：可以安全地将所有权转移到另一个线程

如果一个类型的值可以安全地 move 到另一个线程，它就是 `Send`。大多数 Rust 类型都是 `Send`：

```rust
fn is_send<T: Send>() {}

is_send::<i32>();         // ✅
is_send::<String>();       // ✅
is_send::<Vec<String>>();  // ✅
is_send::<Mutex<i32>>();  // ✅
```

什么不是 `Send`？包装了非线程安全状态的类型。经典例子是 `Rc<T>`：

```rust
use std::rc::Rc;

// is_send::<Rc<i32>>();    // ❌ Rc 不是 Send

// Rc 的引用计数是非原子的。两个线程同时增加计数
// 会导致对计数本身的 data race。
```

`Arc<T>` 是 `Rc<T>` 的 `Send` 版本。"A" 代表 *atomic*（原子）— 它的引用计数使用原子操作：

```rust
use std::sync::Arc;

// is_send::<Arc<i32>>();     // ✅ Arc 是 Send（前提是 T 是 Send + Sync）
```

### `Sync`：可以安全地在多个线程间共享引用

如果一个类型可以安全地在多个线程间共享引用（`&T`），它就是 `Sync`。如果 `&T` 是 `Send`，那么 `T` 就是 `Sync`。

```rust
fn is_sync<T: Sync>() {}

is_sync::<i32>();         // ✅
is_sync::<Mutex<i32>>();  // ✅ Mutex 安全地提供了内部可变性
// is_sync::<Rc<i32>>();  // ❌ Rc 既不是 Send 也不是 Sync
// is_sync::<RefCell<i32>>(); // ❌ RefCell 不是 Sync (它的借用检查不是线程安全的)
```

### 实用规则

当 `tokio::spawn` 用 "the trait bound `Send` is not satisfied" 拒绝你的代码时，找：
1. `Rc<T>` — 应该改成 `Arc<T>`
2. `RefCell<T>` — 应该改成 `Mutex<T>` 或 `RwLock<T>`
3. 裸指针或 `*mut T` 被传来传去
4. 结构体深处嵌入了一个非 `Send` 的类型

修复通常是直截了当的，一旦你确定是哪个类型出了问题。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 3. `Arc<T>` — The Cost of Shared Ownership

`Arc<T>` appears everywhere in concurrent Rust code. In our ChatPD pipeline alone, `Arc` is used for configs, shared counters, abort flags, and semaphores. Understanding its cost is critical.

### `Arc::clone` Is Not a Deep Copy

```rust
use std::sync::Arc;

let config = Arc::new(vec![1, 2, 3]);  // allocate once
let handle1 = Arc::clone(&config);       // only bumps atomic refcount
let handle2 = Arc::clone(&config);       // same — no data copy

// Three Arcs point to the same heap allocation.
// When all three go out of scope, the Vec is freed.
```

The `clone` is cheap: one atomic increment. But it's not free — atomic operations still cost CPU cycles (L1 cache line bouncing between cores). For hot-loop counters, prefer `AtomicUsize` directly. For read-heavy shared data, `Arc` is the right choice.

### `Arc<RwLock<T>>` — The Workhorse Pattern

Most shared mutable state in async Rust uses this combination:

```rust
use std::sync::{Arc, RwLock};
use std::time::Instant;

// From ChatPD src/arxiv_paper.rs — a real pattern from production:
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// Why RwLock and not Mutex?
// - Read path (every request before sending): read lock — cheap, no contention
// - Write path (when we hit 429): write lock — rare, only on rate-limit
// This is "read-heavy, write-rare" — RwLock's sweet spot.
```

Key insight: choose the lock type based on access pattern, not habit. `Mutex` is the default, `RwLock` wins when reads dominate.

### `Arc` Is Not Always the Answer

In our pipeline, the DB writer owns its `Connection` directly:

```rust
// ✅ Better: single owner, no Arc, no Mutex
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    // ... conn used directly, no contention
}
```

If only one task needs a value, don't wrap it in `Arc` — pass ownership.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 3. `Arc<T>` — 共享所有权的代价

`Arc<T>` 在并发 Rust 代码中无处不在。仅在我们的 ChatPD pipeline 中，`Arc` 就用于 config、共享计数器、abort flag 和 semaphore。理解它的代价很重要。

### `Arc::clone` 不是深拷贝

```rust
use std::sync::Arc;

let config = Arc::new(vec![1, 2, 3]);  // 只分配一次
let handle1 = Arc::clone(&config);       // 只原子的增加引用计数
let handle2 = Arc::clone(&config);       // 同上 — 没有数据拷贝

// 三个 Arc 指向同一个堆分配。
// 当所有三个都离开作用域时，Vec 被释放。
```

`clone` 是廉价的：一次原子递增。但它不是免费的 — 原子操作仍然消耗 CPU 周期（核间的 L1 cache line bouncing）。对于热循环中的计数器，最好直接用 `AtomicUsize`。对于读多写少的共享数据，`Arc` 是正确的选择。

### `Arc<RwLock<T>>` — 主力模式

异步 Rust 中的大多数共享可变状态使用这个组合：

```rust
use std::sync::{Arc, RwLock};
use std::time::Instant;

// 来自 ChatPD src/arxiv_paper.rs — 一个真实的生产模式：
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// 为什么是 RwLock 而不是 Mutex？
// - 读路径（每个请求发送前）：读锁 — 便宜，无争用
// - 写路径（遇到 429 时）：写锁 — 罕见，仅在限流时
// 这是"读多写少" — RwLock 的最佳使用场景。
```

关键洞察：根据访问模式选择锁类型，而不是习惯性选择。`Mutex` 是默认值，当读操作占主导时 `RwLock` 胜出。

### `Arc` 并不总是正确答案

在我们的 pipeline 中，DB 写入器直接拥有它的 `Connection`：

```rust
// ✅ 更好：单一所有者，没有 Arc，没有 Mutex
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    // ... conn 直接使用，无争用
}
```

如果只有一个 task 需要一个值，不要把它包在 `Arc` 里 — 直接传递所有权。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 4. `Result<T, E>` — Errors Don't Disappear

In concurrent code, errors are especially dangerous. A panicking task takes down the whole process. A silently swallowed error corrupts your data. Rust's `Result` makes errors explicit — and the `?` operator makes propagation painless.

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

### In Concurrent Contexts: Errors Need Propagation

When multiple tasks are running, a single task's error shouldn't silently vanish. In our pipeline, when the LLM API quota is exhausted, we broadcast the error via `AtomicBool`:

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// In each LLM worker:
if err_str.contains("401") || err_str.contains("quota") {
    eprintln!("FATAL: API quota exhausted. Aborting pipeline.");
    abort_flag.store(true, Ordering::Relaxed);
    return;  // stop this worker
}

// In other workers:
if abort_flag.load(Ordering::Relaxed) {
    return;  // stop without producing error records
}
```

This pattern — `Result` for local errors, `AtomicBool` for global abort — is the backbone of resilient concurrent Rust programs.

### `anyhow` vs `thiserror`

For application code: use `anyhow::Result<T>`. It wraps any error type, adds context, and provides nice error messages.

For library code: use `thiserror` to define a proper error enum. Callers can match on specific error variants.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 4. `Result<T, E>` — 错误不会消失

在并发代码中，错误尤其危险。一个 panic 的 task 会结束整个进程。一个被静默吞掉的错误会污染你的数据。Rust 的 `Result` 使错误显式化 — 而 `?` 操作符使传播变得轻松。

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

### 并发上下文中：错误需要传播

当多个 task 并发运行时，单个 task 的错误不应该静默消失。在我们的 pipeline 中，当 LLM API quota 耗尽时，我们通过 `AtomicBool` 广播错误：

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// 在每个 LLM worker 中：
if err_str.contains("401") || err_str.contains("quota") {
    eprintln!("致命错误：API quota 已耗尽。中止 pipeline。");
    abort_flag.store(true, Ordering::Relaxed);
    return;  // 停止这个 worker
}

// 在其他 worker 中：
if abort_flag.load(Ordering::Relaxed) {
    return;  // 停止，不产生错误记录
}
```

这个模式 — `Result` 处理局部错误，`AtomicBool` 处理全局中止 — 是健壮的并发 Rust 程序的骨干。

### `anyhow` vs `thiserror`

应用代码：使用 `anyhow::Result<T>`。它包装任何错误类型，添加上下文，提供友好的错误消息。

库代码：使用 `thiserror` 定义合适的错误枚举。调用方可以匹配特定的错误变体。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## 5. Warm-up Exercise: Share Data Across Threads

Let's put these four concepts together. We'll build a minimal program that shares state across threads, handles errors, and uses `Arc`.

```rust
use std::sync::{Arc, Mutex};
use std::thread;
use std::io::{self, Write};

/// A shared counter that multiple threads can increment.
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
    // output: requests: 400 total

    Ok(())
}
```

Walk through what's happening:
1. `Arc::new(...)` — allocate once, share with all threads
2. `Arc::clone(&counter)` — cheap refcount bump per thread
3. `move ||` — transfer ownership of the `Arc` into each closure
4. `.lock().unwrap()` — acquire the mutex, increment, release
5. `handle.join().unwrap()` — wait for all threads, propagate panics

In Part 2, we'll replace `std::thread` with `tokio::spawn`, `Mutex` with `RwLock`, and add channels, semaphores, and more.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 5. 热身练习：跨线程共享数据

让我们把这四个概念放在一起。我们将构建一个最小程序，在多个线程间共享状态，处理错误，并使用 `Arc`。

```rust
use std::sync::{Arc, Mutex};
use std::thread;
use std::io::{self, Write};

/// 一个可以被多个线程递增的共享计数器。
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
    // 输出：requests: 400

    Ok(())
}
```

逐步理解发生了什么：
1. `Arc::new(...)` — 分配一次，与所有线程共享
2. `Arc::clone(&counter)` — 每个线程廉价的引用计数增加
3. `move ||` — 将 `Arc` 的所有权转移到每个闭包中
4. `.lock().unwrap()` — 获取 mutex，递增，释放
5. `handle.join().unwrap()` — 等待所有线程，传播 panic

在第二篇中，我们将把 `std::thread` 替换为 `tokio::spawn`，`Mutex` 替换为 `RwLock`，并引入通道、信号量等更多内容。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## What's Next

In Part 2, we'll cover the concurrency toolbox: `Mutex`, `RwLock`, `Atomic*`, `mpsc::channel`, `Semaphore`, `JoinSet`, and `buffer_unordered`. Each primitive comes with a real use case from production code.

In Part 3, we'll walk through five real concurrency bugs — the 429 cascade storm, the cold-start concurrency problem, DB lock contention, fatal error broadcasting, and graceful shutdown — and show how the right combination of primitives solves each one elegantly.

---

*This series is based on production Rust code from three projects (ChatPD, asterinas, mcpr) and 184 coding sessions. All code examples are simplified from real implementations.*

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 下一篇预告

在第二篇中，我们将覆盖并发工具箱：`Mutex`、`RwLock`、`Atomic*`、`mpsc::channel`、`Semaphore`、`JoinSet` 和 `buffer_unordered`。每个原语都配有来自生产代码的真实用例。

在第三篇中，我们将走查五个真实的并发 bug — 429 级联风暴、冷启动并发问题、DB 锁争用、致命错误广播和优雅停机 — 并展示如何用正确的原语组合优雅地解决每一个。

---

*本系列基于三个 Rust 项目（ChatPD、asterinas、mcpr）和 184 个编程会话的生产级代码。所有代码示例均从真实实现简化而来。*

</div>

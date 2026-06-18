---
title: "Rust 并发笔记 (1)：所有权、类型与错误"
date: 2026-05-19
categories:
  - tech
tags:
  - rust
  - concurrency
  - systems-programming
excerpt: "Rust concurrency notes part 1: how ownership, type system, and error handling create a foundation for fearless concurrency—Send, Sync, and what the compiler actually enforces."
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
  <a class="active" href="#zh" onclick="switchLang('zh');return false">中文</a>|
  <a href="#en" onclick="switchLang('en');return false">English</a>
</div>

<div id="lang-zh" class="lang-content" markdown="1">

# Rust 并发笔记 (1)：所有权、类型与错误

过去几个月在做一个叫 ChatPD 的项目，用 LLM 批量处理 arXiv 论文。这中间踩了不少 Rust 并发的坑。回过头看，Rust 的并发模型建立在几个看起来跟并发没什么关系的基础概念上——所有权、`Send`/`Sync`、`Arc` 和 `Result`。这篇笔记梳理它们。

---

## 1. 所有权与借用

Rust 在编译时消灭 data race。这不是什么运行时检测，也不是额外拼接到类型系统上的功能——它就是所有权机制的直接产物。三条规则：

```rust
// 规则1：每个值在任何时候只有一个所有者。
let s1 = String::from("hello");
let s2 = s1;           // s1 被 move 了——不能再用了
// println!("{}", s1); // ❌ 编译错误

// 规则2：要么一个可变引用，要么多个不可变引用。
let mut v = vec![1, 2, 3];
let r1 = &v;           // 共享引用
let r2 = &v;           // 可以有多个共享引用
// let r3 = &mut v;    // ❌ 有 & 在用就不能有 &mut

// 规则3：引用必须始终有效（没有悬垂指针）。
fn dangle() -> &String {
    let s = String::from("hello");
    &s  // ❌ s 在函数结束时被释放
}
```

### 跟并发的联系

在大多数语言里，两个线程同时访问同一数据且至少一个在写入，就是 data race。语言不会阻止它。Rust 的 borrow checker 在编译时就抓住了：

```rust
use std::thread;

let mut data = vec![1, 2, 3];

thread::spawn(move || {
    data.push(4);  // data 被 MOVE 进这个线程了
});

// println!("{:?}", data);  // ❌ data 已经不属于这里了
```

`move` 关键字把所有权转给了闭包。之后原线程就没有访问权。**没有共享的可变状态，就没有 data race。** 这个保证是编译时的，不是运行时的。

---

## 2. `Send` 和 `Sync`

这两个是 marker trait——编译器对大多数类型自动推导它们。它们回答两个问题：这个值能 move 到另一个线程吗？这个值的引用能跨线程共享吗？

### `Send`：跨线程转移所有权

一个类型的值可以安全地 move 到另一个线程，它就是 `Send`。大多数类型都是：

```rust
fn is_send<T: Send>() {}

is_send::<i32>();         // ✅
is_send::<String>();       // ✅
is_send::<Mutex<i32>>();  // ✅
```

经典反例是 `Rc<T>`——它的引用计数用的是非原子操作：

```rust
use std::rc::Rc;
// is_send::<Rc<i32>>();    // ❌ Rc 不是 Send
```

`Arc<T>` 是它的 `Send` 版本。那个 "A" 就是 *atomic* 的意思：

```rust
use std::sync::Arc;
// is_send::<Arc<i32>>();     // ✅（前提是 T: Send + Sync）
```

### `Sync`：跨线程共享引用

一个类型的引用（`&T`）可以安全地跨线程共享，它就是 `Sync`：

```rust
fn is_sync<T: Sync>() {}

is_sync::<i32>();         // ✅
is_sync::<Mutex<i32>>();  // ✅ Mutex 安全地提供内部可变性
// is_sync::<Rc<i32>>();  // ❌ Rc 两者都不是
```

### `tokio::spawn` 报 `Send` 错怎么办

最常见的编译错误长这样：

```
error[E0277]: `Rc<i32>` cannot be sent between threads safely
```

常见原因就几个：`Rc<T>` 该换成 `Arc<T>`、`RefCell<T>` 该换成 `Mutex<T>` 或 `RwLock<T>`、结构体深处藏了个裸指针、或者依赖库引入了非 `Send` 的类型。确定是哪个类型的问题之后，修复通常是机械的。

---

## 3. `Arc<T>`——共享所有权的代价

`Arc<T>` 在并发 Rust 里遍地都是。在 ChatPD 的 pipeline 里，它承载着配置、计数器、abort flag、semaphore，在几十个 async task 之间传递。

### `Arc::clone` 只是原子加一

```rust
use std::sync::Arc;

let config = Arc::new(vec![1, 2, 3]);  // 堆上分配一次
let h1 = Arc::clone(&config);           // 原子地给引用计数 +1
let h2 = Arc::clone(&config);           // 同样，不拷贝数据

// 三个 Arc 指向同一块堆内存
```

`clone` 便宜，但不免费——原子操作会因为核间的 cache line 弹跳消耗 CPU 周期。热循环里的计数器，直接用 `AtomicUsize` 更划算。

### `Arc<RwLock<T>>`

异步 Rust 里大多数共享可变状态都用这个组合。这是 ChatPD 里的一个真实例子——全局限流闸门：

```rust
use tokio::sync::RwLock;
use std::time::Instant;
use once_cell::sync::Lazy;

// 全局限流闸门。每个请求发送前都读（高频），只在收到 429 时写（罕见）。
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// 读路径：共享访问，常见情况下无争用
let until = *RATE_LIMITED_UNTIL.read().await;

// 写路径：独占，但很少触发
let mut guard = RATE_LIMITED_UNTIL.write().await;
*guard = Some(Instant::now() + Duration::from_secs(60));
```

这里用 `RwLock` 而不是 `Mutex`，因为读远超写。锁类型值得根据访问模式来选，而不是习惯性地用 `Mutex`。

### `Arc` 不是必须的

pipeline 里的 DB writer 只被一个 task 使用：

```rust
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    // conn 直接被这个 task 独占——没有 Arc，没有 Mutex，没有争用
    while let Some(record) = rx.recv().await { /* 写入 */ }
}
```

只有一个所有者的时候，通过 channel 或函数参数直接传所有权就行了，不需要 `Arc`。

---

## 4. `Result<T, E>`——错误不会自己消失

并发代码里错误处理更重要。一个 panic 的 task 把整个进程带走了。一个被静默吞掉的错误默默污染数据。Rust 的 `Result` 强制错误显式化，`?` 让传播简洁。

### 基本用法

```rust
fn read_config(path: &str) -> Result<String, std::io::Error> {
    let contents = std::fs::read_to_string(path)?;  // 失败了就返回 Err
    Ok(contents)
}
```

### 并发里的错误

多个 task 同时跑的时候，一个 task 的失败怎么让其他人知道？ChatPD 里有一个场景：LLM API key 的 quota 耗尽了。我们用一个 `AtomicBool` 广播这个致命错误：

```rust
use std::sync::atomic::{AtomicBool, Ordering};

let abort_flag = Arc::new(AtomicBool::new(false));

// 在 LLM worker 里检测到 quota 耗尽：
if err_str.contains("401") || err_str.contains("quota") {
    eprintln!("致命：API quota 耗尽，中止管道");
    abort_flag.store(true, Ordering::Relaxed);
    return;
}

// 其他 worker 在每个工作项开始前检查：
if abort_flag.load(Ordering::Relaxed) {
    return;  // 静默退出，不产生错误记录
}
```

这自然地把错误分成了三类：

| 类别 | 例子 | 处理 |
|------|------|------|
| 瞬时 (transient) | 429、timeout | 退避重试 |
| 终端 (terminal) | 404、解析失败 | 写错误记录，继续 |
| 致命 (fatal) | 401、quota 耗尽 | 设 abort flag，全部停止 |

### `anyhow` vs `thiserror`

应用代码用 `anyhow::Result<T>`——它包装任意错误类型、附加上下文。库代码用 `thiserror`——调用方可以 match 具体的错误变体。区别在于调用方是否需要以编程方式区分错误类型。

---

## 5. 一个小练习

把四个概念拼在一起：创建线程，用 `Arc<Mutex<T>>` 共享状态，用 `Result` 处理错误。

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
        handles.push(thread::spawn(move || {
            for _ in 0..100 {
                let mut count = counter.count.lock().unwrap();
                *count += 1;
            }
            println!("线程 {} 完成", i);
        }));
    }

    for h in handles { h.join().unwrap(); }

    let final_count = counter.count.lock().unwrap();
    println!("{}: {} 总计", counter.name, *final_count);
    Ok(())
}
```

这五行干了什么：
1. `Arc::new(...)`——堆上分配一次，和所有线程共享
2. `Arc::clone(&counter)`——每线程原子地引用计数 +1
3. `move ||`——把克隆的 `Arc` 所有权转给闭包
4. `.lock().unwrap()`——获取 mutex，递增，释放（guard 离开作用域时自动释放）
5. `.join().unwrap()`——等所有线程结束，有 panic 就传播

---

第二篇笔记覆盖并发工具箱：`Mutex`/`RwLock`/`Atomic*`、`channel`、并发控制的三种模式、错误传播策略。第三篇走查五个来自 ChatPD 生产的真实 bug——429 级联风暴、冷启动并发、DB 锁争用、致命错误广播、优雅停机——以及实际起作用的方案。

*代码示例从 [ChatPD](https://github.com/anjiexu-pku)、[asterinas](https://github.com/asterinas/asterinas) 和 [mcpr](https://github.com/TankTechnology) 的生产 Rust 代码简化而来。*

</div>

<div id="lang-en" class="lang-content" style="display:none" markdown="1">

# Rust Concurrency Notes (1): Ownership, Types, and Errors

Over the past few months, while building a project called ChatPD to process arXiv papers in bulk with LLMs, I ran into quite a few Rust concurrency pitfalls. Looking back, Rust's concurrency model rests on several concepts that do not look concurrency-specific at first glance: ownership, `Send`/`Sync`, `Arc`, and `Result`. This note organizes those foundations.

---

## 1. Ownership and Borrowing

Rust eliminates data races at compile time. This is not a runtime check, nor is it a feature bolted onto the type system. It is a direct consequence of ownership. The rules are:

```rust
// Rule 1: every value has exactly one owner at any moment.
let s1 = String::from("hello");
let s2 = s1;           // s1 has been moved and can no longer be used
// println!("{}", s1); // compile error

// Rule 2: either one mutable reference, or many immutable references.
let mut v = vec![1, 2, 3];
let r1 = &v;           // shared reference
let r2 = &v;           // multiple shared references are allowed
// let r3 = &mut v;    // cannot have &mut while & references are in use

// Rule 3: references must always be valid; no dangling pointers.
fn dangle() -> &String {
    let s = String::from("hello");
    &s  // s is dropped when the function returns
}
```

### Connection to Concurrency

In most languages, if two threads access the same data at the same time and at least one of them writes, you have a data race. The language will usually not stop you. Rust's borrow checker catches this at compile time:

```rust
use std::thread;

let mut data = vec![1, 2, 3];

thread::spawn(move || {
    data.push(4);  // data is moved into this thread
});

// println!("{:?}", data);  // data no longer belongs here
```

The `move` keyword transfers ownership into the closure. After that, the original thread has no access to `data`. **No shared mutable state, no data race.** This guarantee is compile-time, not runtime.

---

## 2. `Send` and `Sync`

These are marker traits. The compiler automatically derives them for most types. They answer two questions: can this value be moved to another thread? Can references to this value be shared across threads?

### `Send`: Transferring Ownership Across Threads

If values of a type can be safely moved to another thread, the type is `Send`. Most types are:

```rust
fn is_send<T: Send>() {}

is_send::<i32>();         // ok
is_send::<String>();      // ok
is_send::<Mutex<i32>>();  // ok
```

The classic counterexample is `Rc<T>`, whose reference count uses non-atomic operations:

```rust
use std::rc::Rc;
// is_send::<Rc<i32>>();    // Rc is not Send
```

`Arc<T>` is the `Send` version. The "A" means *atomic*:

```rust
use std::sync::Arc;
// is_send::<Arc<i32>>();     // ok, assuming T: Send + Sync
```

### `Sync`: Sharing References Across Threads

If references to a type (`&T`) can be safely shared across threads, the type is `Sync`:

```rust
fn is_sync<T: Sync>() {}

is_sync::<i32>();         // ok
is_sync::<Mutex<i32>>();  // ok: Mutex provides safe interior mutability
// is_sync::<Rc<i32>>();  // Rc is neither Send nor Sync
```

### What to Do When `tokio::spawn` Complains About `Send`

The most common compiler error looks like this:

```
error[E0277]: `Rc<i32>` cannot be sent between threads safely
```

The usual causes are mechanical: `Rc<T>` should become `Arc<T>`, `RefCell<T>` should become `Mutex<T>` or `RwLock<T>`, a raw pointer is hidden deep inside a struct, or a dependency introduced a non-`Send` type. Once you identify which type is responsible, the fix is usually straightforward.

---

## 3. `Arc<T>`: The Cost of Shared Ownership

`Arc<T>` appears everywhere in concurrent Rust. In ChatPD's pipeline, it carries configuration, counters, abort flags, and semaphores across dozens of async tasks.

### `Arc::clone` Is Just an Atomic Increment

```rust
use std::sync::Arc;

let config = Arc::new(vec![1, 2, 3]);  // one heap allocation
let h1 = Arc::clone(&config);          // atomically increment the refcount
let h2 = Arc::clone(&config);          // same, without copying the data

// all three Arc values point to the same heap allocation
```

`clone` is cheap, but not free. Atomic operations can burn CPU cycles through cache-line bouncing across cores. For counters in hot loops, a direct `AtomicUsize` is usually better.

### `Arc<RwLock<T>>`

Most shared mutable state in async Rust uses this combination. Here is a real example from ChatPD: a global rate-limit gate.

```rust
use tokio::sync::RwLock;
use std::time::Instant;
use once_cell::sync::Lazy;

// Global rate-limit gate. Every request reads before sending; only 429s write.
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

// Read path: shared access, usually uncontended
let until = *RATE_LIMITED_UNTIL.read().await;

// Write path: exclusive, but rare
let mut guard = RATE_LIMITED_UNTIL.write().await;
*guard = Some(Instant::now() + Duration::from_secs(60));
```

This uses `RwLock` instead of `Mutex` because reads vastly outnumber writes. The lock type should follow the access pattern, not habit.

### `Arc` Is Not Always Necessary

The DB writer in the pipeline is used by exactly one task:

```rust
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    // conn is exclusively owned by this task: no Arc, no Mutex, no contention
    while let Some(record) = rx.recv().await { /* write */ }
}
```

When there is only one owner, pass ownership directly through a channel or a function argument. You do not need `Arc`.

---

## 4. `Result<T, E>`: Errors Do Not Disappear by Themselves

Error handling matters even more in concurrent code. A panicking task can take down the process. A silently swallowed error can quietly corrupt data. Rust's `Result` makes errors explicit, and `?` keeps propagation concise.

### Basic Usage

```rust
fn read_config(path: &str) -> Result<String, std::io::Error> {
    let contents = std::fs::read_to_string(path)?;  // return Err on failure
    Ok(contents)
}
```

### Errors in Concurrent Code

When many tasks run at once, how should one task's failure notify the others? ChatPD has a case where the LLM API key runs out of quota. We broadcast this fatal error with an `AtomicBool`:

```rust
use std::sync::atomic::{AtomicBool, Ordering};

let abort_flag = Arc::new(AtomicBool::new(false));

// In an LLM worker, after detecting quota exhaustion:
if err_str.contains("401") || err_str.contains("quota") {
    eprintln!("fatal: API quota exhausted, aborting pipeline");
    abort_flag.store(true, Ordering::Relaxed);
    return;
}

// Other workers check before starting each item:
if abort_flag.load(Ordering::Relaxed) {
    return;  // exit quietly without producing error records
}
```

This naturally divides errors into three categories:

| Category | Example | Handling |
|----------|---------|----------|
| Transient | 429, timeout | Backoff and retry |
| Terminal | 404, parse failure | Write an error record and continue |
| Fatal | 401, quota exhausted | Set the abort flag and stop everything |

### `anyhow` vs `thiserror`

Use `anyhow::Result<T>` in application code: it wraps arbitrary error types and lets you attach context. Use `thiserror` in library code: callers can match on specific error variants. The difference is whether the caller needs to distinguish error types programmatically.

---

## 5. A Small Exercise

Put the four concepts together: create threads, share state with `Arc<Mutex<T>>`, and handle errors with `Result`.

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
        handles.push(thread::spawn(move || {
            for _ in 0..100 {
                let mut count = counter.count.lock().unwrap();
                *count += 1;
            }
            println!("thread {} done", i);
        }));
    }

    for h in handles { h.join().unwrap(); }

    let final_count = counter.count.lock().unwrap();
    println!("{}: {} total", counter.name, *final_count);
    Ok(())
}
```

Those five lines do the real work:

1. `Arc::new(...)`: allocate once on the heap and share with every thread.
2. `Arc::clone(&counter)`: atomically increment the refcount for each thread.
3. `move ||`: transfer ownership of the cloned `Arc` into the closure.
4. `.lock().unwrap()`: acquire the mutex, increment the value, and release it when the guard leaves scope.
5. `.join().unwrap()`: wait for every thread to finish and propagate panics.

---

The second note covers the concurrency toolbox: `Mutex`/`RwLock`/`Atomic*`, channels, three concurrency-control patterns, and error-propagation strategies. The third note walks through five real production bugs from ChatPD: 429 cascade storms, cold-start concurrency, DB lock contention, fatal-error broadcast, and graceful shutdown.

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
if (location.hash === '#en') {
  switchLang('en');
}
</script>

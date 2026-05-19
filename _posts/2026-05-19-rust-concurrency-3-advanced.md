---
title: "Rust Concurrency from Zero to Production (3): Five Real Bugs and Their Elegant Solutions"
date: 2026-05-19
categories:
  - tech
tags:
  - rust
  - concurrency
  - systems-programming
  - production
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

This is Part 3 of a three-part series on Rust concurrency. In [Part 1]({% post_url 2026-05-19-rust-concurrency-1-foundation %}), we covered the foundations. In [Part 2]({% post_url 2026-05-19-rust-concurrency-2-toolbox %}), we filled the toolbox. Now we go to production.

Each section below is a real bug encountered while building **ChatPD**, a Rust pipeline that processes hundreds of thousands of arXiv papers through LLMs. The code examples are simplified from the actual implementation running in production. For each bug, I'll walk through: what happened, why it happened, the naive fix, and the elegant solution.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

这是 Rust 并发系列三篇中的最后一篇。在[第一篇]({% post_url 2026-05-19-rust-concurrency-1-foundation %})中，我们覆盖了基础。在[第二篇]({% post_url 2026-05-19-rust-concurrency-2-toolbox %})中，我们填充了工具箱。现在我们进入生产环境。

下面每个章节都是构建 **ChatPD** 时遇到的真实 bug——一个通过 LLM 处理数十万篇 arXiv 论文的 Rust 管道。代码示例从实际运行的生产代码简化而来。对每个 bug，我将走查：发生了什么、为什么发生、天真修复、以及优雅方案。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## Problem 1: The 429 Cascade Storm

### What Happened

The pipeline has 12 concurrent fetchers, each downloading paper HTML from ar5iv (an arXiv HTML rendering service). One day, ar5iv started returning HTTP 429 (Too Many Requests). Here's what happened next:

1. All 12 fetchers received 429 simultaneously.
2. Each one independently started its exponential backoff timer.
3. All 12 timers expired at roughly the same time.
4. All 12 fetchers sent new requests simultaneously → 429 again.
5. This cycle repeated, creating a **self-reinforcing rate-limit storm**.

### Why It Happened

Each fetcher operated independently. There was no shared knowledge of the rate-limit state. The code looked like this (simplified):

```rust
// ❌ Each fetcher retries independently — no global coordination
async fn fetch_html_with_retry(url: &str) -> Result<String> {
    for retry in 0..MAX_RETRIES {
        match client.get(url).send().await {
            Ok(resp) => return resp.text().await,
            Err(e) if e.contains("429") => {
                let backoff = 500 * 2u64.pow(retry);
                sleep(Duration::from_millis(backoff)).await;
                // 12 tasks sleeping → 12 tasks waking up together → 12 requests → 429!
            }
            Err(e) => return Err(e),
        }
    }
}
```

### The Naive Fix

Add random jitter to the backoff:

```rust
let jitter = rand::thread_rng().gen_range(0..=1000u64);
sleep(Duration::from_millis(backoff + jitter)).await;
```

This helps, but doesn't solve the root problem: each task still doesn't know about the others' 429s. With 200 LLM callers in a later stage, the jitter-based approach becomes statistically unreliable.

### The Elegant Solution: Global Rate-Limit Gate

A single shared gate that all fetchers check before sending. When any one fetcher receives a 429, it sets the gate closed for a cooldown period. All fetchers wait at the gate.

```rust
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Global rate-limit gate. None means "open" (no limit).
/// Some(Instant) means "closed until this time."
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

/// Called when any request receives 429. Extends the cooldown
/// (never shortens it — handles race conditions on concurrent 429s).
async fn set_rate_limit_cooldown(secs: u64) {
    let deadline = Instant::now() + Duration::from_secs(secs);
    let mut guard = RATE_LIMITED_UNTIL.write().await;
    // Only extend, never shorten: if two tasks get 429 simultaneously,
    // the second one might set a shorter deadline. This check prevents that.
    if guard.map_or(true, |t| t < deadline) {
        *guard = Some(deadline);
    }
}

/// Called by every request before sending. Blocks until gate is open.
async fn wait_for_rate_limit() {
    loop {
        let until = *RATE_LIMITED_UNTIL.read().await;
        match until {
            None => return,                             // gate open
            Some(t) if t <= Instant::now() => return,   // cooldown expired
            Some(t) => tokio::time::sleep(t - Instant::now()).await,
        }
    }
}

// Now the fetcher simply does:
async fn fetch_html_with_retry(url: &str) -> Result<String> {
    for retry in 0..MAX_RETRIES {
        wait_for_rate_limit().await;  // ← gate check before EVERY request

        match client.get(url).send().await {
            Ok(resp) => return resp.text().await,
            Err(e) if e.contains("429") => {
                set_rate_limit_cooldown(60).await;  // ← close the gate
                let backoff = 500 * 2u64.pow(retry);
                let jitter = rand::thread_rng().gen_range(0..=1000u64);
                sleep(Duration::from_millis(backoff + jitter)).await;
            }
            Err(e) => return Err(e),
        }
    }
}
```

### Why This Is Elegant

1. **One line per request**: `wait_for_rate_limit().await` is all you add.
2. **Read-heavy, write-rare**: `RwLock` gives lock-free reads in the common case.
3. **Race-condition-proof**: the "only extend" logic means concurrent 429s don't shorten the cooldown.
4. **Works across any number of tasks**: 12 fetchers or 200 LLM callers — same gate, same behavior.

### Before / After

| Metric | Before | After |
|--------|--------|-------|
| 429 rate on retries | 80%+ | <5% |
| Fetch success rate (first attempt after cooldown) | ~15% | ~85% |
| Pipeline wall-clock time for 1000 papers | 45 min (with storms) | 12 min |

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 问题 1：429 级联风暴

### 发生了什么

管道有 12 个并发 fetcher，每个都从 ar5iv（一个 arXiv HTML 渲染服务）下载论文 HTML。某天，ar5iv 开始返回 HTTP 429（Too Many Requests）。接下来发生了什么：

1. 所有 12 个 fetcher 同时收到 429。
2. 每个 fetcher 独立启动自己的指数退避计时器。
3. 所有 12 个计时器大致同时到期。
4. 所有 12 个 fetcher 同时发送新请求 → 又 429。
5. 这个循环重复，产生了**自我强化的限流风暴**。

### 为什么发生

每个 fetcher 独立运作。没有共享的限流状态知识。代码大致是这样的（简化版）：

```rust
// ❌ 每个 fetcher 独立重试 — 没有全局协调
async fn fetch_html_with_retry(url: &str) -> Result<String> {
    for retry in 0..MAX_RETRIES {
        match client.get(url).send().await {
            Ok(resp) => return resp.text().await,
            Err(e) if e.contains("429") => {
                let backoff = 500 * 2u64.pow(retry);
                sleep(Duration::from_millis(backoff)).await;
                // 12 个 task 同时 sleep → 12 个 task 同时醒来 → 12 个请求 → 429！
            }
            Err(e) => return Err(e),
        }
    }
}
```

### 天真修复

给退避加随机 jitter：

```rust
let jitter = rand::thread_rng().gen_range(0..=1000u64);
sleep(Duration::from_millis(backoff + jitter)).await;
```

这有助益，但没有解决根本问题：每个 task 仍然不知道其他 task 的 429。在后面有 200 个 LLM caller 的阶段，基于 jitter 的方法在统计上变得不可靠。

### 优雅方案：全局限流闸门

一个所有 fetcher 在发送前都检查的单一共享闸门。当任何一个 fetcher 收到 429 时，它关闭闸门一个冷却期。所有 fetcher 在闸门处等待。

```rust
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// 全局限流闸门。None 表示"开"（无限流）。
/// Some(Instant) 表示"关闭至此时间"。
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

/// 任何请求收到 429 时调用。延长冷却期
/// （绝不缩短 — 处理并发 429 的竞态条件）。
async fn set_rate_limit_cooldown(secs: u64) {
    let deadline = Instant::now() + Duration::from_secs(secs);
    let mut guard = RATE_LIMITED_UNTIL.write().await;
    // 只延长，不缩短：如果两个 task 同时收到 429，
    // 第二个可能设置一个更短的截止时间。这个检查防止了这一点。
    if guard.map_or(true, |t| t < deadline) {
        *guard = Some(deadline);
    }
}

/// 每个请求在发送前调用。阻塞直到闸门打开。
async fn wait_for_rate_limit() {
    loop {
        let until = *RATE_LIMITED_UNTIL.read().await;
        match until {
            None => return,                             // 闸门开着
            Some(t) if t <= Instant::now() => return,   // 冷却期已过
            Some(t) => tokio::time::sleep(t - Instant::now()).await,
        }
    }
}

// 现在 fetcher 只需要：
async fn fetch_html_with_retry(url: &str) -> Result<String> {
    for retry in 0..MAX_RETRIES {
        wait_for_rate_limit().await;  // ← 每次请求前检查闸门

        match client.get(url).send().await {
            Ok(resp) => return resp.text().await,
            Err(e) if e.contains("429") => {
                set_rate_limit_cooldown(60).await;  // ← 关闭闸门
                let backoff = 500 * 2u64.pow(retry);
                let jitter = rand::thread_rng().gen_range(0..=1000u64);
                sleep(Duration::from_millis(backoff + jitter)).await;
            }
            Err(e) => return Err(e),
        }
    }
}
```

### 为什么这是优雅的

1. **每个请求一行**：你只加了 `wait_for_rate_limit().await`。
2. **读多写少**：`RwLock` 在常见情况下提供无锁读取。
3. **竞态安全**："只延长"逻辑意味着并发的 429 不会缩短冷却期。
4. **跨任意数量 task 工作**：12 个 fetcher 或 200 个 LLM caller — 同一个闸门，同样行为。

### 修复前后

| 指标 | 修复前 | 修复后 |
|------|--------|--------|
| 重试时的 429 率 | 80%+ | <5% |
| Fetch 成功率（冷却后首次尝试） | ~15% | ~85% |
| 1000 篇论文的管道耗时 | 45 分钟（有风暴） | 12 分钟 |

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## Problem 2: The Cold-Start Concurrency Problem

### What Happened

With the rate-limit gate in place, the pipeline no longer created storms. But it still wasn't efficient. The fetcher started with all 32 concurrent slots immediately. If ar5iv's actual capacity was lower that day (partial outage, competing traffic), the first wave of 32 requests would all get 429s, the gate would close, and we'd waste a full cycle.

### Why It Happened

We assumed the configured concurrency limit was _safe_. In practice, external service capacity varies by time of day, server load, and deployment state. Starting at full throttle is like flooring the accelerator on an icy road — you find the limit by exceeding it.

### The Elegant Solution: Adaptive Concurrency with `Semaphore`

Start at 4 concurrent (safe minimum). After every N successes, add one more concurrent slot — up to the configured maximum. This is a "soft start" that discovers actual capacity rather than assuming it.

```rust
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::sync::Semaphore;

fn fetch_initial_concurrency(cap: usize) -> usize {
    if cap <= 2 { return cap; }
    // Start at cap/4 (or cap/2 for small values).
    if cap <= 8 { (cap / 2).max(2) } else { (cap / 4).max(4) }
}

let initial = fetch_initial_concurrency(32);  // = 8
let max_concurrency = 32;
let ramp_every = 24;  // add 1 permit every 24 successes

let sem = Arc::new(Semaphore::new(initial));
let cur_permits = Arc::new(AtomicUsize::new(initial));
let success_ctr = Arc::new(AtomicUsize::new(0));

for paper in papers {
    // Acquire permit BEFORE spawning — this limits concurrency.
    let permit = sem.clone().acquire_owned().await.unwrap();

    let sem = sem.clone();
    let cur_permits = cur_permits.clone();
    let success_ctr = success_ctr.clone();

    tokio::spawn(async move {
        match fetch_and_process(paper).await {
            Ok(paper) => {
                // Ramp up on success.
                let n = success_ctr.fetch_add(1, Ordering::Relaxed) + 1;
                if n % ramp_every == 0 {
                    let cur = cur_permits.load(Ordering::Relaxed);
                    if cur < max_concurrency {
                        cur_permits.fetch_add(1, Ordering::Relaxed);
                        sem.add_permits(1);  // ← dynamic capacity increase
                        println!("Ramped to {}", cur + 1);
                    }
                }
                // ... send paper downstream
            }
            Err(_) => {
                // On failure, don't ramp down — the global gate handles backoff.
                // Ramping down would overreact to transient errors.
            }
        }
        drop(permit);
    });
}
```

### Why Ramp Up Only, Never Down?

The global rate-limit gate (Problem 1) already handles backoff. If we also ramped down, the two mechanisms would fight each other: the gate says "wait 60s," the semaphore says "reduce capacity." The result would be oscillation. **Separation of concerns**: the gate handles rate limits, the semaphore handles capacity discovery.

### The Retry Round System

Papers that fail (transient errors only — 429, timeout, connection) go into a retry pool. The retry rounds use _fixed_ concurrency that _decreases_ each round:

```rust
fn fetch_round_concurrency(cap: usize, round: usize) -> usize {
    (cap / (round + 1)).max(4).min(cap)
}
// Round 0: adaptive 8→32
// Round 1: cap / 2 = 16 (fixed)
// Round 2: cap / 3 = 10 (fixed)
// Round 3: cap / 4 = 8  (fixed)
```

Retry rounds are increasingly conservative. After three rounds, papers that still can't be fetched are logged as "throttled" and the pipeline moves on.

```rust
for round in 0..max_retry_rounds {
    if round > 0 {
        let concurrency = fetch_round_concurrency(cap, round);
        // Wait 90s between rounds for service recovery
        tokio::time::sleep(Duration::from_secs(90)).await;

        futures::stream::iter(pending_papers)
            .map(|paper| retry_fetch(paper))
            .buffer_unordered(concurrency)  // fixed window this round
            .for_each(|()| async {})
            .await;
    }
    // ... collect still-failed papers for next round
}
```

### Why This Is Elegant

1. **Discovers capacity**: doesn't assume the configured limit is always available.
2. **Single mechanism for backoff**: the rate-limit gate, not the semaphore, handles 429s.
3. **Retry rounds degrade gracefully**: each round is more conservative, preventing infinite retry loops.
4. **Observable**: `FetchPerfSummary` records initial/max concurrency, ramp rate, retry rounds — you can _see_ what happened.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 问题 2：冷启动并发问题

### 发生了什么

有了限流闸门后，管道不再制造风暴。但它仍然不高效。Fetcher 一开始就用满 32 个并发槽位。如果 ar5iv 当天的实际容量较低（部分故障、竞争流量），第一波 32 个请求全都会收到 429，闸门关闭，我们浪费了整整一个周期。

### 为什么发生

我们假设配置的并发上限是 _安全的_。实际上，外部服务的容量因时间、服务器负载和部署状态而变化。从全油门起步就像在结冰的路面上猛踩加速踏板 — 你通过超过极限来发现极限。

### 优雅方案：用 `Semaphore` 实现自适应并发

从 4 并发开始（安全下限）。每成功 N 次，增加一个并发槽位 — 直到配置的上限。这是一个"软启动"，发现实际容量而不是假设它。

```rust
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::sync::Semaphore;

fn fetch_initial_concurrency(cap: usize) -> usize {
    if cap <= 2 { return cap; }
    // 从 cap/4 开始（小值时用 cap/2）。
    if cap <= 8 { (cap / 2).max(2) } else { (cap / 4).max(4) }
}

let initial = fetch_initial_concurrency(32);  // = 8
let max_concurrency = 32;
let ramp_every = 24;  // 每 24 次成功增加 1 个许可

let sem = Arc::new(Semaphore::new(initial));
let cur_permits = Arc::new(AtomicUsize::new(initial));
let success_ctr = Arc::new(AtomicUsize::new(0));

for paper in papers {
    // 在 spawn 之前获取许可 — 这限制了并发。
    let permit = sem.clone().acquire_owned().await.unwrap();

    let sem = sem.clone();
    let cur_permits = cur_permits.clone();
    let success_ctr = success_ctr.clone();

    tokio::spawn(async move {
        match fetch_and_process(paper).await {
            Ok(paper) => {
                // 成功时爬坡。
                let n = success_ctr.fetch_add(1, Ordering::Relaxed) + 1;
                if n % ramp_every == 0 {
                    let cur = cur_permits.load(Ordering::Relaxed);
                    if cur < max_concurrency {
                        cur_permits.fetch_add(1, Ordering::Relaxed);
                        sem.add_permits(1);  // ← 动态增加容量
                        println!("爬坡至 {}", cur + 1);
                    }
                }
                // ... 将 paper 发送到下游
            }
            Err(_) => {
                // 失败时不下降 — 全局闸门处理退避。
                // 下降会对瞬时错误反应过度。
            }
        }
        drop(permit);
    });
}
```

### 为什么只升不降？

全局限流闸门（问题 1）已经处理了退避。如果我们同时下降，两个机制会互相冲突：闸门说"等 60s"，信号量说"减少容量"。结果会是振荡。**关注点分离**：闸门处理限流，信号量处理容量发现。

### 重试轮次系统

失败的论文（仅瞬时错误 — 429、timeout、连接）进入重试池。重试轮次使用 _固定_ 并发，每轮递 _减_：

```rust
fn fetch_round_concurrency(cap: usize, round: usize) -> usize {
    (cap / (round + 1)).max(4).min(cap)
}
// Round 0: 自适应 8→32
// Round 1: cap / 2 = 16（固定）
// Round 2: cap / 3 = 10（固定）
// Round 3: cap / 4 = 8 （固定）
```

重试轮次越来越保守。三轮后，仍然无法获取的论文被记录为"throttled"，管道继续前进。

```rust
for round in 0..max_retry_rounds {
    if round > 0 {
        let concurrency = fetch_round_concurrency(cap, round);
        // 轮次间等待 90s 让服务恢复
        tokio::time::sleep(Duration::from_secs(90)).await;

        futures::stream::iter(pending_papers)
            .map(|paper| retry_fetch(paper))
            .buffer_unordered(concurrency)  // 本轮固定窗口
            .for_each(|()| async {})
            .await;
    }
    // ... 收集仍然失败的论文用于下一轮
}
```

### 为什么这是优雅的

1. **发现容量**：不假设配置的上限总是可用的。
2. **退避的单一机制**：限流闸门而不是信号量处理 429。
3. **重试轮次优雅降级**：每轮更保守，防止无限重试循环。
4. **可观测**：`FetchPerfSummary` 记录初始/最大并发、爬坡速率、重试轮次 — 你可以 _看到_ 发生了什么。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## Problem 3: Database Lock Contention

### What Happened

The original ChatPD database access pattern used a global `Arc<Mutex<Connection>>`:

```rust
let db = DatabaseManager::new(&db_path)?;
let arc = db.connection();          // Arc<Mutex<Connection>>
let conn = arc.lock().unwrap();     // every query locks the whole DB
```

Every part of the pipeline — fetcher, builder, LLM caller — needed the connection to check for existing work or write results. Even read-only queries contended on the same mutex.

### Why It Happened

This is the "one big lock" anti-pattern. It's easy to write (`Arc<Mutex<Everything>>`) and works for low concurrency. But in a pipeline with 200 concurrent LLM callers each wanting to check if a paper was already processed, the mutex became a bottleneck.

### The Naive Fix

Use `RwLock` instead of `Mutex` for read-heavy access:

```rust
let db = DatabaseManager::new(&db_path)?;
let arc = db.connection();  // now Arc<RwLock<Connection>>
let conn = arc.read().unwrap();  // shared reads
```

This helps but doesn't address the deeper problem: SQLite itself serializes writes. Sharing a connection across 200 tasks is fundamentally wasteful.

### The Elegant Solution: Single-Owner Writer

Only the DB writer task needs a connection. All other tasks send data to it via a channel. The writer owns the connection exclusively — no Arc, no Mutex, no lock.

```rust
use tokio::sync::mpsc;

enum WriteRecord {
    Success { arxiv_id: String, raw_response: String, parsed_json: Option<String>, ... },
    Error   { arxiv_id: String, status: ProcessingStatusType, notes: Option<String>, ... },
}

// The DB writer owns its connection. No locks needed.
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    conn.execute_batch("PRAGMA journal_mode=WAL;")?;  // better concurrent reads

    let mut total = 0u64;
    let mut success_count = 0u64;
    let mut error_count = 0u64;

    while let Some(record) = rx.recv().await {
        let result = match record {
            WriteRecord::Success { arxiv_id, model, messages_json, raw_response,
                                   parsed_json, categories, processed_month } => {
                persist_production_write(&conn, ProductionWriteInput { ... })?;
                Ok(())
            }
            WriteRecord::Error { arxiv_id, status, categories, processed_month, notes } => {
                persist_terminal_error_record(&conn, arxiv_id, status, ...)?;
                Ok(())
            }
        };

        match result {
            Ok(()) => success_count += 1,
            Err(e) => eprintln!("[DBWriter] write error: {}", e),
        }

        if total % 100 == 0 {
            println!("[Pipeline] Written {} records ({} success), elapsed {:?}",
                     total, success_count, start.elapsed());
        }
        total += 1;
    }

    // No explicit close — Connection is dropped, SQLite WAL is checkpointed.
    StagePerfSummary { input_count: total as usize, output_count: success_count as usize, ... }
}
```

### The Pipeline Wiring

```rust
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

let fetcher  = tokio::spawn(run_fetcher(..., write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(..., write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(..., write_tx.clone(), ...));
drop(write_tx);  // ← crucial: drop main sender so channel closes after all tasks finish

let db_writer = tokio::spawn(run_db_writer(write_rx, db_path));
```

All three upstream stages send to the same `write_tx`. The DB writer receives from `write_rx`. When all upstream stages finish and drop their senders, `write_rx.recv()` returns `None`, and the writer exits naturally.

### Why This Is Elegant

1. **Zero lock contention**: the writer is the sole owner of the connection.
2. **Single writer = SQLite's happy place**: SQLite serializes writes anyway. One writer avoids SQLITE_BUSY.
3. **Channel provides backpressure**: if the writer is slow, `send().await` blocks the producers, naturally throttling the pipeline.
4. **Graceful shutdown**: `drop(write_tx)` is the shutdown signal. No special shutdown messages needed.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 问题 3：数据库锁争用

### 发生了什么

最初的 ChatPD 数据库访问模式使用全局 `Arc<Mutex<Connection>>`：

```rust
let db = DatabaseManager::new(&db_path)?;
let arc = db.connection();          // Arc<Mutex<Connection>>
let conn = arc.lock().unwrap();     // 每个查询都锁整个 DB
```

管道的每个部分 — fetcher、builder、LLM caller — 都需要连接来检查已有工作或写入结果。即使是只读查询也在同一 mutex 上争用。

### 为什么发生

这是"一把大锁"的反模式。它容易写（`Arc<Mutex<Everything>>`），对低并发能工作。但在一个有 200 并发 LLM caller 的管道中——每个都想检查论文是否已处理过——mutex 成为了瓶颈。

### 天真修复

读多写少的场景用 `RwLock` 代替 `Mutex`：

```rust
let db = DatabaseManager::new(&db_path)?;
let arc = db.connection();  // 现在是 Arc<RwLock<Connection>>
let conn = arc.read().unwrap();  // 共享读
```

这有帮助，但没有解决更深层的问题：SQLite 本身就会序列化写入。在 200 个 task 间共享一个连接从根本上就是浪费。

### 优雅方案：单所有者写入器

只有 DB writer task 需要连接。所有其他 task 通过 channel 发送数据给它。写入器独占连接 — 没有 Arc、没有 Mutex、没有锁。

```rust
use tokio::sync::mpsc;

enum WriteRecord {
    Success { arxiv_id: String, raw_response: String, parsed_json: Option<String>, ... },
    Error   { arxiv_id: String, status: ProcessingStatusType, notes: Option<String>, ... },
}

// DB 写入器拥有自己的连接。不需要锁。
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    conn.execute_batch("PRAGMA journal_mode=WAL;")?;  // 更好的并发读取

    let mut total = 0u64;
    let mut success_count = 0u64;

    while let Some(record) = rx.recv().await {
        let result = match record {
            WriteRecord::Success { ... } => {
                persist_production_write(&conn, ProductionWriteInput { ... })?;
                Ok(())
            }
            WriteRecord::Error { ... } => {
                persist_terminal_error_record(&conn, arxiv_id, status, ...)?;
                Ok(())
            }
        };

        match result {
            Ok(()) => success_count += 1,
            Err(e) => eprintln!("[DBWriter] 写入错误：{}", e),
        }

        if total % 100 == 0 {
            println!("[Pipeline] 已写入 {} 条记录（{} 成功），已用 {:?}",
                     total, success_count, start.elapsed());
        }
        total += 1;
    }

    // 无需显式关闭 — Connection 被 drop，SQLite WAL 被 checkpoint。
    StagePerfSummary { input_count: total as usize, output_count: success_count as usize, ... }
}
```

### 管道连接

```rust
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

let fetcher  = tokio::spawn(run_fetcher(..., write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(..., write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(..., write_tx.clone(), ...));
drop(write_tx);  // ← 关键：drop 主 sender，所有 task 完成后 channel 关闭

let db_writer = tokio::spawn(run_db_writer(write_rx, db_path));
```

所有三个上游阶段向同一个 `write_tx` 发送。DB writer 从 `write_rx` 接收。当所有上游阶段完成并 drop 它们的 sender 后，`write_rx.recv()` 返回 `None`，写入器自然退出。

### 为什么这是优雅的

1. **零锁争用**：写入器是连接的唯一所有者。
2. **单写入器 = SQLite 的理想状态**：SQLite 本来就会序列化写入。一个写入器避免了 SQLITE_BUSY。
3. **Channel 提供背压**：如果写入器慢，`send().await` 会阻塞生产者，自然地调节管道速率。
4. **优雅关机**：`drop(write_tx)` 就是关机信号。不需要特殊的关机消息。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## Problem 4: Fatal Error Broadcasting

### What Happened

One morning, the pipeline started running against a fresh batch of papers. After processing ~300 papers successfully, the LLM API key hit its quota. What happened next:

1. One LLM caller received HTTP 401 (quota exceeded).
2. That task stopped. **The other 199 tasks kept going.**
3. Each of the 199 tasks continued retrying — 199 requests × 3 retries each = 597 wasted API calls (which all failed with 401).
4. The pipeline appeared "stuck" for several minutes before giving up.

### Why It Happened

The error was detected locally, but there was no mechanism to tell the other tasks. It's the same problem as Problem 1 (no shared state) but for a fatal condition rather than a rate limit.

### The Elegant Solution: `AtomicBool` Abort Flag

One of the simplest concurrency primitives — used correctly — solved this completely:

```rust
use std::sync::atomic::{AtomicBool, Ordering};

let abort_flag = Arc::new(AtomicBool::new(false));

// ── In every LLM caller ──────────────────────────────────────────
tokio::spawn(async move {
    if abort_flag.load(Ordering::Relaxed) {
        return;  // someone already aborted — don't start new work
    }

    match call_llm_api(&request).await {
        Ok(response) => { /* process */ }
        Err(err_str) => {
            // Fatal: API quota exhausted. Signal ALL tasks to stop.
            if err_str.contains("401") || err_str.contains("quota") {
                eprintln!("FATAL: API quota exhausted. Aborting pipeline.");
                abort_flag.store(true, Ordering::Relaxed);
                return;
            }

            // Terminal but not fatal: write error record, continue.
            if let Some(status) = classify_error(&err_str) {
                write_tx.send(WriteRecord::Error { ... }).await;
                return;
            }

            // Transient: could be retried, but we skip in pipeline mode.
            transient_skipped.fetch_add(1, Ordering::Relaxed);
        }
    }
});

// ── In every OTHER worker (fetcher, builder) ─────────────────────
while let Some(item) = rx.recv().await {
    if abort_flag.load(Ordering::Relaxed) {
        return;  // stop processing, don't write error records
    }
    process(item).await;
}

// ── After all tasks join ─────────────────────────────────────────
if abort_flag.load(Ordering::Relaxed) {
    return Err("Pipeline aborted: API quota exhausted. Top up the key and re-run.".into());
}
```

### Three Error Categories

This pattern forced us to classify errors into three categories:

| Category | Example | Action |
|----------|---------|--------|
| **Transient** | 429, timeout, connection reset | Retry (or skip in pipeline mode) |
| **Terminal** | 404, no sections, parse failure | Write error record, continue |
| **Fatal** | 401, quota exceeded | Set abort flag, all tasks stop |

The key insight: **transient errors are the task's problem. Fatal errors are everyone's problem.**

### Why This Is Elegant

1. **One `AtomicBool`**: no channels, no complex shutdown protocol.
2. **Relaxed ordering** is sufficient: we don't need other state to be visible in a specific order — we just need to stop.
3. **Check at multiple points**: at the start of each work item, and in the error path of the LLM caller.
4. **Idempotent**: setting the flag twice is harmless.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 问题 4：致命错误广播

### 发生了什么

某天早上，管道开始处理一批新论文。在成功处理约 300 篇论文后，LLM API key 达到了 quota。接下来发生了什么：

1. 一个 LLM caller 收到 HTTP 401（quota 超出）。
2. 那个 task 停止了。**其他 199 个 task 继续运行。**
3. 199 个 task 中的每一个继续重试 — 199 个请求 × 每个 3 次重试 = 597 次浪费的 API 调用（全部以 401 失败）。
4. 管道看起来"卡住了"好几分钟才放弃。

### 为什么发生

错误被局部检测到了，但没有机制通知其他 task。这和问题 1（没有共享状态）是同一个问题，但针对的是致命条件而不是限流。

### 优雅方案：`AtomicBool` Abort Flag

最简单的并发原语之一 — 正确使用后完全解决了这个问题：

```rust
use std::sync::atomic::{AtomicBool, Ordering};

let abort_flag = Arc::new(AtomicBool::new(false));

// ── 在每个 LLM caller 中 ──────────────────────────────────────────
tokio::spawn(async move {
    if abort_flag.load(Ordering::Relaxed) {
        return;  // 有人已经中止了 — 不要开始新工作
    }

    match call_llm_api(&request).await {
        Ok(response) => { /* 处理 */ }
        Err(err_str) => {
            // 致命：API quota 耗尽。通知所有 task 停止。
            if err_str.contains("401") || err_str.contains("quota") {
                eprintln!("致命：API quota 耗尽。中止 pipeline。");
                abort_flag.store(true, Ordering::Relaxed);
                return;
            }

            // 终端但不致命：写错误记录，继续。
            if let Some(status) = classify_error(&err_str) {
                write_tx.send(WriteRecord::Error { ... }).await;
                return;
            }

            // 瞬时：可以重试，但在 pipeline 模式下跳过。
            transient_skipped.fetch_add(1, Ordering::Relaxed);
        }
    }
});

// ── 在每个其他 worker（fetcher、builder）中 ───────────────────────
while let Some(item) = rx.recv().await {
    if abort_flag.load(Ordering::Relaxed) {
        return;  // 停止处理，不写错误记录
    }
    process(item).await;
}

// ── 所有 task join 之后 ───────────────────────────────────────────
if abort_flag.load(Ordering::Relaxed) {
    return Err("Pipeline 中止：API quota 耗尽。充值 key 后重新运行。".into());
}
```

### 三类错误

这个模式迫使我们把错误分为三类：

| 类别 | 示例 | 动作 |
|------|------|------|
| **瞬时** | 429、timeout、连接重置 | 重试（或在 pipeline 模式下跳过） |
| **终端** | 404、无章节、解析失败 | 写错误记录，继续 |
| **致命** | 401、quota 超出 | 设置 abort flag，所有 task 停止 |

关键洞察：**瞬时错误是 task 自己的问题。致命错误是所有人的问题。**

### 为什么这是优雅的

1. **一个 `AtomicBool`**：不需要 channel，不需要复杂的关机协议。
2. **Relaxed 排序足够**：我们不需要其他状态以特定顺序可见 — 我们只需要停止。
3. **在多个点检查**：在每个工作项的开头和 LLM caller 的错误路径中。
4. **幂等**：设置 flag 两次是无害的。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## Problem 5: Graceful Shutdown

### What Happened

The pipeline has four concurrent stages running in separate `tokio::spawn` tasks, connected by three channels. When the work is done, everything needs to stop cleanly — no dropped writes, no hung tasks, no resource leaks.

### Why This Is Hard

The naive approach — just `abort()` all handles — loses in-flight work. The alternative — wait for all tasks to finish — risks hanging if one task blocks on a channel that will never receive.

### The Elegant Solution: Channel Drop Cascade + Abort Flag

Two mechanisms, each with a clear role:

**Mechanism 1: Channel Drop Cascade** — for normal completion.

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

// Spawn stages — each gets the sender for the NEXT stage.
let fetcher  = tokio::spawn(run_fetcher(paper_list, paper_tx, ...));
let builder  = tokio::spawn(run_builder(paper_rx, req_tx, ...));
let llm      = tokio::spawn(run_llm_caller(req_rx, write_tx.clone(), ...));
drop(write_tx);  // ← drop the "main" sender
let db_writer = tokio::spawn(run_db_writer(write_rx, db_path));

// Shutdown cascade:
// 1. Fetcher finishes → drops paper_tx
// 2. Builder sees paper_rx closed → finishes → drops req_tx
// 3. LLM caller sees req_rx closed → finishes → drops write_tx (clone)
// 4. DB writer sees write_rx closed → finishes
//
// Each stage's "while let Some(item) = rx.recv().await" loop
// naturally exits when the sender is dropped.
```

**Mechanism 2: Abort Flag** — for emergency stop.

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// In LLM caller: on 401/quota → abort_flag.store(true, Relaxed)
// In all other stages: if abort_flag.load(Relaxed) { return; }
// After all joins: if abort_flag.load(Relaxed) { return Err(...); }
```

### Why Two Mechanisms?

They serve different purposes that should not be conflated:

| | Channel Drop Cascade | Abort Flag |
|---|-----|-----|
| **Purpose** | Normal completion | Emergency stop |
| **Trigger** | Fetcher exhausts input | Quota exhausted, disk full |
| **Effect** | Stages drain naturally | Stages stop immediately |
| **Data loss** | None (all in-flight work drains) | Acceptable (in-flight work discarded) |
| **Exit code** | Success | Error |

Combining them into one mechanism would make both paths worse: normal shutdown would be abrupt (data loss), emergency stop would be slow (waiting for drain).

### The Complete Join Pattern

```rust
// Wait for all stages.
let fetch_perf = fetcher.await.map_err(|e| format!("fetcher panic: {}", e))?;
let build_perf = builder.await.map_err(|e| format!("builder panic: {}", e))?;
let llm_perf   = llm.await.map_err(|e| format!("llm panic: {}", e))?;
let db_perf    = db_writer.await.map_err(|e| format!("db writer panic: {}", e))?;

// Check for emergency stop.
if abort_flag.load(Ordering::Relaxed) {
    return Err("Pipeline aborted: API quota exhausted.".into());
}

// Normal completion: aggregate performance data.
Ok(PipelineSummary {
    throttled_fetch: throttled_count.load(Ordering::Relaxed),
    persisted_success: db_perf.output_count,
    persisted_terminal_failures: db_perf.terminal_count,
    perf: Some(PipelinePerfSummary { fetch: fetch_perf, build: build_perf,
                                     llm: llm_perf, db_write: db_perf, ... }),
})
```

### Why This Is Elegant

1. **Normal path is zero-overhead**: `drop(tx)` propagates naturally through the pipeline.
2. **Emergency path is immediate**: one `store(true, Relaxed)`, all tasks stop.
3. **No custom shutdown messages**: the channel primitives handle it.
4. **Testable**: you can test normal shutdown by providing finite input, and emergency shutdown by injecting a 401 error.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 问题 5：优雅停机

### 发生了什么

管道有四个并发阶段，运行在独立的 `tokio::spawn` task 中，通过三个 channel 连接。当工作完成时，所有东西都需要干净地停止 — 没有丢失的写入，没有挂起的 task，没有资源泄漏。

### 为什么这很难

天真方法 — 直接 `abort()` 所有 handle — 会丢失正在处理的工作。另一种方法 — 等待所有 task 完成 — 有可能挂起，如果某个 task 阻塞在一个永远不会收到数据的 channel 上。

### 优雅方案：Channel Drop 级联 + Abort Flag

两个机制，各有明确的角色：

**机制 1：Channel Drop 级联** — 用于正常完成。

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

// 创建各阶段 — 每个获得下一阶段的 sender。
let fetcher  = tokio::spawn(run_fetcher(paper_list, paper_tx, ...));
let builder  = tokio::spawn(run_builder(paper_rx, req_tx, ...));
let llm      = tokio::spawn(run_llm_caller(req_rx, write_tx.clone(), ...));
drop(write_tx);  // ← drop "主" sender
let db_writer = tokio::spawn(run_db_writer(write_rx, db_path));

// 关闭级联：
// 1. Fetcher 完成 → drop paper_tx
// 2. Builder 看到 paper_rx 关闭 → 完成 → drop req_tx
// 3. LLM caller 看到 req_rx 关闭 → 完成 → drop write_tx（clone）
// 4. DB writer 看到 write_rx 关闭 → 完成
//
// 每个阶段的 "while let Some(item) = rx.recv().await" 循环
// 在 sender 被 drop 时自然退出。
```

**机制 2：Abort Flag** — 用于紧急停止。

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// 在 LLM caller 中：遇到 401/quota → abort_flag.store(true, Relaxed)
// 在所有其他阶段：if abort_flag.load(Relaxed) { return; }
// 所有 join 之后：if abort_flag.load(Relaxed) { return Err(...); }
```

### 为什么需要两个机制？

它们服务于不应混淆的不同目的：

| | Channel Drop 级联 | Abort Flag |
|---|-----|-----|
| **目的** | 正常完成 | 紧急停止 |
| **触发** | Fetcher 耗尽了输入 | Quota 耗尽、磁盘满 |
| **效果** | 各阶段自然耗尽 | 各阶段立即停止 |
| **数据丢失** | 无（所有进行中的工作都会排空） | 可接受（进行中的工作被丢弃） |
| **退出码** | 成功 | 错误 |

将它们合并为一个机制会使两条路径都变差：正常关机会很突然（数据丢失），紧急停止会很慢（等待排空）。

### 完整的 Join 模式

```rust
// 等待所有阶段。
let fetch_perf = fetcher.await.map_err(|e| format!("fetcher panic: {}", e))?;
let build_perf = builder.await.map_err(|e| format!("builder panic: {}", e))?;
let llm_perf   = llm.await.map_err(|e| format!("llm panic: {}", e))?;
let db_perf    = db_writer.await.map_err(|e| format!("db writer panic: {}", e))?;

// 检查紧急停机。
if abort_flag.load(Ordering::Relaxed) {
    return Err("Pipeline 中止：API quota 耗尽。".into());
}

// 正常完成：汇总性能数据。
Ok(PipelineSummary {
    throttled_fetch: throttled_count.load(Ordering::Relaxed),
    persisted_success: db_perf.output_count,
    persisted_terminal_failures: db_perf.terminal_count,
    perf: Some(PipelinePerfSummary { fetch: fetch_perf, build: build_perf,
                                     llm: llm_perf, db_write: db_perf, ... }),
})
```

### 为什么这是优雅的

1. **正常路径零开销**：`drop(tx)` 自然地通过管道传播。
2. **紧急路径即时**：一个 `store(true, Relaxed)`，所有 task 停止。
3. **没有自定义关机消息**：channel 原语处理了它。
4. **可测试**：你可以提供有限输入来测试正常关机，注入 401 错误来测试紧急停机。

</div>

---

<div id="lang-en" class="lang-content" markdown="1">

## Summary: 10 Principles for Concurrent Rust in Production

These principles emerged from fixing real bugs across three Rust projects. They're not about the language — they're about how to think about concurrent systems.

| # | Principle | Anti-pattern |
|---|-----------|--------------|
| 1 | **External services need a global rate-limit gate** | Each task retries independently |
| 2 | **Measure capacity, don't assume it** | Hardcoded concurrency limits |
| 3 | **Parameterize concurrency via env vars** | Recompiling to change limits |
| 4 | **Single writer = ownership transfer, no lock** | `Arc<Mutex<Connection>>` |
| 5 | **Cold start: begin small, ramp on success** | Max concurrency from the start |
| 6 | **Retry = exponential backoff + random jitter** | Fixed sleep intervals |
| 7 | **Fatal errors use `AtomicBool` broadcast** | Errors detected locally, ignored globally |
| 8 | **Channel `drop` IS the completion signal** | Custom "done" messages |
| 9 | **Retry round concurrency decreases each round** | Same concurrency for all retries |
| 10 | **Record perf data for every concurrency decision** | "It feels faster" |

### The Tool Selection Guide

| When you need to... | Reach for |
|---------------------|-----------|
| Share a read-heavy value across tasks | `Arc<RwLock<T>>` |
| Share a simple flag/counter | `AtomicBool` / `AtomicUsize` |
| Pass data between stages | `mpsc::channel` |
| Control how many tasks run at once | `Semaphore` (adaptive) or `buffer_unordered(n)` (fixed) |
| Collect results from dynamic task set | `JoinSet` |
| Stop all tasks on fatal error | `AtomicBool` abort flag |
| Clean shutdown on normal completion | `drop(sender)` |

Rust gives you a small, sharp set of concurrency primitives. The elegance is not in the tool — it's in knowing which combination to use for which problem. I hope these five bugs and their solutions help you build that intuition.

---

*This series is based on production Rust code from [ChatPD](https://github.com/anjiexu-pku) (an LLM-powered arXiv paper analysis pipeline), [asterinas](https://github.com/asterinas/asterinas) (a Rust OS kernel), and [mcpr](https://github.com/TankTechnology) (an MCP protocol implementation). All code examples are simplified from real implementations. Thanks to Claude Code for the 184 coding sessions that helped surface these patterns.*

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

## 总结：生产级 Rust 并发的 10 条原则

这些原则来自修复三个 Rust 项目中真实 bug 的经验。它们不是关于语言的 — 而是关于如何思考并发系统。

| # | 原则 | 反模式 |
|---|------|--------|
| 1 | **外部服务调用需要全局限流闸门** | 每个 task 独立重试 |
| 2 | **测量容量，不要假设** | 硬编码并发限制 |
| 3 | **通过环境变量参数化并发度** | 重新编译才能改限制 |
| 4 | **单写入器 = 所有权传递，不需要锁** | `Arc<Mutex<Connection>>` |
| 5 | **冷启动：从小到大，成功后递增** | 一上来就打满并发 |
| 6 | **重试 = 指数退避 + 随机 jitter** | 固定 sleep 间隔 |
| 7 | **致命错误用 `AtomicBool` 广播** | 错误局部检测，全局忽略 |
| 8 | **Channel 的 `drop` 就是完成信号** | 自定义"完成"消息 |
| 9 | **重试轮次的并发度逐轮递减** | 所有重试用相同并发度 |
| 10 | **记录每个并发决策的性能数据** | "感觉快了" |

### 工具选择指南

| 当你需要... | 使用 |
|-------------|------|
| 跨 task 共享读多写少的值 | `Arc<RwLock<T>>` |
| 共享简单标志/计数器 | `AtomicBool` / `AtomicUsize` |
| 在阶段间传递数据 | `mpsc::channel` |
| 控制同时运行的 task 数量 | `Semaphore`（自适应）或 `buffer_unordered(n)`（固定） |
| 从动态 task 集合收集结果 | `JoinSet` |
| 致命错误时停止所有 task | `AtomicBool` abort flag |
| 正常完成时的优雅停机 | `drop(sender)` |

Rust 给你了一套小而锋利的并发原语。优雅不在于工具 — 而在于知道哪种组合用于哪种问题。希望这五个 bug 和它们的解决方案能帮助你建立这种直觉。

---

*本系列基于 [ChatPD](https://github.com/anjiexu-pku)（LLM 驱动的 arXiv 论文分析管道）、[asterinas](https://github.com/asterinas/asterinas)（Rust 操作系统内核）和 [mcpr](https://github.com/TankTechnology)（MCP 协议实现）的生产级 Rust 代码。所有代码示例均从真实实现简化而来。感谢 Claude Code 的 184 个编程会话帮助呈现这些模式。*

</div>

---
title: "Rust 并发笔记 (3)：五个真实 Bug 的优雅解法"
date: 2026-05-19
categories:
  - tech
tags:
  - rust
  - concurrency
  - systems-programming
  - production
excerpt: "Rust concurrency notes part 3: five real-world concurrency bugs and their elegant solutions—deadlocks, data races, and performance pathologies caught at compile time."
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

# Rust 并发笔记 (3)：五个真实 Bug 的优雅解法

[第一篇](/tech/rust-concurrency-1-foundation/) 讲了所有权、`Send`/`Sync`、`Arc` 和 `Result`。[第二篇](/tech/rust-concurrency-2-toolbox/) 填了并发工具箱。这篇走查五个在 ChatPD 生产环境里真实遇到的 bug——每个都会讲发生了什么、为什么会发生、天真的修复、以及最终起作用的方案。代码示例从实际运行的生产代码简化而来。

---

## 问题 1：429 级联风暴

### 发生了什么

pipeline 有 12 个并发的 fetcher，每个都从 ar5iv（一个 arXiv HTML 渲染服务）下载论文。某天 ar5iv 开始返回 HTTP 429（Too Many Requests）。接下来的事情：

1. 12 个 fetcher 同时收到 429
2. 每个独立启动指数退避计时器
3. 12 个计时器几乎同时到期
4. 12 个新请求同时发出 → 又 429
5. 循环重复，形成**自我强化的限流风暴**

### 为什么发生

每个 fetcher 独立运作，没有共享的限流状态。

```rust
// ❌ 各自为政——12 个 task 同时睡、同时醒、同时发请求
async fn fetch_with_retry(url: &str) -> Result<String> {
    for retry in 0..MAX_RETRIES {
        match client.get(url).send().await {
            Ok(r) => return r.text().await,
            Err(e) if e.contains("429") => {
                let ms = 500 * 2u64.pow(retry);
                sleep(Duration::from_millis(ms)).await;
                // 12 个 task 全在睡→全醒了→全发请求→全拿 429
            }
            Err(e) => return Err(e),
        }
    }
}
```

### 天真修复

加随机 jitter：

```rust
let jitter = rand::thread_rng().gen_range(0..=1000u64);
sleep(Duration::from_millis(ms + jitter)).await;
```

有帮助，但没解决根本问题：每个 task 还是不知道别人的 429。后面有 200 个 LLM caller 的时候，光靠 jitter 统计上不够可靠。

### 优雅方案：全局限流闸门

一个所有 fetcher 在发送前都检查的共享闸门。任何 fetcher 收到 429 就关上闸门一段冷却期。所有 fetcher 在闸门前等。

```rust
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// None = 闸门开着。Some(Instant) = 关到这个时候。
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

/// 收到 429 时调用。只延长、不缩短——处理并发 429 的竞态。
async fn set_rate_limit_cooldown(secs: u64) {
    let deadline = Instant::now() + Duration::from_secs(secs);
    let mut guard = RATE_LIMITED_UNTIL.write().await;
    if guard.map_or(true, |t| t < deadline) {
        *guard = Some(deadline);
    }
}

/// 每个请求发送前调用。闸门关着就等到开门。
async fn wait_for_rate_limit() {
    loop {
        let until = *RATE_LIMITED_UNTIL.read().await;
        match until {
            None => return,
            Some(t) if t <= Instant::now() => return,
            Some(t) => tokio::time::sleep(t - Instant::now()).await,
        }
    }
}
```

用起来就两行：

```rust
async fn fetch_with_retry(url: &str) -> Result<String> {
    for retry in 0..MAX_RETRIES {
        wait_for_rate_limit().await;  // ← 每次请求前检查

        match client.get(url).send().await {
            Ok(r) => return r.text().await,
            Err(e) if e.contains("429") => {
                set_rate_limit_cooldown(60).await;  // ← 关上闸门
                let ms = 500 * 2u64.pow(retry);
                let jitter = rand::thread_rng().gen_range(0..=1000u64);
                sleep(Duration::from_millis(ms + jitter)).await;
            }
            Err(e) => return Err(e),
        }
    }
}
```

### 为什么这个方案好

1. **每个请求只加一行**：`wait_for_rate_limit().await`
2. **读多写少，`RwLock` 正好**：常见情况下读路径无争用
3. **"只延长"逻辑防竞态**：两个 task 同时收到 429，不会互相缩短冷却期
4. **12 个 fetcher 还是 200 个 LLM caller 都一样**：闸门不管你有多少 task

### 修前 vs 修后

| | 修前 | 修后 |
|---|------|------|
| 重试 429 率 | 80%+ | <5% |
| 冷却后首次成功率 | ~15% | ~85% |
| 1000 篇论文耗时 | 45 分钟 | 12 分钟 |

---

## 问题 2：冷启动并发

### 发生了什么

有限流闸门之后不再制造风暴了，但效率还不够好。fetcher 一上来就开满 32 个并发槽。如果 ar5iv 当天容量偏低，第一波 32 个请求全拿 429，闸门关上，浪费一整轮。

### 为什么发生

假设配置的上限总是安全的。实际上外部服务容量随时间、服务器负载、部署状态波动。一上来就打满，等于在结冰路面上猛踩油门——极限是在被超过时才被发现的。

### 优雅方案：`Semaphore` 自适应并发

从 4 并发开始。每 24 次成功，多开一个槽——到上限为止。

```rust
use tokio::sync::Semaphore;
use std::sync::atomic::{AtomicUsize, Ordering};

let sem = Arc::new(Semaphore::new(4));    // 从 4 开始
let max = 32;
let cur = Arc::new(AtomicUsize::new(4));
let success = Arc::new(AtomicUsize::new(0));

for paper in papers {
    let permit = sem.clone().acquire_owned().await.unwrap();

    tokio::spawn(async move {
        if fetch(paper).await.is_ok() {
            let n = success.fetch_add(1, Ordering::Relaxed) + 1;
            if n % 24 == 0 {
                let c = cur.load(Ordering::Relaxed);
                if c < max {
                    cur.fetch_add(1, Ordering::Relaxed);
                    sem.add_permits(1);  // ← 动态扩容
                }
            }
        }
        drop(permit);
    });
}
```

只升不降。全局限流闸门（问题 1）处理退避，信号量只管容量发现。两个机制各管各的，不会互相打架。

### 重试轮次逐轮递减

瞬时错误失败的论文进入重试池，但每轮的并发量递减：

```rust
fn round_concurrency(cap: usize, round: usize) -> usize {
    (cap / (round + 1)).max(4).min(cap)
}
```

轮次之间等 90 秒让服务恢复。三轮后还拿不到的标记为 throttled，管道继续走。这样既给足重试机会，又不会无限循环。

```rust
for round in 0..3 {
    if round > 0 {
        let c = round_concurrency(32, round);
        tokio::time::sleep(Duration::from_secs(90)).await;
        futures::stream::iter(&pending)
            .map(|p| retry_fetch(p))
            .buffer_unordered(c)
            .for_each(|()| async {})
            .await;
    }
    // 收集仍然失败的，进入下一轮
}
```

### 为什么这个方案好

1. **发现容量**，不假设上限总是可达的
2. **关注点分离**：退避归闸门管，容量发现归信号量管
3. **重试轮次优雅降级**：越来越保守，不会死循环
4. **可观测**：`FetchPerfSummary` 记录了初始/最大并发、爬坡速率、重试轮次——发生了什么能看清楚

---

## 问题 3：DB 锁争用

### 发生了什么

ChatPD 最早的数据库访问模式是全局 `Arc<Mutex<Connection>>`。管道的每个部分——fetcher、builder、LLM caller——都要拿连接来查已有数据或写结果。连只读查询都在同一把 mutex 上排队。

### 为什么发生

这是"一把大锁"反模式。低并发时没事，但 200 个 LLM caller 都想查"这篇论文处理过没有"的时候，mutex 变成了瓶颈。

### 优雅方案：单所有者写入器

只有 DB writer task 需要连接。其他 task 通过 channel 发数据给它。写入器独占连接——没有 Arc，没有 Mutex。

```rust
enum WriteRecord {
    Success { arxiv_id: String, raw_response: String, parsed_json: Option<String>, ... },
    Error   { arxiv_id: String, status: ProcessingStatusType, ... },
}

// DB writer 自己是 Connection 的唯一所有者。零锁。
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    conn.execute_batch("PRAGMA journal_mode=WAL;")?;

    while let Some(record) = rx.recv().await {
        match record {
            WriteRecord::Success { ... } => persist_production_write(&conn, ...)?,
            WriteRecord::Error { ... }   => persist_terminal_error(&conn, ...)?,
        }
    }
    // Connection 在这里 drop，WAL 被 checkpoint
}
```

管道接线：

```rust
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

let fetcher  = tokio::spawn(run_fetcher(..., write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(..., write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(..., write_tx.clone(), ...));
drop(write_tx);  // ← 主 sender drop，上游全结束后 channel 关闭
let db_writer = tokio::spawn(run_db_writer(write_rx, db_path));
```

### 为什么这个方案好

1. **零锁争用**：写入器独占连接
2. **单一写入者 = SQLite 最舒服的状态**：SQLite 本来就会序列化写入，一个 writer 避免了 `SQLITE_BUSY`
3. **channel 提供背压**：写入器慢了，`send().await` 阻塞生产者，自然节流
4. **`drop(write_tx)` 就是关机信号**：不需要特殊的关机消息

---

## 问题 4：致命错误广播

### 发生了什么

早上管道开始跑一批新论文。处理了大约 300 篇之后，LLM API key 的 quota 耗尽了。接下来：

1. 一个 LLM caller 收到 HTTP 401
2. 那个 task 停了。**其他 199 个 task 还在跑。**
3. 199 个 task × 每人 3 次重试 = 597 次浪费的 API 调用（全以 401 失败）
4. 管道看起来"卡住了"好几分钟

### 为什么发生

错误被局部检测到了，但没机制告诉其他 task。这是问题 1（无共享状态）的同一个问题，只是这次是致命错误，不是限流。

### 优雅方案：`AtomicBool` Abort Flag

最简单的并发原语之一，正确用就完全解决问题：

```rust
use std::sync::atomic::{AtomicBool, Ordering};

let abort_flag = Arc::new(AtomicBool::new(false));

// ── 在每个 LLM caller 里 ─────────────────────────────────
tokio::spawn(async move {
    if abort_flag.load(Ordering::Relaxed) { return; }  // 有人已经中止了

    match call_llm(&request).await {
        Ok(r) => { /* 处理 */ }
        Err(e) => {
            // 致命：API quota 耗尽。通知所有 task 停。
            if e.contains("401") || e.contains("quota") {
                eprintln!("致命：API quota 耗尽，中止管道");
                abort_flag.store(true, Ordering::Relaxed);
                return;
            }
            // 终端但不致命：写错误记录，继续
            if let Some(status) = classify_error(&e) {
                write_tx.send(WriteRecord::Error { ... }).await;
                return;
            }
            // 瞬时：pipeline 模式下跳过
            transient_skipped.fetch_add(1, Ordering::Relaxed);
        }
    }
});

// ── 在其他 worker 里 ─────────────────────────────────────
while let Some(item) = rx.recv().await {
    if abort_flag.load(Ordering::Relaxed) { return; }
    process(item).await;
}

// ── 所有 task join 之后 ──────────────────────────────────
if abort_flag.load(Ordering::Relaxed) {
    return Err("管道中止：API quota 耗尽，充值后重试".into());
}
```

这个模式强制把错误分成三类：

| 类别 | 例子 | 动作 |
|------|------|------|
| 瞬时 (transient) | 429、timeout | 重试或跳过 |
| 终端 (terminal) | 404、解析失败 | 写错误记录，继续 |
| 致命 (fatal) | 401、quota 耗尽 | 设 abort flag，全部停 |

核心洞见：**瞬时错误是 task 自己的事。致命错误是所有人的事。**

### 为什么这个方案好

1. **一个 `AtomicBool`**：不需要 channel，不需要复杂关机协议
2. **`Relaxed` 排序足够**：不用别的状态配合，只求尽快停下来
3. **多点检查**：每个工作项开头 + LLM caller 的错误路径
4. **幂等**：设两次 flag 无害

---

## 问题 5：优雅停机

### 发生了什么

管道四个阶段跑在独立的 `tokio::spawn` 里，通过三个 channel 串起来。工作做完的时候，所有东西要干净地停下——不能丢数据、不能挂 task、不能泄漏资源。

### 为什么难

最天真的做法——直接 `abort()` 所有 handle——会丢掉正在处理的工作。另一个极端——等所有 task 自己完——有可能挂住，因为某个 task 可能在等一个永远不会来数据的 channel。

### 优雅方案：Channel Drop 级联 + Abort Flag

两个机制，各管各的事：

**机制 1：Channel Drop 级联（正常完成）**

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

let fetcher  = tokio::spawn(run_fetcher(input, paper_tx, write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(paper_rx, req_tx, write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(req_rx, write_tx.clone(), ...));
drop(write_tx);  // ← drop "主" sender
let db_writer = tokio::spawn(run_db_writer(write_rx, ...));

// 关机级联：
// 1. Fetcher 完成 → drop paper_tx
// 2. Builder 发现 paper_rx 关了 → 完成 → drop req_tx
// 3. LLM caller 发现 req_rx 关了 → 完成 → drop write_tx 的 clone
// 4. DB writer 发现 write_rx 关了 → 完成
//
// 每个阶段的 "while let Some(item) = rx.recv().await" 自然退出
```

**机制 2：Abort Flag（紧急停止）**

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// LLM caller 里：401/quota → abort_flag.store(true, Relaxed)
// 其他阶段：if abort_flag.load(Relaxed) { return; }
// Join 之后：if abort_flag.load(Relaxed) { return Err(...); }
```

### 为什么两个机制

它们服务不同的目的，不应混淆：

| | Channel Drop 级联 | Abort Flag |
|---|------------------|------------|
| 目的 | 正常完成 | 紧急停止 |
| 触发 | Fetcher 耗尽了输入 | Quota 耗尽、磁盘满 |
| 效果 | 阶段自然排空 | 立即停 |
| 数据丢失 | 无（进行中的工作都排空） | 可接受（丢弃进行中的工作） |
| 退出码 | 成功 | 错误 |

合并成一个机制会让两个路径都变差：正常关机会很粗暴（丢数据），紧急停止会很慢（等排空）。

### 完整的 Join 逻辑

```rust
let fetch_perf = fetcher.await.map_err(|e| format!("fetcher panic: {}", e))?;
let build_perf = builder.await.map_err(|e| format!("builder panic: {}", e))?;
let llm_perf   = llm.await.map_err(|e| format!("llm panic: {}", e))?;
let db_perf    = db_writer.await.map_err(|e| format!("db panic: {}", e))?;

if abort_flag.load(Ordering::Relaxed) {
    return Err("管道中止：API quota 耗尽".into());
}

Ok(PipelineSummary {
    throttled_fetch: throttled.load(Ordering::Relaxed),
    persisted_success: db_perf.output_count,
    perf: Some(PipelinePerfSummary { fetch: fetch_perf, build: build_perf,
                                     llm: llm_perf, db_write: db_perf, ... }),
})
```

### 为什么这个方案好

1. **正常路径几乎零开销**：`drop(tx)` 沿着管道自然传播
2. **紧急路径即时**：一个 `store(true, Relaxed)`，所有 task 停
3. **没有自定义关机消息**：channel 原语自己处理了
4. **可测试**：提供有限输入测正常关机，注入 401 错误测紧急停机

---

## 总结：十条从 Bug 中学到的原则

| # | 原则 | 反模式 |
|---|------|--------|
| 1 | 外部服务要有全局限流闸门 | 各自重试 |
| 2 | 测量容量，不要假设 | 硬编码并发上限 |
| 3 | 并发度通过环境变量可调 | 改代码重新编译 |
| 4 | 单写入器 = 传递所有权，不要锁 | `Arc<Mutex<Connection>>` |
| 5 | 冷启动：从小开始，成功后递增 | 上来就打满 |
| 6 | 重试 = 指数退避 + 随机 jitter | 固定间隔 sleep |
| 7 | 致命错误用 `AtomicBool` 广播 | 局部检测、全局忽略 |
| 8 | Channel 的 `drop` 就是完成信号 | 自定义"done"消息 |
| 9 | 重试轮次并发量逐轮递减 | 所有重试用相同并发 |
| 10 | 每个并发决策都记录性能数据 | "感觉快了" |

### 工具速查

| 场景 | 用什么 |
|------|--------|
| 跨 task 共享读多写少的值 | `Arc<RwLock<T>>` |
| 共享简单标志/计数器 | `AtomicBool` / `AtomicUsize` |
| 阶段间传数据 | `mpsc::channel` |
| 控制并发数量 | `Semaphore`（自适应）或 `buffer_unordered(n)`（固定） |
| 动态 task 集合收集结果 | `JoinSet` |
| 致命错误时全停 | `AtomicBool` abort flag |
| 正常完成时优雅关机 | `drop(sender)` |

Rust 给的并发原语不多，但够锋利。优雅不在于工具本身——在于知道哪种问题该用哪种组合。这五个 bug 和它们的解法，是我在 ChatPD 上踩出来的。

---

*本系列代码示例从 [ChatPD](https://github.com/anjiexu-pku)、[asterinas](https://github.com/asterinas/asterinas) 和 [mcpr](https://github.com/TankTechnology) 的生产 Rust 代码简化而来。感谢 Claude Code 协助梳理这些模式。*

</div>

<div id="lang-en" class="lang-content" style="display:none" markdown="1">

# Rust Concurrency Notes (3): Elegant Fixes for Five Real Bugs

[Part 1](/tech/rust-concurrency-1-foundation/) covered ownership, `Send`/`Sync`, `Arc`, and `Result`. [Part 2](/tech/rust-concurrency-2-toolbox/) filled in the concurrency toolbox. This post walks through five real bugs I encountered in ChatPD production. For each one, I describe what happened, why it happened, the naive fix, and the solution that actually worked. The code examples are simplified from production code.

---

## Problem 1: 429 Cascade Storm

### What Happened

The pipeline had 12 concurrent fetchers, each downloading papers from ar5iv, an arXiv HTML rendering service. One day ar5iv started returning HTTP 429, Too Many Requests. Then this happened:

1. All 12 fetchers received 429 at the same time.
2. Each fetcher started its own exponential backoff timer.
3. All 12 timers expired at almost the same moment.
4. All 12 sent new requests at once and received 429 again.
5. The loop repeated, creating a **self-reinforcing rate-limit storm**.

### Why It Happened

Each fetcher operated independently. There was no shared rate-limit state.

```rust
// Each task acts alone: 12 tasks sleep, wake, and retry together.
async fn fetch_with_retry(url: &str) -> Result<String> {
    for retry in 0..MAX_RETRIES {
        match client.get(url).send().await {
            Ok(r) => return r.text().await,
            Err(e) if e.contains("429") => {
                let ms = 500 * 2u64.pow(retry);
                sleep(Duration::from_millis(ms)).await;
                // all 12 sleep -> all wake -> all request -> all get 429
            }
            Err(e) => return Err(e),
        }
    }
}
```

### Naive Fix

Add random jitter:

```rust
let jitter = rand::thread_rng().gen_range(0..=1000u64);
sleep(Duration::from_millis(ms + jitter)).await;
```

This helps, but it does not fix the root cause: each task still has no idea that other tasks are also seeing 429. Once there are 200 LLM callers, jitter alone is not statistically reliable enough.

### Elegant Fix: A Global Rate-Limit Gate

Use one shared gate that every fetcher checks before sending a request. If any fetcher receives 429, it closes the gate for a cooldown period. All fetchers wait at the gate.

```rust
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// None means the gate is open. Some(Instant) means closed until that time.
static RATE_LIMITED_UNTIL: Lazy<Arc<RwLock<Option<Instant>>>> =
    Lazy::new(|| Arc::new(RwLock::new(None)));

/// Called after receiving 429. Only extends the cooldown, never shortens it.
async fn set_rate_limit_cooldown(secs: u64) {
    let deadline = Instant::now() + Duration::from_secs(secs);
    let mut guard = RATE_LIMITED_UNTIL.write().await;
    if guard.map_or(true, |t| t < deadline) {
        *guard = Some(deadline);
    }
}

/// Called before every request. If the gate is closed, wait until it opens.
async fn wait_for_rate_limit() {
    loop {
        let until = *RATE_LIMITED_UNTIL.read().await;
        match until {
            None => return,
            Some(t) if t <= Instant::now() => return,
            Some(t) => tokio::time::sleep(t - Instant::now()).await,
        }
    }
}
```

Using it takes two lines:

```rust
async fn fetch_with_retry(url: &str) -> Result<String> {
    for retry in 0..MAX_RETRIES {
        wait_for_rate_limit().await;  // check before every request

        match client.get(url).send().await {
            Ok(r) => return r.text().await,
            Err(e) if e.contains("429") => {
                set_rate_limit_cooldown(60).await;  // close the gate
                let ms = 500 * 2u64.pow(retry);
                let jitter = rand::thread_rng().gen_range(0..=1000u64);
                sleep(Duration::from_millis(ms + jitter)).await;
            }
            Err(e) => return Err(e),
        }
    }
}
```

### Why This Works

1. **One extra line per request:** `wait_for_rate_limit().await`
2. **Read-heavy state fits `RwLock`:** the common path is an uncontended read.
3. **Only extending the cooldown avoids races:** two tasks that receive 429 at the same time cannot shorten each other's cooldown.
4. **It scales from 12 fetchers to 200 LLM callers:** the gate does not care how many tasks exist.

### Before vs After

| | Before | After |
|---|--------|-------|
| 429 retry rate | 80%+ | <5% |
| First success after cooldown | ~15% | ~85% |
| Time for 1000 papers | 45 minutes | 12 minutes |

---

## Problem 2: Cold-Start Concurrency

### What Happened

After adding the rate-limit gate, the pipeline stopped creating storms, but it still was not efficient enough. The fetcher started immediately at the full 32 concurrency slots. If ar5iv's capacity was low that day, the first wave of 32 requests all got 429, the gate closed, and the whole round was wasted.

### Why It Happened

The code assumed the configured maximum was always safe. In reality, external service capacity changes with time, server load, and deployment state. Starting at full throttle is like stomping on the accelerator on an icy road: you only discover the limit after crossing it.

### Elegant Fix: Adaptive Concurrency with `Semaphore`

Start at 4-way concurrency. Every 24 successes, open one more slot until reaching the maximum.

```rust
use tokio::sync::Semaphore;
use std::sync::atomic::{AtomicUsize, Ordering};

let sem = Arc::new(Semaphore::new(4));    // start at 4
let max = 32;
let cur = Arc::new(AtomicUsize::new(4));
let success = Arc::new(AtomicUsize::new(0));

for paper in papers {
    let permit = sem.clone().acquire_owned().await.unwrap();

    tokio::spawn(async move {
        if fetch(paper).await.is_ok() {
            let n = success.fetch_add(1, Ordering::Relaxed) + 1;
            if n % 24 == 0 {
                let c = cur.load(Ordering::Relaxed);
                if c < max {
                    cur.fetch_add(1, Ordering::Relaxed);
                    sem.add_permits(1);  // dynamically expand capacity
                }
            }
        }
        drop(permit);
    });
}
```

The semaphore only increases. The global rate-limit gate from Problem 1 handles backoff. The semaphore handles capacity discovery. The two mechanisms do not fight each other.

### Retry Rounds with Decreasing Concurrency

Papers that fail with transient errors enter a retry pool, but each retry round uses lower concurrency:

```rust
fn round_concurrency(cap: usize, round: usize) -> usize {
    (cap / (round + 1)).max(4).min(cap)
}
```

Between rounds, the pipeline waits 90 seconds for the service to recover. After three rounds, papers that still fail are marked as throttled and the pipeline continues. This gives retries a fair chance without looping forever.

```rust
for round in 0..3 {
    if round > 0 {
        let c = round_concurrency(32, round);
        tokio::time::sleep(Duration::from_secs(90)).await;
        futures::stream::iter(&pending)
            .map(|p| retry_fetch(p))
            .buffer_unordered(c)
            .for_each(|()| async {})
            .await;
    }
    // collect remaining failures for the next round
}
```

### Why This Works

1. **Discover capacity instead of assuming it.**
2. **Separate concerns:** the gate handles backoff; the semaphore handles capacity discovery.
3. **Retry rounds degrade gracefully:** later retries are more conservative and cannot loop forever.
4. **Observable behavior:** `FetchPerfSummary` records initial/max concurrency, ramp rate, and retry rounds, so the system can explain what happened.

---

## Problem 3: DB Lock Contention

### What Happened

ChatPD's first database access pattern was a global `Arc<Mutex<Connection>>`. Every part of the pipeline, including fetcher, builder, and LLM caller, had to acquire the connection to check existing data or write results. Even read-only queries queued on the same mutex.

### Why It Happened

This is the "one big lock" anti-pattern. It works at low concurrency, but when 200 LLM callers all ask "has this paper already been processed?", the mutex becomes the bottleneck.

### Elegant Fix: A Single-Owner Writer

Only the DB writer task needs the connection. Other tasks send write records to it through a channel. The writer exclusively owns the connection: no `Arc`, no `Mutex`.

```rust
enum WriteRecord {
    Success { arxiv_id: String, raw_response: String, parsed_json: Option<String>, ... },
    Error   { arxiv_id: String, status: ProcessingStatusType, ... },
}

// The DB writer is the sole owner of Connection. Zero locks.
pub async fn run_db_writer(
    mut rx: mpsc::Receiver<WriteRecord>,
    db_path: String,
) -> StagePerfSummary {
    let conn = rusqlite::Connection::open(&db_path)?;
    conn.execute_batch("PRAGMA journal_mode=WAL;")?;

    while let Some(record) = rx.recv().await {
        match record {
            WriteRecord::Success { ... } => persist_production_write(&conn, ...)?,
            WriteRecord::Error { ... }   => persist_terminal_error(&conn, ...)?,
        }
    }
    // Connection drops here; WAL can be checkpointed.
}
```

Pipeline wiring:

```rust
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

let fetcher  = tokio::spawn(run_fetcher(..., write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(..., write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(..., write_tx.clone(), ...));
drop(write_tx);  // drop the main sender; channel closes after upstream finishes
let db_writer = tokio::spawn(run_db_writer(write_rx, db_path));
```

### Why This Works

1. **Zero lock contention:** the writer owns the connection.
2. **One writer is SQLite's happy path:** SQLite serializes writes anyway; one writer avoids `SQLITE_BUSY`.
3. **The channel provides backpressure:** if the writer is slow, `send().await` blocks producers naturally.
4. **`drop(write_tx)` is the shutdown signal:** no special shutdown message is needed.

---

## Problem 4: Fatal Error Broadcast

### What Happened

One morning the pipeline started processing a new batch of papers. After about 300 papers, the LLM API key ran out of quota. Then:

1. One LLM caller received HTTP 401.
2. That task stopped. **The other 199 tasks kept running.**
3. 199 tasks times 3 retries each produced 597 wasted API calls, all failing with 401.
4. The pipeline looked "stuck" for several minutes.

### Why It Happened

The error was detected locally, but there was no mechanism to tell the other tasks. This is the same shape as Problem 1, except the shared state is a fatal error rather than rate limiting.

### Elegant Fix: `AtomicBool` Abort Flag

One of the simplest concurrency primitives solves the problem completely when used correctly:

```rust
use std::sync::atomic::{AtomicBool, Ordering};

let abort_flag = Arc::new(AtomicBool::new(false));

// -- inside each LLM caller ------------------------------------------------
tokio::spawn(async move {
    if abort_flag.load(Ordering::Relaxed) { return; }  // someone already aborted

    match call_llm(&request).await {
        Ok(r) => { /* handle */ }
        Err(e) => {
            // Fatal: API quota exhausted. Tell every task to stop.
            if e.contains("401") || e.contains("quota") {
                eprintln!("fatal: API quota exhausted, aborting pipeline");
                abort_flag.store(true, Ordering::Relaxed);
                return;
            }
            // Terminal but non-fatal: write an error record and continue.
            if let Some(status) = classify_error(&e) {
                write_tx.send(WriteRecord::Error { ... }).await;
                return;
            }
            // Transient: skipped in pipeline mode.
            transient_skipped.fetch_add(1, Ordering::Relaxed);
        }
    }
});

// -- inside other workers --------------------------------------------------
while let Some(item) = rx.recv().await {
    if abort_flag.load(Ordering::Relaxed) { return; }
    process(item).await;
}

// -- after joining all tasks -----------------------------------------------
if abort_flag.load(Ordering::Relaxed) {
    return Err("pipeline aborted: API quota exhausted; retry after topping up".into());
}
```

This pattern forces errors into three categories:

| Category | Example | Action |
|----------|---------|--------|
| Transient | 429, timeout | Retry or skip |
| Terminal | 404, parse failure | Write an error record and continue |
| Fatal | 401, quota exhausted | Set abort flag and stop everything |

The core insight: **transient errors belong to one task; fatal errors belong to everyone.**

### Why This Works

1. **One `AtomicBool`:** no channel and no complex shutdown protocol.
2. **`Relaxed` ordering is enough:** the flag is not synchronized with other state; it only asks tasks to stop soon.
3. **Multiple checkpoints:** at the start of each work item and on the LLM caller error path.
4. **Idempotent:** setting the flag twice is harmless.

---

## Problem 5: Graceful Shutdown

### What Happened

The pipeline runs four stages in separate `tokio::spawn` tasks connected by three channels. When the work is done, everything needs to stop cleanly: no lost data, no hanging tasks, no leaked resources.

### Why This Is Hard

The naive approach, calling `abort()` on every handle, loses in-flight work. The opposite approach, waiting for every task to finish by itself, can hang forever if a task is waiting on a channel that will never receive another item.

### Elegant Fix: Channel Drop Cascade + Abort Flag

Use two mechanisms, each for its own purpose.

**Mechanism 1: Channel Drop Cascade for Normal Completion**

```rust
let (paper_tx, paper_rx) = mpsc::channel::<Paper>(cap);
let (req_tx, req_rx)     = mpsc::channel::<PaperRequest>(cap);
let (write_tx, write_rx) = mpsc::channel::<WriteRecord>(cap * 2 + 100);

let fetcher  = tokio::spawn(run_fetcher(input, paper_tx, write_tx.clone(), ...));
let builder  = tokio::spawn(run_builder(paper_rx, req_tx, write_tx.clone(), ...));
let llm      = tokio::spawn(run_llm_caller(req_rx, write_tx.clone(), ...));
drop(write_tx);  // drop the main sender
let db_writer = tokio::spawn(run_db_writer(write_rx, ...));

// Shutdown cascade:
// 1. Fetcher finishes -> drops paper_tx.
// 2. Builder sees paper_rx closed -> finishes -> drops req_tx.
// 3. LLM caller sees req_rx closed -> finishes -> drops its write_tx clone.
// 4. DB writer sees write_rx closed -> finishes.
//
// Each stage's "while let Some(item) = rx.recv().await" exits naturally.
```

**Mechanism 2: Abort Flag for Emergency Stop**

```rust
let abort_flag = Arc::new(AtomicBool::new(false));

// In the LLM caller: 401/quota -> abort_flag.store(true, Relaxed)
// In other stages: if abort_flag.load(Relaxed) { return; }
// After join: if abort_flag.load(Relaxed) { return Err(...); }
```

### Why Two Mechanisms

They serve different purposes and should not be merged:

| | Channel Drop Cascade | Abort Flag |
|---|----------------------|------------|
| Purpose | Normal completion | Emergency stop |
| Trigger | Fetcher exhausts input | Quota exhausted, disk full |
| Effect | Stages drain naturally | Stop immediately |
| Data loss | None; in-flight work drains | Acceptable; in-flight work is discarded |
| Exit code | Success | Error |

Merging these paths makes both worse: normal shutdown becomes too abrupt and loses data, while emergency shutdown becomes too slow because it waits for draining.

### Complete Join Logic

```rust
let fetch_perf = fetcher.await.map_err(|e| format!("fetcher panic: {}", e))?;
let build_perf = builder.await.map_err(|e| format!("builder panic: {}", e))?;
let llm_perf   = llm.await.map_err(|e| format!("llm panic: {}", e))?;
let db_perf    = db_writer.await.map_err(|e| format!("db panic: {}", e))?;

if abort_flag.load(Ordering::Relaxed) {
    return Err("pipeline aborted: API quota exhausted".into());
}

Ok(PipelineSummary {
    throttled_fetch: throttled.load(Ordering::Relaxed),
    persisted_success: db_perf.output_count,
    perf: Some(PipelinePerfSummary { fetch: fetch_perf, build: build_perf,
                                     llm: llm_perf, db_write: db_perf, ... }),
})
```

### Why This Works

1. **The normal path is almost zero-cost:** `drop(tx)` propagates naturally through the pipeline.
2. **The emergency path is immediate:** one `store(true, Relaxed)` tells every task to stop.
3. **No custom shutdown messages:** the channel primitives already encode completion.
4. **Testable:** provide finite input to test normal shutdown; inject a 401 to test emergency shutdown.

---

## Summary: Ten Principles Learned from Bugs

| # | Principle | Anti-pattern |
|---|-----------|--------------|
| 1 | Put a global rate-limit gate in front of external services | Independent retries |
| 2 | Measure capacity; do not assume it | Hard-coded concurrency ceiling |
| 3 | Make concurrency tunable through environment variables | Recompile after changing code |
| 4 | Single writer means ownership transfer, not locks | `Arc<Mutex<Connection>>` |
| 5 | Cold start: begin small and increase after success | Start at full throttle |
| 6 | Retry means exponential backoff plus random jitter | Fixed-interval sleep |
| 7 | Broadcast fatal errors with `AtomicBool` | Local detection, global ignorance |
| 8 | Dropping a channel sender is a completion signal | Custom "done" messages |
| 9 | Decrease concurrency across retry rounds | Same concurrency for every retry |
| 10 | Record performance data for every concurrency decision | "It feels faster" |

### Tool Cheat Sheet

| Scenario | Use |
|----------|-----|
| Share read-mostly state across tasks | `Arc<RwLock<T>>` |
| Share a simple flag or counter | `AtomicBool` / `AtomicUsize` |
| Pass data between stages | `mpsc::channel` |
| Control concurrency | `Semaphore` for adaptive, `buffer_unordered(n)` for fixed |
| Collect results from a dynamic task set | `JoinSet` |
| Stop everything after a fatal error | `AtomicBool` abort flag |
| Graceful shutdown after normal completion | `drop(sender)` |

Rust does not give you many concurrency primitives, but the ones it gives are sharp enough. Elegance is not in the tools themselves; it is in knowing which combination matches which problem. These five bugs, and their fixes, are lessons I learned by tripping over them in ChatPD.

---

*The code examples in this series are simplified from production Rust code in [ChatPD](https://github.com/anjiexu-pku), [asterinas](https://github.com/asterinas/asterinas), and [mcpr](https://github.com/TankTechnology). Thanks to Claude Code for helping organize these patterns.*

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

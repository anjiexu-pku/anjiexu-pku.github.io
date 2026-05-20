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

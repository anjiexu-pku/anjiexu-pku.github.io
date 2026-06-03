---
title: "Design Dimensions for Research Infrastructure"
date: 2026-05-20
categories:
  - tech
  - research
tags:
  - infrastructure
  - systems
  - research-methodology
  - opensource
excerpt: "Four research infrastructure projects, and what they taught me about failure recovery, data integrity, observability, system abstraction, and the mistakes I'd avoid starting over."
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

<div id="lang-en" class="lang-content" markdown="1">

# Design Dimensions for Research Infrastructure

Over the past few years I've built several pieces of research infrastructure. ChatPD—a data pipeline processing hundreds of thousands of arXiv papers. SkillFab—a platform for creating, reviewing, and publishing agent skills. multi-agent-topo—an experimental framework comparing multi-agent topologies across 500 SWE-bench instances. s2s—a tool that lets Claude Code autonomously explore open-source software and generate competency benchmarks.

These projects differ in scale, language, and audience. But building them surfaced the same set of problems: how do you keep a pipeline running after it crashes at hour 14? How do you know if 3% of your records silently corrupted? How do you max out concurrency without getting rate-limited into the ground?

Every insight here comes from a specific bug, incident, or near-miss.

---

## Failure Recovery: Slow Is Fine, Silent Is Not

Data pipelines eventually encounter every kind of failure. LLM APIs return 429. Source servers go down. PDFs turn out malformed halfway through. Networks hiccup.

ChatPD's core logic is simple: **distinguish "retrying might help" from "retrying won't change anything."**

```rust
fn classify_error(err: &PipelineError) -> Option<ProcessingStatus> {
    match err {
        // Transient: retry might succeed
        PipelineError::Http(429) | PipelineError::Timeout |
        PipelineError::ConnectionReset => None,

        // Terminal: retry is useless → record and skip permanently
        PipelineError::Http(404) =>
            Some(ProcessingStatus::SourceUnavailable),
        PipelineError::ParseError =>
            Some(ProcessingStatus::NoContent),

        // Quota exhausted → global abort, don't burn remaining budget
        PipelineError::Http(401) | PipelineError::QuotaExhausted => {
            abort_flag.store(true, Ordering::Relaxed);
            Some(ProcessingStatus::Aborted)
        }
    }
}
```

This classification came from a specific failure: an early version retried everything 3 times, wasting quota repeatedly hitting 404s that would never succeed.

Same lesson, different form: **checkpointing doesn't need a complex system.** ChatPD's resume logic is under ten lines—query completed paper IDs from the database at startup, skip them in the main loop. Combined with idempotent writes (`ON CONFLICT DO UPDATE`), the pipeline produces identical results no matter how many times it runs.

### Recovery Levels

Different projects need different recovery sophistication. Building enough of these taught me to match the level to the project rather than over-engineering:

- **Level 1 — Skip existing output.** `if os.path.exists(out): return`. One line.
- **Level 2 — Track processed IDs.** multi-agent-topo lives here—check which instance JSON outputs exist at startup.
- **Level 3 — Structured checkpoints.** ChatPD's `processing_status` table—knows not just whether something finished, but which stage and what outcome.
- **Level 4 — Auto-recovery strategy.** Escalate by failure type: transient → retry, persistent → rollback checkpoint, non-critical → log and skip, critical → pause.
- **Level 5 — Survive process death.** Checkpoints in DB, work items with leases, graceful shutdown on SIGTERM.

ChatPD runs at Level 4. multi-agent-topo and s2s at Level 2. No project has needed Level 5 yet.

---

## Efficiency: Find the Bottleneck First

Programs have exactly two bottleneck types: compute-bound or bandwidth-bound. Check IPC with `perf stat`—IPC > 2 and low cache misses → compute-bound, optimize the math. IPC < 1 and high cache misses → bandwidth-bound, reorganize the data. Optimizing the wrong one adds overhead with no gain.

Two simple laws prevent most guesswork on concurrency:

**Amdahl's Law**: 10% serial portion → infinite cores give 10× speedup at best. Shrinking the serial portion matters more than adding cores.

**Little's Law**: `concurrency = throughput × latency`. 2-second LLM calls, 50 req/s target → at least 100 concurrent workers. Derive `max_workers` from the formula, not intuition.

### Bounded Channel Pipelines

ChatPD chains four stages through three bounded mpsc channels. The key design: queues have caps. When DB writes slow down, upstream channels fill and backpressure propagates naturally—no unbounded memory growth. Each stage's concurrency is tuned independently because their bottlenecks differ: Fetch is I/O-bound, LLM calls are latency-bound, DB writes are disk-bound.

### Adaptive Concurrency

Starting at max concurrency gets you rate-limited immediately. ChatPD's Fetch stage begins at half the target and adds a slot every 32 successes. On 429, it ramps down and waits 90 seconds between rounds. The pipeline finds its own stable operating point rather than relying on a human-picked "safe" concurrency number that turns out to be either too conservative or too aggressive.

### Two Easy-to-Miss Details

**Reuse containers, don't rebuild.** multi-agent-topo's three experimental modes share one Docker container per instance, reset with `git reset --hard base_commit`. One build takes minutes; 500 instances without reuse wastes hours.

**Clean up zombie containers before starting.** Added after an hour-long debugging session:

```bash
docker ps -a --filter "name=sweb.eval" --format '{% raw %}{{.ID}}{% endraw %}' | xargs docker rm -f
```

---

## Data Integrity: The Scariest Bug Is the Silent One

The pipeline finishes. Everything looks fine. But 3% of records are missing fields, or a foreign key points to a nonexistent paper. These bugs don't surface immediately—they corrupt every downstream analysis built on top.

### Health Audits

ChatPD's `audit_health()` cross-checks every pipeline run with four SQL queries: orphan responses, request gaps, mismatched IDs, and papers stuck in PENDING or IN_PROGRESS. A `reconcile_month_against_metadata()` compares database records against arXiv metadata line by line—"processed 10,000 papers but metadata says there should be 10,023." Where did those 23 go?

These checks went in after discovering that a month's papers had silently lost 200 records to a fetch-stage silent failure. The source returned an incomplete list with no error. The health audit now catches this at pipeline completion.

### Golden Dataset Regression Tests

Maintain a small set of manually verified extraction results. Every pipeline code change reprocesses this batch and diffs against the golden dataset. Some diffs are expected (new fields). Some are bug fixes (previous parsing was wrong). Some make you stop—"why did 3% of records suddenly change?"

### The Schema Migration Lesson

ChatPD's database schema went through five major versions. The first flattened everything into one table, implicitly assuming "one paper → one dataset at most." Later discoveries—papers reference multiple datasets, datasets have citation relationships—broke the initial abstraction. Changing the schema meant changing all downstream read code, the golden dataset, and the health audit SQL.

The lesson came from the cost: **data model abstractions deserve the most design time because changing them has the highest cost in the entire system.**

---

## Observability: It's Running. Now What?

### Canary Pre-Checks

A full run takes days. A canary takes ten minutes. ChatPD samples equal numbers of papers from four major categories and runs the complete pipeline before committing to a full run. Only returns Go when all samples complete, no data gaps exist, and at least one succeeds.

This mechanism exists because of an incident: an 8-hour full run discovered that a prompt template formatting error had corrupted 80% of records. Eight hours of compute and API cost wasted. The canary went in immediately after.

The pattern generalizes: before a full run, test one or two units to measure per-unit time and extrapolate to full scale.

### The Rate Limiter "Death Spiral"

SkillFab's rate limiter distinguishes five dimensions, each independently limited. One implementation detail: rejected requests don't record timestamps.

The conventional approach records every request timestamp in a sliding window. But if a rate-limited user keeps retrying, those retries refresh the window, locking them out permanently. Not recording rejections avoids this death spiral. This bug was only discoverable by observing real traffic—test environments never generate authentic rate-limit retry patterns.

---

## System Abstraction: You Won't Get It Right the First Time

### Mechanism vs. Policy

ChatPD's extraction pipeline has a generic LLM extraction module. It takes a prompt template and a document, returns structured JSON. It knows nothing about datasets, papers, or citations.

```rust
async fn extract_with_llm(
    doc: &Document,
    prompt_template: &PromptTemplate,
    output_schema: &JsonSchema,
) -> Result<serde_json::Value> {
    let prompt = prompt_template.render(doc);
    let response = llm_client.complete(&prompt).await?;
    Ok(parse_json(&response, output_schema)?)
}
```

When we later needed to extract research methods (not datasets), we wrote one new prompt template and output schema. Zero changes to the mechanism code. When testing, the mechanism can be tested with fake templates; the policy can be tested with a mock LLM. Completely decoupled.

The boundary: **mechanism handles "how to call the LLM." Policy handles "what to ask it."**

s2s's filesystem protocol is the same idea concretized. Claude Code inside the container communicates with the host exclusively through the filesystem—JSON written to `/workspace/tasks/`, a watcher detects new files and acts. Zero network dependency, trivially debuggable, fully decoupled processes.

### An Abstraction That Didn't Work

multi-agent-topo's three experimental modes share one Docker container, resetting state with `git reset --hard base_commit`. The assumption: all three modes have identical environments, and git reset always produces a clean state.

In practice: files written outside `.gitignore` coverage, git reset failures from lock files, zombie processes holding file descriptors. We patched it with `git clean -fd` and process cleanup, but the fundamental problem remained: **state reset isn't fully guaranteed by git reset, and this abstraction promised something it couldn't deliver.**

### When to Abstract

SkillFab's early route handlers inlined database queries directly. The same query logic appeared in three different routes—fix one, miss the other two. This wasn't "abstraction done wrong"—it was no abstraction at all.

The later three-layer architecture (Route → TS Service → Rust Native) fixed this. But doing three layers from day one for a simple CRUD operation would have been equally stupid.

My practice now: **extract after you see the repetition.** First occurrence: inline. Second: tolerate. Third: extract. Fourth: congratulations, you have a battle-tested abstraction.

---

## Specific Mistakes I've Made

Everything above describes things that eventually worked. These didn't. Each has a concrete git commit behind it.

**Type-safety shortcuts became debt.** One `as any` takes 2 seconds to write. Fixing it can take 20 minutes—understanding context, defining correct types, confirming edge cases. After accumulating dozens, cleanup isn't linear.

**New API goes in, old API doesn't come out.** ChatPD's persistence layer went through three API evolutions. Each created a new interface without deleting the old one. SkillFab had the same pattern—"remove dead code" commits appeared five or six times. Nobody proactively says "this can be deleted."

**Cross-language naming conventions weren't settled upfront.** SkillFab's TS uses camelCase, Rust uses snake_case. At the napi boundary, neither was standardized. Settling it on day one costs nothing; deferring three months means touching every route.

**Config defaults that kept changing.** ChatPD's qwen db default path changed six times across six commits. Config options were added one at a time, each with its own read logic, with no documented precedence between them.

**Refactoring that broke backward compatibility.** Changing a discriminated union's structure without running "find all references" first. Downstream switch/case matching broke silently.

---

## What I Still Don't Have Good Answers For

**Agent evaluation infrastructure.** Evaluating a model = test set + metrics. Evaluating an agent = trajectories + intermediate decisions + environment stability. We're still evaluating agents with model-era methods—checking final accuracy while ignoring where the intermediate steps went wrong. Anthropic's [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) describes using an independent Evaluator agent with Playwright to test artifacts, which is more nuanced than pass/fail, but there's still distance from knowing *why* an agent made a wrong turn mid-execution.

**Dataset versioning.** ChatPD's output evolves over time. Downstream uses v1, upstream is at v3—how do you know whether to rerun? Currently solved with README version numbers. It's not enough.

**The "is this even worth it" moment.** ChatPD took months from first line to reliable output. Somewhere in the middle there's always a moment where you wonder whether this was a mistake. Anthropic's harness design post has an observation that applies here: harness components encode assumptions about model limitations that go stale as models improve. Every few months, re-examine which are load-bearing and which are dead weight. Same applies to infrastructure projects.

---

*Anthropic posts that shaped this thinking: [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents), [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps).*

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

# 科研基础设施的设计维度：从几个实际项目谈起

过去几年做了几个科研基础设施项目。

ChatPD 是一个处理几十万篇 arXiv 论文的数据管道。SkillFab 是一个 Agent Skill 的创建、审核和发布平台。multi-agent-topo 是一个在 500 个 SWE-bench 实例上对比多 Agent 拓扑结构的实验框架。s2s 是一个让 Claude Code 自主探索开源软件并生成教学任务集的小工具。

这些项目体量不同、语言不同。但在做的过程中反复碰到同一类问题：系统跑了十几个小时后崩溃了怎么续上？管道里几十万条数据有没有悄悄坏掉？并发拉满的同时怎么不被 API 限流打回来？

每个维度都来自具体的 bug、事故、或差点出事但没有出事的时刻。

---

## 容错：宁可慢，不能丢，不能悄悄坏

数据管道跑久了什么都会遇到。LLM API 偶尔 429、源站挂掉、PDF 解析到一半格式坏了、网络抖一下断开。

ChatPD 的核心逻辑很简单：**区分"重试之后可能成功"和"重试多少次都一样"的错误。**

```rust
fn classify_error(err: &PipelineError) -> Option<ProcessingStatus> {
    match err {
        // 瞬态：重试可能成功
        PipelineError::Http(429) | PipelineError::Timeout |
        PipelineError::ConnectionReset => None,

        // 终态：重试没用 → 写入 DB，永久跳过
        PipelineError::Http(404) =>
            Some(ProcessingStatus::SourceUnavailable),
        PipelineError::ParseError =>
            Some(ProcessingStatus::NoContent),

        // Quota 耗尽 → 触发全局终止，不逐个浪费
        PipelineError::Http(401) | PipelineError::QuotaExhausted => {
            abort_flag.store(true, Ordering::Relaxed);
            Some(ProcessingStatus::Aborted)
        }
    }
}
```

这个分类逻辑来自一个具体的教训：早期版本对所有错误统一重试 3 次，结果 pipeline 在遇到 404 的论文时浪费了大量配额反复重试一个永远不会成功的请求。

同样来自教训：**断点续传不需要复杂的 checkpoint 系统。** ChatPD 的启动逻辑只有不到十行——先从数据库查所有已完成的论文 ID，主循环里直接跳过。配合幂等写入（`ON CONFLICT DO UPDATE`），pipeline 跑多少次结果都一样。

### 中断恢复的层次

不同项目需要的恢复能力不一样。做多了之后，我形成了判断哪个项目该用哪个级别的直觉，而不是每个都做到最高：

- **Level 1 — 跳过已有输出。** `if os.path.exists(out): return`。一行代码。
- **Level 2 — 追踪已处理 ID。** multi-agent-topo 在这个级别——启动时检查 instance 的 JSON 输出是否已存在。
- **Level 3 — 结构化断点。** ChatPD 的 `processing_status` 表——不仅知道做完没做完，还知道做到哪一步、结果是什么。
- **Level 4 — 自动恢复策略。** 按失败类型升级处理：瞬态重试、持久失败回滚、非关键错误跳过、关键错误暂停。
- **Level 5 — 进程死亡也能恢复。** 检查点存 DB、工作项带租约、SIGTERM 优雅关闭。

ChatPD 做到了 Level 4。multi-agent-topo 和 s2s 在 Level 2 左右。还没有项目需要 Level 5。

---

## 效率：先搞清楚瓶颈在哪，再动手

程序只有两种瓶颈：算力受限或带宽受限。判断方法——`perf stat` 看 IPC（instructions per cycle）。IPC > 2 且 cache miss 低 → 算力受限，优化计算。IPC < 1 且 cache miss 高 → 带宽受限，优化数据搬运。用错方向的优化加开销不加收益。

两条简单的定律，避免了大量拍脑袋的并发数设定：

**Amdahl 定律**：10% 串行部分 → 无限多核最多加速 10 倍。缩小串行部分比加核重要。

**Little's Law**：`并发数 = 吞吐量 × 延迟`。LLM 调用耗时 2 秒、目标吞吐 50 req/s → 至少 100 个并发 worker。公式反推 `max_workers`，不看感觉。

### ChatPD 的有界通道流水线

四个阶段通过 3 条有界 mpsc channel 串联。关键设计：队列有上限。DB Write 慢了 → 前面 channel 满 → 上游自动被反压。不会有无限堆积内存的情况。每个阶段的并发度独立控制——Fetch 受限于 I/O，LLM Call 受限于 API 延迟，DB Write 受限于磁盘——独立调参。

### 自适应并发

直接拉满并发会被限流打回来。ChatPD 的 Fetch 阶段从目标并发的一半起步，每成功 32 次加一个槽位。碰到 429 后递减，轮次之间等 90 秒。让 pipeline 自己找到 API 能承受的稳定点，而不是人预设一个"安全的并发数"然后发现要么太保守要么太激进。

### 两个容易忽视的细节

**重用容器，不重建。** multi-agent-topo 里每个 instance 的三种实验模式共享同一个 Docker 容器，通过 `git reset --hard base_commit` 重置状态。一次 build 几分钟，500 个 instance 不重用就是几小时的浪费。

**清理僵尸容器。** 实验启动前记得清理上次跑崩留下的东西：

```bash
docker ps -a --filter "name=sweb.eval" --format '{% raw %}{{.ID}}{% endraw %}' | xargs docker rm -f
```

僵尸容器占着内存，不清掉新容器跑不起来。这行命令是某次 debug 一个小时后补上的。

---

## 数据完整性：最怕的不是跑崩，是悄悄坏

管道跑完了，看起来一切正常，但实际上有 3% 的记录丢了字段，或者某个外键指向了不存在的论文。这些问题不会立即暴露，但会让所有下游分析建立在错误数据上。

### 健康审计

ChatPD 的 `audit_health()` 用 4 个 SQL 查询交叉检查每一个 pipeline 运行的完整性：孤儿 response、请求缺口、不匹配的 ID、仍卡在 PENDING 或 IN_PROGRESS 的论文。还有一个 `reconcile_month_against_metadata()` 把数据库记录和 arXiv metadata 逐行比对——"处理了 10000 篇但 metadata 里实际有 10023 篇"，那 23 篇去哪了？

这些检查是某次发现"一个月的论文莫名其妙少了 200 篇"之后加的。原因是一个 fetch 阶段的 silent failure——源站返回了不完整的列表，但没有报错。加完健康审计后，这种问题会在 pipeline 结束时就暴露，而不是等下游分析出奇怪结果时才回去排查。

### Golden Dataset 回归测试

维护一小批人工验证过的正确提取结果。每次改 pipeline 代码，测试套件用新代码重新处理这批论文，把输出和 golden dataset diff。有些差异是预期内的（新增字段），有些是 bug 修复（之前解析错了），有些是让你停下来的——"为什么 3% 的记录突然变了？"

### Schema 迁移的教训

ChatPD 的数据库 schema 经历了 5 个大版本。第一版把所有字段平铺在一张表里，隐含假设是"每篇论文最多关联一个数据集"。后来发现一篇论文可以涉及多个数据集、数据集之间还有引用关系——初始抽象漏掉了关键概念。改 schema 意味着改所有下游的读取代码、改 golden dataset、改健康审计的 SQL。

教训来自代价：**数据模型的抽象最值得花时间，因为改它的成本是整个系统里最高的。**

---

## 可观测性：跑起来了，然后呢？

### Canary 预检

全量跑一次几天，canary 十分钟。ChatPD 在全量运行前从四个主要类别各采样等量论文跑完整 pipeline。只有所有采样完成、没有数据缺口、且至少有一条成功时，才返回 Go。

这个机制来自一次事故：全量跑了 8 小时后才发现 prompt 模板里有个格式错误，导致 80% 的记录解析失败。8 小时的算力和 API 费用白花了。Canary 就是那次之后加的。

同样的思路可以推广：跑全量之前，先跑一两个单元测出单次耗时，外推到全量。一个 5 秒的测量能防止给 10 小时的 job 设 10 分钟的超时。

### 限流器的"死亡螺旋"

SkillFab 的限流器区分了 5 种维度（注册、登录、邮件、token 创建、MCP 调用），每种独立限制。一个实现细节：被拒绝的请求不记录时间戳。

常规做法是在滑动窗口里记录每次请求的时间戳来计数。但如果用户被限流后不断重试，重试请求也在刷新时间窗口，导致被永久锁在外面。不记录拒绝请求的时间戳，避开了这个"死亡螺旋"。这个 bug 是上线后通过观测实际流量才发现的——测试环境永远不会产生真实的限流重试模式。

---

## 系统抽象：不是开始就能做对的

### 机制与策略分离

ChatPD 的提取管道有一个通用的 LLM 提取模块。它接受 prompt 模板和文档，返回结构化 JSON。对数据集、论文、引用一无所知。

```rust
async fn extract_with_llm(
    doc: &Document,
    prompt_template: &PromptTemplate,
    output_schema: &JsonSchema,
) -> Result<serde_json::Value> {
    let prompt = prompt_template.render(doc);
    let response = llm_client.complete(&prompt).await?;
    Ok(parse_json(&response, output_schema)?)
}
```

后来需要提取研究方法（不是数据集）时，只写了一个新的 prompt 模板和 output schema，机制代码一行没改。测试时，机制可以用假模板测试，策略可以用 mock LLM 测试——两侧完全解耦。

这个抽象的边界是：**机制负责"怎么调 LLM"，策略负责"调 LLM 做什么"。**

s2s 的文件系统协议是同一个思路的具体化。容器内的 Claude Code 和宿主机之间通过文件系统通信——JSON 写入 `/workspace/tasks/`，watcher 检测到新文件后执行操作。选择文件系统作为抽象边界的原因很简单：零网络依赖、调试直观（直接看文件内容）、进程完全解耦（一方崩溃不影响另一方）。

### 一个搞错了的抽象

multi-agent-topo 的三种实验模式共享同一个 Docker 容器，通过 git reset 重置状态。这个抽象的假设是"三种模式的实验环境完全一致，reset 总是能回到干净状态"。

实际跑起来有各种边界情况——容器里写了没被 `.gitignore` 覆盖的文件、git reset 因为 lock 文件失败、残留进程占用文件描述符。后来加了 `git clean -fd` 和进程清理，但根本问题是：**状态重置不是 git reset 能完全保证的，但这个抽象承诺了它做不到的事情。**

### 什么时候做抽象

SkillFab 早期在 TS 层的 route handler 里直接写数据库查询。同一个查询逻辑出现在三个不同的 route 里，改一处漏了另外两处。这不是"抽象错了"，而是没有抽象——本该分离的关注点混在了一起。

后来的三层架构（Route 层 → TS Service 层 → Rust Native 层）就是针对这个问题加上的。但反过来，如果项目第一天就设计三层架构，写个简单的 CRUD 也要跨三层，更蠢。

我现在的做法：**等看到重复模式再提取。** 第一次出现：内联。第二次出现：容忍。第三次出现：提取。第四次出现：恭喜，你有了一个经得起验证的抽象。

---

## 几个我犯过的具体错误

前面讲的都是最后做对了的东西。下面几个是没做对的。每个都有具体的 git commit 记录。

**类型安全的捷径变成债务。** 快速迭代时为了"先跑起来"，写了不少 `as any`。一个 `as any` 写的时候花 2 秒，修的时候可能要花 20 分钟——理解上下文、定义正确类型、确认边界情况。积累了几十个之后，清理成本就不是线性的。

**新 API 上线，旧 API 没删。** ChatPD 的持久化写入经历了三轮 API 演化，每一步创建了新接口但没有同步删除旧接口。SkillFab 同样——"remove dead code" 的 commit 出现了五六次。没有人主动说"这个可以删了"。加新东西有动力，删旧东西没动力。

**跨语言接口的命名契约没有先定。** SkillFab 的 TS 层用 camelCase，Rust 层用 snake_case。各自合理，但 napi 边界上没有统一。REST API 返回的 JSON 里字段名不一致。后来专门修了一次。这是那种"如果第一天就定了，一分钱不花；拖了三个月，每个 route 都要改"的问题。

**配置默认值反复横跳。** ChatPD 的 qwen db 默认路径在 6 个 commit 里改了 6 次。反映的不是一个 bug，而是一个设计没想清楚：默认路径从哪读、优先级是什么、命令行和配置文件冲突了以谁为准。配置项是逐个加的，不是一次性设计的。

**重构时破坏向后兼容性。** SkillFab Phase D3 重构中改了一个 discriminated union 的结构。下游代码依赖旧结构做 switch/case 匹配，全坏了。重构前花 30 秒跑一下 IDE 的 "find all references" 就能看到影响范围。跳过了这一步。

---

## 我仍然没有好的答案的问题

这些是反复碰到、还没找到好方案的问题。

**Agent 评估基础设施。** 评估模型 = 测试集 + 指标。评估 Agent = 轨迹 + 中间决策 + 环境稳定性。我们还在用模型时代的方法评估 Agent——只看最终正确率，不看在哪些中间步骤上坏了。Anthropic 在 [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) 里描述了他们用独立的 Evaluator agent 通过 Playwright 测试产物，这比只看 pass/fail 要细腻得多，但离"知道 Agent 为什么在某个中间步骤做错"还有距离。

**数据集版本化。** ChatPD 产出的数据集随时间演化。下游分析用的是 v1，上游到了 v3，怎么知道要不要重跑？目前靠 README 记版本号。

**基础设施的"不值得时刻"。** ChatPD 从开始写到稳定产出可靠数据花了几个月。中途有几个时刻会想"这玩意到底值不值得"。infra 最难的不是技术，是在看不到短期回报的时候坚持把它做完。Anthropic 的 harness design 文章有一条洞察我觉得适用于此：harness 组件编码了关于模型局限性的假设，这些假设会随着模型进步而过期。每过一段时间，需要重新审视哪些组件还承载重量、哪些已经是死重——对 infra 项目也一样适用。

---

*塑造这些思考的 Anthropic 文章：[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)、[Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)、[Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps)。*

</div>

<script>
function switchLang(lang) {
  document.querySelectorAll('.lang-content').forEach(function(el) {
    el.style.display = 'none';
  });
  document.getElementById('lang-' + lang).style.display = 'block';
  document.querySelectorAll('.lang-switch a').forEach(function(el) {
    el.classList.remove('active');
  });
  document.querySelector('.lang-switch a[href="#' + lang + '"]').classList.add('active');
}
</script>

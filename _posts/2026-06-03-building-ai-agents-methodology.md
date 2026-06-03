---
title: "How to Build AI Agents: Lessons from Five Projects"
date: 2026-06-03
categories:
  - tech
  - ai
tags:
  - AI
  - agent
  - methodology
  - software-engineering
  - systems
excerpt: "How much should I specify upfront, and how much should I let the agent figure out? Lessons from five agent projects, grounded in Anthropic's engineering philosophy."
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

# How to Build AI Agents: Lessons from Five Projects

Over the past year, I've built a series of AI agent systems. A multi-agent pipeline that fixes bugs in real codebases. A federated query engine that audits whether ML datasets are actually downloadable. A benchmark that measures how well agents can use unfamiliar command-line tools. A full research-agent operating system with memory consolidation and self-evolution.

Across these projects, one question came up again and again: **how much should I, the human builder, specify up front, and how much should I let the agent figure out?**

Anthropic's engineering team has been publishing some of the best thinking on this question. Their series of posts—from the foundational [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) (December 2024) through to the recent [Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps) (May 2026)—form what I think is the most coherent engineering philosophy for agent builders right now.

This post is my attempt to synthesize what I learned from their writing with what I learned from building. The projects I'll draw on are DataQuery (dataset accessibility auditing), multi-agent-topo (SWE-bench bug-fixing pipeline), s2s (agent capability benchmarking), OmniScientist/Helixforge (research agent OS), and ChatPD (paper-to-dataset extraction pipeline).

---

## The Core Framework: Agent = Model + Harness

The single most useful framing comes from Anthropic's harness design post: **an agent is the model plus the harness around it.** The harness is everything you build around the model—prompts, tools, context policies, sandboxes, feedback loops, recovery paths.

> *"A decent model with a great harness beats a great model with a bad harness."* — [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)

Every component in your harness encodes an assumption about what the model can't do on its own. Those assumptions go stale as models improve. Part of your job is to keep re-testing them.

When I first built the multi-agent-topo pipeline, my harness assumed the model needed a six-step workflow written into the system prompt: `ls` the directory, `grep` for keywords, `cat` the file, trace the logic, `sed -i` to edit, `git diff` to verify. This was me encoding my own debugging habits as a mandatory script. The model followed orders—even when a different approach would have been faster. It was, as Anthropic puts it, "grown more than it was built"—and I had over-built the wrong parts.

The rest of this post walks through the design principles I arrived at, organized around one fundamental idea: **find the simplest thing that works, then only add complexity when you can measure the improvement.**

---

## Principle 1: Start with a Single Call, Not an Agent

Anthropic's opening recommendation in [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) is unambiguous:

> *"Start by using LLM APIs directly. Many patterns can be implemented in a few lines of code."*

They introduce a distinction between **workflows** (LLMs orchestrated through predefined code paths) and **agents** (LLMs that dynamically direct their own process and tool usage). The advice: begin with a single, well-crafted LLM call. Add retrieval and in-context examples. Only graduate to multi-step agentic patterns when a simpler approach demonstrably fails.

In my projects, I've violated this principle more often than I'd like to admit. The multi-agent-topo pipeline started as an elaborate five-stage architecture—analysis agent, localization agent, challenge node, repair agent, verification—before I had validated that a single interactive agent loop with `bash` + `submit` tools could outperform the whole thing. When I finally ran the baseline experiment, the standalone mode (single agent with tools, no pipeline) achieved a **73% submit rate with 40.4 average turns**—while the challenge-injected pipeline hit only 50% submit with 50 turns.

The lesson: **before you build a pipeline, prove that a single agent can't do the job.**

---

## Principle 2: Prompt the Goal, Not the Recipe

This is the single change that had the largest impact across my projects.

Here is what my early agent prompt looked like:

```
1. Run ls /testbed to find relevant directories
2. Use grep -r "keyword" /testbed/ to search
3. Read files with cat /testbed/path/to/file.py
4. Trace the code logic
5. Edit with sed -i
6. Run git diff and submit
```

And here is the DataQuery auditor prompt, after I learned better:

```
Your task: determine whether an academic researcher can actually obtain
this data. The URL is a starting point, not the only path. Use your tools
and judgment.
```

The first version turns the agent into an executor. The second gives it a goal and trusts it to navigate. As Anthropic puts it in their context engineering post: every token depletes the model's "attention budget"—so make each one count [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents). A numbered workflow burns attention budget on instructions the agent doesn't need, while crowding out the context it actually needs to reason about the problem.

---

## Principle 3: Separate Execution from Verification

This is the architectural decision I'm most confident about, and it aligns directly with the Evaluator-Optimizer pattern Anthropic describes across multiple posts.

> *"Agents tend to respond by confidently praising their own work even when it is, to a human reviewer, mediocre at best. Separating the judging agent from the doing agent proved powerful."* — [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)

In DataQuery, the Auditor agent tries to access a dataset. The Verifier agent inspects the downloaded files. They are two completely independent Claude Code sessions. The Verifier never sees the Auditor's report. They share only raw artifacts—files on disk.

In our multi-agent-topo experiments, when we let the same agent re-examine its own output (the "self-reflection" pattern), the submission rate dropped from 73% to 50%. The agents became more hesitant after being challenged, spent more turns re-reading the same files, but did not produce better patches. Self-evaluation created the illusion of rigor without the substance.

A second lesson from Anthropic's harness post: the evaluator needs to be tuned to be **skeptical**. Not aggressive—skeptical. Their evaluator used four graded criteria (design quality, originality, craft, functionality) rather than asking "is this good?", which reliably produced rubber-stamp approvals. In DataQuery, we achieved the same effect with a V1–V4 verification taxonomy: file existence → format validation → content integrity → total size. Each check is a binary pass/fail, leaving no room for "looks fine to me."

---

## Principle 4: The Skill Library—Learn from Trajectories

Anthropic's [Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) post introduces a three-level progressive disclosure mechanism: metadata loaded at startup, full instructions loaded on task match, and bundled resources loaded on demand. Skills transform a general-purpose agent into a specialized one by packaging domain knowledge into composable, discoverable units.

DataQuery's Skill Library takes this idea one step further: **the skills are automatically extracted from the agent's own successful trajectories.**

Here is the loop:

1. **Extract** — After a successful dataset access, another LLM call analyzes the trajectory and extracts a reusable pattern. Crucially, we don't extract a script ("step 1: curl X, step 2: wget Y"). We extract a **cognitive model**: "GitHub repos are often just pointers; the actual data lives in Releases or on mirror sites like HuggingFace. Check there first."

2. **Consolidate** — When 5–10 trajectories from the same platform accumulate, a merge pass generalizes them. The prompt explicitly says: *"Do NOT write a checklist of curl/wget commands. Instead, teach a future agent HOW TO THINK about this platform."*

3. **Select** — On a new query, the system automatically matches the top-N highest-success-rate skills for the target platform. Skills with persistently low success rates are automatically deprecated—not by human judgment, but by statistical evidence.

4. **Bootstrap** — The initial skills are human-written decision trees with concrete evidence citations. Once the system is running, automated extraction takes over.

Anthropic notes that a future direction is enabling agents to "create, edit, and evaluate Skills on their own." DataQuery's extraction pipeline is a working prototype of exactly that.

---

## Principle 5: Schema Over Script

One of the subtler but most important distinctions: a **schema** describes what the output should look like. A **script** prescribes what the agent should do.

In DataQuery, the barrier taxonomy classifies access outcomes along three dimensions: R (reachability: R0–R2), I (interface: I0–I4), A (accessibility: A0–A4). It says: "When you report results, classify what happened using these dimensions." It does not say: "If you get a 404, then use wget with --mirror."

In earlier projects, I blurred this line. The MARC-DSL for robot coordination started as a communication schema—a vocabulary for expressing plans. Over time, it hardened into a script: robots couldn't express intentions the DSL didn't cover.

Anthropic's skills design follows the same principle. A SKILL.md provides methodology and reference material—not prescribed steps. The skill says "here's what we know about this domain and how to reason about it." The agent decides what to do with that knowledge.

> *"Give Claude necessary information but flexibility to adapt."* — Skill design tip from Anthropic's March 2026 update

---

## Principle 6: The Sprint Contract

Both s2s and DataQuery independently arrived at a pattern Anthropic formalizes as the **Sprint Contract**:

> *"Before each sprint the generator and evaluator negotiate a sprint contract: agreeing on what 'done' looks like for that chunk of work before any code was written."* — [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)

In DataQuery, the agent writes `plan.json` before acting: what approach it will try first, what barrier codes it expects to find. After execution, the system compares expectations to reality. A mismatch is recorded but doesn't trigger a retry—it's purely observational. Over time, systematic gaps (agent consistently expects R0 but gets R1) reveal that its cognitive model of a platform is wrong and needs updating.

This is different from runtime intervention—like multi-agent-topo's mid-session challenge injection. The Sprint Contract doesn't interrupt. It **observes** the gap between expectation and reality, then feeds that gap back into the learning loop for the next run.

---

## Principle 7: Deterministic Where Possible, LLM Where Necessary

Anthropic's post on harnessing Claude's intelligence makes a pointed recommendation: **"Use declarative tools for UX, observability, or security."** Promote actions to dedicated tools with typed arguments when you need interception, gating, rendering, or auditing. For everything else, let Claude use what it already knows—bash and a text editor.

DataQuery's verification pipeline follows the same split:

- **Rust layer** — Checks file existence, validates magic bytes (`\x89PNG`, `PK\x03\x04`, `\x1f\x8b`), detects HTML error pages masquerading as data files, verifies minimum download size. Deterministic, zero API cost, runs in milliseconds.
- **LLM layer** — A separate Verifier session judges whether the downloaded files "look like actual data." One prompt handles qualitative judgment that can't be reduced to if-statements.

The principle: never pay API tokens for something a deterministic check can do. Conversely, never hardcode thirty if-statements for something an LLM can judge in one prompt.

---

## Principle 8: Ask "What Can I Stop Doing?"

This is, to me, the most counterintuitive and important idea in Anthropic's engineering philosophy:

> *"Every component in your harness encodes an assumption about what the model can't do on its own. Those assumptions go stale as models improve."* — [Harnessing Claude's Intelligence](https://claude.com/de/blog/harnessing-claudes-intelligence)

Their concrete example: Claude Sonnet 4.5 exhibited "context anxiety"—rushing to finish when nearing the context limit. They built a context-reset mechanism to compensate. Claude Opus 4.5 largely eliminated that behavior on its own. The reset mechanism became dead weight. They removed it.

In my own projects, the multi-agent-topo pipeline still carries components I added for earlier, weaker models. The six-step workflow in the system prompt. The `_is_stuck()` function with its hand-tuned thresholds (5, 3, 15, 10, 6, 2). The challenge injection triggered by `confidence < 0.7`. Each of these was a reasonable response to a model limitation at the time. Many of them are now dead weight.

The discipline: after every model upgrade, re-baseline with the simplest possible harness. Remove anything that no longer moves the needle. Anthropic calls this "the harness doesn't shrink, it moves"—as old assumptions become obsolete, new ceilings unlock new scaffolding needs. But the direction of travel is always toward less, not more.

---

## The Five-Layer Framework

Bringing all of this together, here is how I think about what the human specifies versus what the agent decides:

| Layer | What It Is | Human Role | Agent Role |
|-------|-----------|------------|------------|
| **0: Hard Constraints** | Safety bounds, cost limits, infrastructure | Set absolute limits | Cannot override |
| **1: Goal & Success Criteria** | What to achieve, what "done" means | Define target and verification | How to get there |
| **2: Exploration Space** | Available tools and capabilities | Provide composable tools | Choose what, when, how |
| **3: Self-Awareness** | Agent's ability to assess its own state | Define what self-reflection looks like (schema) | Judge progress, confidence, completion |
| **4: Self-Evolution** | Learning from experience | Bootstrap initial knowledge, design the loop | Extract patterns, update models |

Most agent projects—including my own early ones—live at Layer 2, with humans inadvertently making Layer 3 decisions through hardcoded thresholds. The meta-skill of agent building is knowing, for each design decision, which layer it belongs in and whether you've placed it too low.

---

## Where to Start

If I were starting a new agent project tomorrow, here's what I'd do, ordered by impact-to-effort:

1. **Write the goal, not the steps.** Delete every numbered list from your system prompt. Replace with a target description and a definition of done.

2. **Run a baseline with a single agent call before building a pipeline.** In my experience, the single agent usually beats the pipeline on first attempt. Only add multi-step orchestration when you can measure the gap.

3. **Add an independent evaluator.** One session that sees only raw outputs, not the executor's reasoning. Make it pass/fail.

4. **Add a plan artifact.** Before execution, write expectations to a file. After execution, diff expectation against reality. Don't interrupt—just record. Feed the gaps back into the next run.

5. **Start a skill library.** Even a simple JSON file mapping platform → successful patterns. Feed it as context to future runs.

6. **After every model upgrade, prune.** Re-run the baseline without your harness components. Delete anything that no longer moves the needle.

---

*The projects this methodology is drawn from: DataQuery (federated dataset accessibility auditing), multi-agent-topo (multi-agent SWE-bench pipeline), s2s (agent capability benchmarking), OmniScientist/Helixforge (research agent OS), and ChatPD (paper-to-dataset extraction).*

*The Anthropic posts that shaped this thinking: [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents), [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [Equipping Agents for the Real World with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills), [Harnessing Claude's Intelligence](https://claude.com/de/blog/harnessing-claudes-intelligence), and [Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps).*

---

## Cite This Post

```bibtex
@misc{xu2026agent-methodology,
  author       = {Anjie Xu},
  title        = {How to Build {AI} Agents: Lessons from Five Projects},
  year         = {2026},
  month        = jun,
  howpublished = {\url{https://anjiexu-pku.github.io/tech/ai/building-ai-agents-methodology/}},
}
```

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

# 构建 AI Agent 的方法论：从五个项目谈起

过去一年，我做了好几个 AI Agent 系统。一个能在真实代码库里修 bug 的多智能体流水线。一个把互联网当成联邦数据库来查询数据集可获取性的审计引擎。一个衡量 Agent 使用陌生命令行工具能力的 benchmark。还有一个带记忆巩固和自我进化的完整研究 Agent 操作系统。

这些项目中反复出现同一个问题：**作为人类构建者，我该预先规定多少，又该让 Agent 自己决定多少？**

Anthropic 的工程团队就这个问题发表了近年来最好的几篇文章。从 2024 年 12 月的奠基之作 [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) 到 2026 年 5 月的 [Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps)，构成了一套我见过的最成体系的 Agent 工程哲学。

这篇文章是我把从他们那学到的，和从自己项目里踩坑踩出来的经验，放在一起的总结。涉及的项目：DataQuery（数据集可获取性审计）、multi-agent-topo（多智能体 SWE-bench 修 bug）、s2s（Agent 能力 benchmark）、OmniScientist/Helixforge（研究 Agent OS）、ChatPD（论文到数据集的提取管道）。

---

## 核心框架：Agent = 模型 + Harness

Anthropic harness 设计文章里最有用的一个公式：**Agent 是模型加上它外面那层 harness。** Harness 是你围绕模型构建的一切——prompts、tools、context policies、sandboxes、feedback loops、recovery paths。

> *"一个还不错的模型配上好的 harness，可以赢过一个很好的模型配上烂的 harness。"* —— [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)

Harness 里的每一个组件，都编码了一个关于"模型自己做不到什么"的假设。模型升级后，这些假设会过期。你的工作之一就是持续重新检验它们。

我刚做 multi-agent-topo 的时候，harness 里写死了一个六步工作流：`ls` 看目录 → `grep` 搜代码 → `cat` 读文件 → 追踪逻辑 → `sed -i` 编辑 → `git diff` 验证。这是把我自己的调试习惯编码成了强制脚本。模型乖乖照做——哪怕有更好的方法。这就是 Anthropic 说的"系统是长出来的，不是造出来的"——而我长错了方向。

这篇文章剩下的部分，围绕一个核心想法展开：**找到能工作的最简单方案，只有当你能够度量改进时才增加复杂度。**

---

## 原则一：从一个单次调用开始，不要一上来就建 Agent

Anthropic 在 [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) 里开门见山：

> *"从直接使用 LLM API 开始。很多模式几行代码就能实现。"*

他们区分了 **workflow**（通过预定义代码路径编排 LLM 和工具）和 **agent**（LLM 动态决定自己的流程和工具使用）。建议是：先从一个精心设计的单次 LLM 调用开始。加入检索和上下文示例。只有在简单方案确实不够的时候，才升级到多步 agent 模式。

我在自己的项目里违反这个原则的次数比愿意承认的多。multi-agent-topo 一上来就设计了五阶段架构——analysis agent、localization agent、challenge node、repair agent、verification——在还没验证单个交互式 agent loop 能不能干得更好之前。当终于跑完 baseline 实验，结果很清楚：**standalone 模式（单 agent + 工具，无 pipeline）提交率 73%，平均 40.4 轮**，而加了 challenge injection 的 pipeline 只有 50% 提交率和 50 轮。

教训：**在搭建流水线之前，先证明单个 agent 确实不够用。**

---

## 原则二：Prompt 里写目标，不写步骤

这是我所有项目里改动影响最大的一条。

早前我的 agent prompt 长这样：

```
1. 运行 ls /testbed 找到相关目录
2. 用 grep -r "keyword" /testbed/ 搜索
3. 用 cat /testbed/path/to/file.py 阅读文件
4. 追踪代码逻辑
5. 用 sed -i 编辑
6. git diff 并 submit
```

DataQuery 的 auditor prompt 后来是这样：

```
你的任务是：确定一个学术研究者是否真的能获取这个数据。
URL 只是入口，不是唯一路径。用你的工具和判断力。
```

第一个版本把 agent 变成了执行器。第二个给了它目标和信任。Anthropic 在 context engineering 文章里写得好：每个 token 都在消耗模型的"注意力预算"——所以每个 token 都得值 [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)。一个带编号的工作流在烧预算给 agent 不需要的指令，同时挤占了它推理问题真正需要的上下文。

---

## 原则三：执行与验证分离

这是我最确信的架构决策，跟 Anthropic 在多篇文章里描述的 Evaluator-Optimizer 模式完全一致。

> *"Agent 倾向于自信地赞美自己的工作，即使在人类审阅者看来最多算平庸。把评判 agent 和干活 agent 分开，被证明是非常有效的。"* —— [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)

在 DataQuery 里，Auditor agent 尝试访问数据集。Verifier agent 检查下载的文件。两个完全独立的 Claude Code session。Verifier 看不到 Auditor 的报告。它们共享的只有原始产物——磁盘上的文件。

multi-agent-topo 的实验证据直接支持这一条：当我们让同一个 agent 重新审视自己的输出（"自我反思"模式），提交率从 73% 降到了 50%。Agent 被质疑后变得更犹豫，多花了很多轮次重读同样的文件，但没有产出更好的补丁。自我评估制造了"严谨"的幻觉，却没有实质。

Anthropic harness 文章里的第二个教训：evaluator 需要被调教成**怀疑的**。不是激进的——是怀疑的。他们的 evaluator 用了四个可打分的维度（design quality, originality, craft, functionality），而不是问"这个好不好？"。DataQuery 里我们用了 V1-V4 验证分类来实现同样的效果：文件存在 → 格式验证 → 内容完整性 → 总大小。每一项检查都是二元的 pass/fail，不给"看起来还行"留空间。

---

## 原则四：Skill Library——从轨迹中学习

Anthropic 的 [Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) 引入了一个三级渐进式披露机制：元数据在启动时加载、完整指令在任务匹配时加载、附属资源按需加载。Skills 把通用 agent 变成专用 agent——把领域知识打包成可组合、可发现的单元。

DataQuery 的 Skill Library 在此基础上多走了一步：**skill 是从 agent 自己的成功轨迹中自动提取的。**

循环如下：

1. **提取**——一次成功的数据集访问后，另一个 LLM 调用分析这条轨迹，提取可复用模式。关键是我们不提取脚本（"步骤 1：curl X，步骤 2：wget Y"）。我们提取的是**认知模型**："GitHub repos 往往只是指针，真正的数据存在于 Releases 或 HuggingFace 等镜像站。先去那里找。"

2. **合并**——同一平台累积 5-10 条轨迹后，一个合并过程将它们泛化。提示词明确写：*"不要写 curl/wget 命令清单。教未来的 Agent 如何思考这个平台。"*

3. **选择**——新查询来时，系统自动匹配目标平台成功率最高的 top-N 个 skill。持续低成功率的 skill 被自动淘汰——不是靠人的判断，是靠统计证据。

4. **冷启动**——最初几个 skill 是手写的决策树，附具体证据引用。系统跑起来后，自动化提取接管。

Anthropic 提到未来方向是让 agent "自己创建、编辑和评估 Skills"。DataQuery 的提取流水线就是这个方向的一个工作原型。

---

## 原则五：Schema 而非 Script

一个更微妙但重要的区分：**Schema** 描述输出应该长什么样。**Script** 规定 agent 应该做什么。

DataQuery 的 barrier taxonomy 用三个维度分类访问结果：R（可达性：R0-R2）、I（接口：I0-I4）、A（可获取性：A0-A4）。它说："汇报结果时，用这些维度分类发生了什么。"它**没有**说："如果遇到 404，用 wget --mirror。"

在更早的项目里，我没分清这条线。机器人协作的 MARC-DSL 本应是通信 Schema——一套表达计划的词汇。但做着做着硬成了 Script：机器人不能表达 DSL 没覆盖的意图。

Anthropic 的 Skills 设计遵循完全相同的原则。SKILL.md 提供方法论和参考材料——不是规定步骤。Skill 说"这是我们关于这个领域已知的东西，以及怎么思考它"。Agent 自己决定怎么用这些知识。

> *"给 Claude 必要的信息，但保留适应灵活性。"* —— Anthropic 2026 年 3 月 Skill 设计建议

---

## 原则六：Sprint Contract

s2s 和 DataQuery 独立摸索出了一个 Anthropic 后来正式命名为 **Sprint Contract** 的模式：

> *"每个 sprint 开始前，generator 和 evaluator 协商一个 sprint contract：在写任何代码之前，就'做完'是什么意思达成一致。"* —— [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)

DataQuery 里 agent 在行动前写 `plan.json`：准备先试什么方法，预期得到什么 barrier code。执行后系统对比预期和现实。不匹配被记录但不触发重试——纯粹是观测数据。时间长了，系统性的偏差（agent 总是预期 R0 但实际得到 R1）揭示它对某个平台的认知模型错了，需要更新。

这和运行时干预不同——比如 multi-agent-topo 的 mid-session challenge injection。Sprint Contract 不中断执行。它**观察**预期与现实之间的差距，然后把这个差距反馈到学习循环里，用于下一次运行。

---

## 原则七：能确定的用代码，需判断的用 LLM

Anthropic 在 harnessing Claude's intelligence 文章里给出了一个精准的建议：**"用声明式工具做 UX、可观测性和安全边界。"** 当需要拦截、门控、渲染或审计时，把操作 promote 成有类型参数的专用工具。其他的，让 Claude 用他已经理解的东西——bash 和文本编辑器。

DataQuery 的验证流水线遵循同样的分工：

- **Rust 层**——检查文件存在、验证魔术字节（`\x89PNG`、`PK\x03\x04`、`\x1f\x8b`）、检测伪装成数据文件的 HTML 错误页、验证最低下载大小。确定性的，零 API 成本，毫秒级。
- **LLM 层**——独立的 Verifier session 判断下载的文件"看起来像不像真实数据"。一个 prompt 处理无法简化为 if 语句的定性判断。

原则：永远不要为确定性检查能做的事付 API token。反过来，永远不要为 LLM 一个 prompt 就能判断的事写三十个 if。

---

## 原则八：问自己"我可以停止做什么？"

这是我认为 Anthropic 工程哲学里最反直觉也最重要的一条：

> *"Harness 里的每一个组件都编码了一个关于模型自己做不到什么的假设。这些假设会随着模型进步而过期。"* —— [Harnessing Claude's Intelligence](https://claude.com/de/blog/harnessing-claudes-intelligence)

他们的具体例子：Claude Sonnet 4.5 有"context anxiety"——快到底了就想收工。他们为此建了一套 context-reset 机制。Claude Opus 4.5 基本上自己消除了这个问题。reset 机制变成死重。他们删了。

我自己的项目里，multi-agent-topo 仍然背着为更早期的、更弱的模型加上的组件。system prompt 里的六步工作流。手调阈值（5, 3, 15, 10, 6, 2）的 `_is_stuck()` 函数。`confidence < 0.7` 触发的 challenge injection。每一个在当时都是对模型局限性的合理回应。现在很多已经是死重。

纪律是：每次模型升级后，用最简单的 harness 重新跑 baseline。删掉任何不再产生可度量改进的东西。Anthropic 把这叫做"harness 不会缩小，它会迁移"——旧假设被淘汰，新天花板需要新脚手架。但迁移的方向永远是更少，不是更多。

---

## 五层框架

把以上全部放在一起，这是我现在思考"人规定什么 vs Agent 决定什么"的框架：

| 层级 | 是什么 | 人的角色 | Agent 的角色 |
|------|------|---------|------------|
| **0: 硬约束** | 安全边界、成本限制、基础设施 | 设定绝对上限 | 不可覆盖 |
| **1: 目标与成功标准** | 要达成什么、怎么算做完 | 定义目标和验证标准 | 怎么达成 |
| **2: 探索空间** | 可用工具和能力 | 提供可组合的工具 | 选择用什么、何时用、怎么用 |
| **3: 自我觉察** | Agent 评估自身状态的能力 | 定义自我反思长什么样（schema） | 判断进展、信心、完成度 |
| **4: 自我进化** | 从经验中学习 | 冷启动初始知识，设计学习循环 | 提取模式、更新模型 |

大多数 Agent 项目——包括我自己的早期项目——卡在 Layer 2，而人却通过硬编码的阈值和条件，无意中替 Agent 做了 Layer 3 的决策。构建 Agent 的元技能，就是知道每一个设计决策属于哪一层，以及你是否把它放得太低了。

---

## 从哪开始

如果我明天开始一个新的 Agent 项目，以下是我会做的事，按效果/投入比排序：

1. **写目标，不写步骤。** 把 system prompt 里每个带编号的列表删掉。换成目标描述和对"做完"的定义。

2. **在搭流水线之前，先用单次 agent 调用跑一遍 baseline。** 以我的经验，单 agent 通常在第一次尝试就优于流水线。只有在你能够度量差距时才加多步编排。

3. **加一个独立的 evaluator。** 一个只看原始输出、不看执行者推理的独立 session。让它给出 pass/fail。

4. **加一个 plan 产物。** 执行前把预期写入文件。执行后对比预期和现实。不要中断——只记录。把差距反馈到下一次运行。

5. **启动一个 skill library。** 哪怕是最简单的 JSON 文件，记录 platform → 成功模式映射。作为上下文反馈给未来的运行。

6. **每次模型升级后，剪枝。** 不带 harness 组件重新跑 baseline。删除任何不再产生可度量改进的东西。

---

*这套方法论来自以下项目：DataQuery（联邦数据集可获取性审计）、multi-agent-topo（多智能体 SWE-bench 流水线）、s2s（Agent 能力 benchmark）、OmniScientist/Helixforge（研究 Agent OS）、ChatPD（论文到数据集的提取管道）。*

*塑造这些思考的 Anthropic 文章：[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)、[Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)、[Equipping Agents for the Real World with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)、[Harnessing Claude's Intelligence](https://claude.com/de/blog/harnessing-claudes-intelligence)、[Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps)。*

---

## 引用本文

```bibtex
@misc{xu2026agent-methodology,
  author       = {Anjie Xu},
  title        = {构建 {AI} Agent 的方法论：从五个项目谈起},
  year         = {2026},
  month        = jun,
  howpublished = {\url{https://anjiexu-pku.github.io/tech/ai/building-ai-agents-methodology/}},
}
```

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

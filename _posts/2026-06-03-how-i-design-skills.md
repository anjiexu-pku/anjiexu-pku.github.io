---
title: "How I Design Claude Code Skills"
date: 2026-06-03
categories:
  - tech
  - ai
tags:
  - AI
  - claude-code
  - skill
  - methodology
  - software-engineering
excerpt: "A skill is crystallized consensus from repeated experience, not something designed in the abstract. Eight skills and what I learned about knowing what's worth putting in them."
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

# How I Design Claude Code Skills

Over the past six months I've built eight Claude Code skills—session analysis tools, Docker research patterns, a full system-building methodology. Two are public ([high-performance-coding](https://github.com/TankTechnology/high-performance-coding), [ai-session-analysis](https://github.com/TankTechnology/ai-session-analysis)); the rest live in a private repo and are loaded as project-local or global skills depending on scope.

I didn't set out to write eight skills. I built a series of systems—ChatPD, SkillFab, s2s, DataQuery, multi-agent-topo—and at some point noticed I was carrying the same hard-won patterns from one project to the next. Writing them down as skills was the natural endpoint of that process.

Anthropic published their [Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) post in October 2025, introducing a three-level progressive disclosure mechanism and framing skills as "organized folders of instructions, scripts, and resources that agents can discover and load dynamically." It's a strong technical specification. But there's a gap between the spec and the practice—between understanding the format and knowing what's worth putting in it. This post is about that gap.

---

## Skills Are Extracted, Not Designed

The single most important thing I've learned: **a skill is crystallized consensus from repeated experience. It comes after the builds, not before.**

I didn't design a system-building methodology in the abstract. I built ChatPD (a 270K-paper data pipeline with months of debugging), then SkillFab (an agent skill platform with its own operational surprises), then s2s (a benchmark that taught me about task design), then DataQuery (where the Skill Library pattern emerged). Only after the fourth project did I look back and notice: the same five phases kept appearing, the same failure modes kept recurring, the same checkpoint patterns kept being reinvented.

There's a rule I've come to trust: **don't extract a skill until you've seen the pattern in at least three projects.** The first time you see something, it might be a fluke. The second time, it might be coincidence. The third or fourth time, it's a pattern. System-building was extracted after ChatPD, SkillFab, s2s, and DataQuery. High-performance-coding came from profiling and optimizing pipelines across all four. Each skill encodes something that actually went wrong, repeatedly, across multiple systems—not something that *could* go wrong in theory.

Anthropic's skills post recommends the same approach from the evaluation side: "Run agents on representative tasks, identify gaps, build skills incrementally to address shortcomings." The principle works from both directions—whether you're extracting experience into a skill or testing a skill against real runs, the raw material is always actual failures, not anticipated ones.

---

## How I Structure a Skill

After writing enough of these, a structure emerged. Not because I planned it, but because every skill that worked well ended up having roughly the same shape:

**1. YAML frontmatter with bilingual triggers.** The `description` field is the skill's "if statement"—Claude uses it to decide whether to load the skill. Mine include both English and Chinese trigger phrases, because that's how I naturally speak about each topic in Claude Code. "我要搭一个XX系统" triggers system-building. "帮我研究一下" triggers research-gate. "断点续传" triggers high-performance-coding.

The skill body itself stays in English because Claude Code operates in English, but the trigger conditions match my actual speech patterns.

**2. A short "what this is for" section.** Two or three sentences. Not a manifesto. Enough to tell Claude (and future me) what problem this skill solves and when to reach for it.

**3. The anti-patterns table.** This is the most-read section of any skill. Nobody reads long-form guidance in the middle of work—they scan. The table is the scannable version of the entire skill.

Each entry has three columns: a **name** (memorable, specific—"Print-based logging," not "inadequate observability"), **what it looks like** (a realistic thought someone would actually have: *"It's just a prototype, I'll add tests later"*), and **what to do instead** (concrete, with cross-references: *"Phase 1 gates on tests. 'Later' never comes."*).

Five to ten entries. Each one something I've actually caught myself doing. This constraint is important—if an anti-pattern hasn't happened to me personally, I don't know enough about it to write a good entry.

**4. The main guidance.** This is where the skill earns its tokens. Specific, grounded in real code, organized by decision point rather than by topic. Not "here is everything about performance optimization"—that's a textbook. "When you notice X, reach for Y first" is what a skill should say.

**5. References to bundled resources.** Larger skills split detailed material into separate files loaded on demand: reference docs, code templates, checklists. Anthropic's progressive disclosure design makes this practical—Claude reads the skill body on match, then navigates into sub-files only when needed.

---

## Gates at the Right Places

Some decisions are too expensive to get wrong. For those, the skill blocks progress until a checklist completes.

What makes a decision worth gating? Three tests, discovered by getting all three wrong at different times:

- **The cost of being wrong is high.** Scaling to 5000 units without validating on 50 burned days of compute on an early ChatPD run.
- **The fix is cheap early, expensive late.** Adding structured logging on day one is trivial. Retrofitting it across 20 modules after the fact took an entire afternoon.
- **The decision gets skipped under time pressure.** "I'll add tests later" was the most reliable predictor of never adding tests, across every project I've built.

But—and this matters—**gates have to be rare.** If every section is a gate, the agent learns to treat all of them as optional. In system-building, four of five phases have gates. In research-gate, five checkpoints guard four phase transitions. The pattern held: each gate is at a genuinely irreversible decision point, and there are few enough of them that the agent takes each one seriously.

Anthropic's harness design post describes a related pattern they call the Sprint Contract: before writing code, the generator and evaluator negotiate exactly what "done" looks like. A gate is a Sprint Contract with teeth—it doesn't just record expectations, it refuses to proceed until they're met.

---

## Gates Produce Audit Trails

Every gate I design requires producing structured output. Not a form to fill out—a compact artifact that proves the gate was actually engaged with:

```
Phase 3 complete.
Bottleneck: serial regex matching across 270K records
Fix: compiled regex + chunked parallel processing
Speedup: 23x
Tests passing: all 47
```

Two purposes. First, it forces real thinking—you can't produce this output without having actually profiled and optimized. Second, it creates a record. Six months later, when I'm wondering why a particular architecture decision was made, the gate outputs are there, written at the moment of decision, not reconstructed from memory.

This is the same instinct behind DataQuery's `plan.json` and s2s's Sprint Contract verification. Before acting, write down what you expect. After acting, compare. The artifact bridges the gap between intention and outcome.

---

## Self-Contained Over Orchestrated

When given the choice between a skill that delegates to other skills and one that stands alone, I choose standalone. Always.

The reason is boring but empirically true across every skill I've built: delegation chains break silently. If skill A triggers skill B which triggers skill C, and B's conditions don't match the current context, the chain fails with no error message. The agent just doesn't do the thing.

Cross-reference is fine—"optionally use the ai-session-analysis skill to automate this step." But a skill should work without depending on other skills.

---

## What I'd Do Differently

Looking back at eight skills, a few patterns I wish I'd adopted earlier:

**Start with a shorter description field.** My early skills had description fields that tried to list every trigger condition. Claude is better at semantic matching than I gave it credit for—a concise description with 2–3 representative trigger phrases works better than an exhaustive list.

**Anti-patterns first.** In early skills, I buried the anti-patterns table in the middle. In later ones, it's always the first substantive section after the intro. When I'm mid-task and scanning, that's what I want to see. When Claude is mid-task and scanning, same thing.

**Prune after model upgrades.** Anthropic's harness design principle—"every component encodes an assumption about what the model can't do on its own"—applies to skills too. Some guidance that was essential for Claude 3.5 Sonnet became dead weight for Opus 4.5. After every major model release, I now re-read each skill and ask: does Claude still need to be told this?

---

## When Not to Write a Skill

Not everything deserves to be a skill. I've held off on writing one when:

- The pattern hasn't appeared across multiple projects. One project is an anecdote.
- The guidance is obvious to anyone with basic competence in the domain.
- I'm still figuring out the pattern myself. Let it stabilize.
- It would work better as a reference document or code template—a skill should encode methodology, not just information.

The bar is: can I point to a specific session or project where not having this skill caused a measurable failure? If I can't, the skill probably isn't ready.

---

## The Current Set

| Skill | Type | What triggers it | What it actually does |
|-------|------|-----------------|----------------------|
| [high-performance-coding](https://github.com/TankTechnology/high-performance-coding) | Global | "optimize", "断点续传", "make it faster" | Bottleneck-driven performance methodology distilled from profiling ChatPD, s2s, and DataQuery pipelines |
| [ai-session-analysis](https://github.com/TankTechnology/ai-session-analysis) | Global | "analyze my coding sessions", "what tools do I use most" | Zero-dependency Python scripts extracting tool usage patterns from Claude Code, Codex, and Kimi Code sessions |
| system-building | Global | "我要搭一个XX系统", "帮我构建一个平台" | Five-phase methodology: scaffolding with tests, test-first core, profiling-driven optimization, staged scale-up, retrospective |
| docker-research | Global | Docker, containers, docker-compose | Sandbox lifecycle patterns from s2s and DataQuery: build once, exec many; base64 command encoding; snapshot/restore |
| research-gate | Global | "帮我研究一下", "can we investigate", "I want to study" | Five checkpoints before committing compute: problem definition, scope validation, method selection, resource estimation, success criteria |
| session-audit | Global | "audit my sessions", "会话审计", "分析我的会话质量" | Seven semantic failure patterns extracted from analyzing 282 Claude Code sessions |
| software-to-skill | Project-local | "add a new software target" | CLI software → AI competency benchmark pipeline (s2s-specific) |
| curate-new-datasets | Project-local | "find new datasets" | ChatPD dataset discovery and deduplication pipeline |

---

*The Anthropic posts that shaped this thinking: [Equipping Agents for the Real World with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) (October 2025), [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) (December 2024), and [Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps) (May 2026).*

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

# 我是如何设计 Claude Code Skill 的

过去半年写了八个 Claude Code skill——会话分析工具、Docker 研究模式、系统构建方法论。其中两个公开在 GitHub（[high-performance-coding](https://github.com/TankTechnology/high-performance-coding)、[ai-session-analysis](https://github.com/TankTechnology/ai-session-analysis)），其余的放在私有仓库里按需加载。

我不是一开始就计划写八个 skill。我是先做了一串项目——ChatPD、SkillFab、s2s、DataQuery、multi-agent-topo——做到某个时候突然意识到，我在把同一套来之不易的模式从一个项目搬到另一个项目。把它们写成 skill，是这个过程自然的终点。

Anthropic 在 2025 年 10 月发布了 [Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)，提出了三级渐进式披露机制，把 skills 定义为"agent 可以动态发现和加载的指令、脚本和资源的文件夹"。它是一份扎实的技术规范。但在规范和实操之间有一个 gap——理解格式和知道什么值得往里写，是两件事。这篇文章聊的就是这个 gap。

---

## Skill 是提取出来的，不是设计出来的

我学到的最重要的一件事：**skill 是从重复经验中结晶出的共识。它产生在构建之后，不是之前。**

我没有凭空设计一套系统构建方法论。我先做了 ChatPD（一个 27 万篇论文的数据管道，踩了几个月的坑），然后 SkillFab（一个 agent skill 平台，带来了自己的运维意外），然后 s2s（一个让我学到任务设计方法的 benchmark），然后 DataQuery（Skill Library 模式在这里自然浮现）。做到第四个项目之后，我才回头看，发现：同样的五个阶段一直在出现，同样的失败模式一直在重复，同样的 checkpoint 模式一直被重新发明。

有一条我信任的规则：**不要在三个项目之前提取 skill。** 第一次出现可能是巧合。第二次可能是偶然。第三第四次，就是模式。System-building 是在 ChatPD、SkillFab、s2s 和 DataQuery 之后才提取的。High-performance-coding 来自对这几个项目的多条 pipeline 进行 profiling 和优化。每个 skill 编码的都是真实出过问题的事——反复地、跨多个系统——不是理论上可能出问题的事。

Anthropic 的 skills 文章从评估的角度给了相同的建议："先在代表性任务上跑 agent，找到差距，再逐步构建 skill 来填补这些不足。"从两边出发都能到达同一个原则——不管你是把经验提取成 skill，还是用真实运行来测试 skill，原材料永远是真实的失败，不是预想的失败。

---

## 我是怎么组织一个 Skill 的

写多了之后，一个结构自然浮现了。不是我规划的，而是每个好用的 skill 最后都长得差不多：

**1. YAML 元数据，带双语触发词。** `description` 字段是 skill 的"if 语句"——Claude 用它来决定是否加载。我的 description 里同时放中英文触发短语，因为这就是我在 Claude Code 里自然谈论每个话题的方式。"我要搭一个XX系统"触发 system-building。"帮我研究一下"触发 research-gate。"断点续传"触发 high-performance-coding。

Skill 正文用英文写（Claude Code 的运作语言），但触发条件得匹配我的实际说话方式。

**2. 一段"这是干什么用的"。** 两三句话。不是宣言。够让 Claude（和未来的我）知道这个 skill 解决什么问题、什么时候该用它。

**3. Anti-patterns 表。** 这是整个 skill 里被读得最多的部分。没人会在工作中间读长篇指导——大家都是扫读。这张表就是整个 skill 的可扫描版本。

每条三列：**名称**（好记、具体——"Print-based logging"，不是"可观测性不足"）、**长什么样**（某人真的会有的想法：*"就是个原型，后面再加测试"*）、**应该怎么做**（具体，带交叉引用：*"Phase 1 以测试为门禁条件。'后面'永远不会来。"*）。

五到十条。每一条都是我自己真的犯过的。这条约束很重要——如果一个 anti-pattern 我没亲自掉进过坑，我了解得不够，写不出好条目。

**4. 主体指导。** 这是 skill 挣回它消耗的 token 的地方。具体的、根植于真实代码的、按决策点而非主题组织的。不是"这是关于性能优化的一切"——那是教科书。"当你注意到 X 的时候，先试 Y"——这才是一个 skill 该说的。

**5. 引用附属资源。** 大一点的 skill 把详细材料拆到独立的文件里按需加载：参考文档、代码模板、检查清单。Anthropic 的渐进式披露设计让这件事变得实际——Claude 在匹配时读 skill body，只在需要时才往子文件里钻。

---

## 门禁设在正确的地方

有些决策错了太贵。对这些决策，skill 堵住进度，直到检查清单完成。

什么值得设门禁？三条检验标准，来自在不同时间把三条都搞错过：

- **错误的代价够高。** ChatPD 的早期运行中，没在 50 个样本上验证就扩展到 5000，烧了几天的算力。
- **早修便宜，晚修贵。** 第一天加结构化日志很简单。写完 20 个模块后补加，花了一整个下午。
- **时间压力下会被跳过。** "后面再加测试"是我做过的每个项目里，预测"永远不会加测试"最可靠的指标。

但——这点很重要——**门禁必须稀缺。** 如果每个 section 都是门禁，agent 会学会把所有的都当可选项。在 system-building 里，五个阶段中有四个有门禁。在 research-gate 里，五个检查点守卫四个阶段切换。模式是一致的：每个门禁都在一个真正不可逆的决策点上，数量够少，所以 agent 认真对待每一个。

Anthropic 的 harness design 文章描述了一个相关模式叫 Sprint Contract：在写代码之前，generator 和 evaluator 协商"做完"到底是什么意思。门禁就是带牙齿的 Sprint Contract——它不仅记录预期，而且拒绝继续，直到预期被满足。

---

## 门禁产生审计轨迹

我设计的每个门禁都要求产出结构化输出。不是要填表——是一个紧凑的产物，证明门禁真的被认真对待了：

```
Phase 3 complete.
Bottleneck: 27万条记录的串行正则匹配
Fix: 编译正则 + 分块并行处理
Speedup: 23x
Tests passing: all 47
```

两个目的。第一，它强制真正的思考——没真的 profiling 和优化过，产不出这个输出。第二，它创造了记录。六个月后我在想"为什么当时选了这套架构"的时候，门禁输出就在那里——写在决策的当下，不是事后重构的记忆。

这是跟 DataQuery 的 `plan.json` 和 s2s 的 Sprint Contract 验证一样的直觉。行动前写下预期。行动后对比。产物连接了意图和结果之间的缝隙。

---

## 自包含优于编排

在"skill 委托其他 skill"和"skill 独立运作"之间，我选独立。每次。

理由很无聊，但在我写过的每个 skill 上都经验性地成立：委托链会悄悄地断。如果 skill A 触发 skill B 触发 skill C，而 B 的条件在当前上下文里不匹配，链条失败，没有报错。agent 就是没做那件事。

交叉引用没问题——"可以选用 ai-session-analysis skill 来自动化这个步骤。"但一个 skill 应该不依赖其他 skill 就能工作。

---

## 如果能重来

回头看八个 skill，有几件事我希望早点知道：

**description 字段写短点。** 我早期的 skill 的 description 试图列出所有触发条件。Claude 的语义匹配能力比我给它的 credit 要强——一个简洁的 description 加 2-3 个代表性触发短语，比穷举列表好用。

**Anti-patterns 放前面。** 早期 skill 里我把 anti-patterns 表埋在中间。晚期 skill 里它永远是 intro 之后的第一个实质性 section。当我执行到一半在扫读时，我最想看它。当 Claude 执行到一半在扫读时，同样的东西。

**模型升级后剪枝。** Anthropic 的 harness design 原则——"每个组件都编码了一个关于模型自己做不到什么的假设"——对 skill 同样成立。有些对 Claude 3.5 Sonnet 非常必要的指导，到 Opus 4.5 就成了死重。现在每次大模型发布后，我会重读每个 skill 并问自己：Claude 还需要被告知这件事吗？

---

## 什么时候不写 Skill

不是所有东西都配做一个 skill。以下情况我会按住不写：

- 模式还没有跨多个项目出现。一个项目是 stories，不是 patterns。
- 指导内容对域内有基本能力的人来说显而易见。
- 我自己还在摸索模式。等它稳定。
- 更适合当参考文档或代码模板——skill 应该编码方法论，不是仅仅编码信息。

标准是：我能不能指向一个具体的 session 或项目，其中"没有这个 skill"造成了可度量的失败？如果不能，这个 skill 大概还没准备好。

---

## 目前的八个

| Skill | 类型 | 什么会触发它 | 它实际做什么 |
|-------|------|------------|------------|
| [high-performance-coding](https://github.com/TankTechnology/high-performance-coding) | 全局 | "optimize", "断点续传", "make it faster" | 从 ChatPD、s2s、DataQuery 多条 pipeline 的 profiling 中蒸馏出的瓶颈驱动性能方法论 |
| [ai-session-analysis](https://github.com/TankTechnology/ai-session-analysis) | 全局 | "analyze my coding sessions", "what tools do I use most" | 零依赖 Python 脚本，提取 Claude Code、Codex、Kimi Code 会话的工具使用模式 |
| system-building | 全局 | "我要搭一个XX系统", "帮我构建一个平台" | 五阶段方法论：带测试的脚手架、测试驱动核心开发、profiling 驱动优化、分阶段扩展、回顾总结 |
| docker-research | 全局 | Docker, containers, docker-compose | 来自 s2s 和 DataQuery 的沙箱生命周期模式：build once exec many、base64 命令编码、snapshot/restore |
| research-gate | 全局 | "帮我研究一下", "can we investigate", "I want to study" | 投入算力前的五道检查点：问题定义、范围验证、方法选择、资源估算、成功标准 |
| session-audit | 全局 | "audit my sessions", "会话审计", "分析我的会话质量" | 从分析 282 个 Claude Code 会话中提取的七种语义失败模式 |
| software-to-skill | 项目专属 | "add a new software target" | CLI 软件 → AI 能力基准 pipeline（s2s 专用） |
| curate-new-datasets | 项目专属 | "find new datasets" | ChatPD 数据集发现与去重 pipeline |

---

*塑造这些思考的 Anthropic 文章：[Equipping Agents for the Real World with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)（2025 年 10 月）、[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)（2024 年 12 月）、[Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps)（2026 年 5 月）。*

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

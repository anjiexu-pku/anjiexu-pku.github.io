---
title: "From Agent Mania to Research Automation: AI Breaking Through the Frontiers of Knowledge"
date: 2026-05-02
categories:
  - tech
  - ai
tags:
  - AI
  - deepseek
  - research
  - agent
  - software-engineering
excerpt: "Models are so powerful now that anyone can bring ideas to life. But what comes after agent mania? A reflection on data flywheels, distillation, and building AI that does research."
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

# From Agent Mania to Research Automation: AI Breaking Through the Frontiers of Knowledge

Ever since Openclaw came out, I've been meaning to write about all this — but it's taken me until now to actually sit down and do it.

Over the Chinese New Year, Openclaw exploded. For the first time, ordinary people viscerally felt the power of AI-assisted programming. But after the frenzy, things settled back down. At the start of the year, everyone was scrambling for API keys from Qwen, Zhipu, MiniMax. Then last month, Anthropic started banning accounts en masse. Now OpenAI is doing the same. Most people can't even get Plus or Pro subscriptions anymore.

Xiaomi poached Luo Fuli from DeepSeek and somehow shipped MiMo, catching up to the front line almost overnight. DeepSeek then dropped V4 — 1M context attention with insanely good `cache` hit rates. I'm hitting **98%** on my end, which is just ridiculous. I spent 60 RMB to run `Claude Code + DeepSeek-V4-Pro` hard for two days, and honestly, it felt almost on par with Claude 4.6 Sonnet.

There's another thing I find genuinely impressive: DeepSeek pulled off model inference at this scale using Huawei GPUs. I've talked to plenty of people doing model training, and they really don't like working with Huawei's hardware — the compatibility issues and pitfalls are endless. But DeepSeek made it happen anyway. It reminds me of that line from Xunzi they quoted:

> 不诱于誉，不恐于诽，率道而行，端然正己。
>
> Unswayed by praise, unafraid of slander, follow the path and hold yourself upright.

---

## The Data Flywheel Puzzle

I've always believed in the data flywheel. OpenAI and Anthropic are so strong precisely because they leverage massive user feedback to refine their models. That's why, among domestic players, I've always liked Kimi — they built Kimi Code, a channel to collect data at scale and feed it back into the model.

But DeepSeek puzzles me. DeepSeek-R1 is honestly not that strong on long-horizon coding tasks — very few people actually use it for serious, complex code development. Their data flywheel looks weak. So how are they still this good?

The more I think about it, the more the answer seems to be the same old recipe: **aggressively distill from Claude / GPT, combined with extremely strong RL**.

{: .notice--info}
The data flywheel isn't everything. Without massive user feedback, strong RL + high-quality distillation can still get you to the front line. For teams in China building foundation models, this might be more pragmatic than blindly chasing user volume.

---

## What's Next?

Models are now so powerful that any ordinary person can easily bring their ideas and code to life. GPT-5.6 is supposedly around the corner, and humanity keeps pushing the limits of scaling laws, intelligence ceilings, AI infra, and chip compute. But I'm not that excited about GPT-5.6 anymore — because the set of things that "only a smarter model can do" is shrinking. I wonder: is there something new?

Openclaw is great, but even with Peter reportedly shipping at a million lines of code per month, it still has massive unsolved problems. The memory mechanisms, in particular, remain terrible.

These technical issues will eventually get solved, I think. But I keep asking myself: where do we go next? Setting aside the "just scale more data" direction —

> **Can we switch to a different track entirely?**

---

## Let AI Do Research

I've been working on AI-automated scientific research — getting AI to explore science on its own. Research is fundamentally different from coding. Most of it involves extremely long-horizon tasks; you can't just set up a pipeline and let it run. AI currently can't autonomously complete research projects with that level of engineering complexity.

But that also means there are opportunities:

### 1. Build General-Purpose Research Platforms

Take VLM training as an example. Combine `Agent` workflows to prepare mainstream datasets, data cleaning methods, and training `baseline`s, with a solid codebase. Anyone who wants to optimize VLM algorithms later can build directly on top of it. It serves both human researchers tweaking code for papers and `Agent`s exploring research directions.

### 2. Identify Short-Horizon Research Tasks

Plenty of papers only change a few dozen lines of code, or swap in a different dataset — these are perfect for AI to tackle.

### 3. Strengthen AI's Long-Horizon Capabilities

There are several paths here: train better models, build `harness`es, optimize `skill`s, and decompose traditional research pipelines so AI can operate under controlled conditions on specific steps.

### 4. Let AI Tackle Theoretical Problems

Combine AI's growing capability in formal reasoning to break through certain problems from the theoretical side. Let AI pick up mathematical tools and attempt solutions. But my theoretical foundation is relatively weak — I can't yet see clearly what specifically can be done. The hardest part, really, is: **how do you find a problem worth solving?**

---

## What About the Real World?

This methodology, combined with AI's now-superhuman coding ability, can solve a lot through engineering alone. But is that enough?

In purely virtual domains (non-physical settings), strong engineering plus some algorithmic `trick`s can handle most research. But the moment you touch the real world, it gets messy.

The most direct example is **embodied intelligence**. Studying intelligent behavior in the physical world sounds cool but is painful in practice. Robotic arm calibration, sensor noise, environmental uncertainty — as soon as AI needs to interact with physical reality, it has to confront this chaos. In virtual environments you can restart and precisely reproduce everything; in the real world, a screw loosened by half a turn can ruin an entire experiment. There's no clear way out for automated research at this level.

Cross-disciplinary work is even harder. Beyond computer science, fields like mathematics (where AI + formal methods have been advancing fast), physics, chemistry, biology, materials — these disciplines are deeply tied to everyone's lives, yet AI's role remains severely limited. Biology and medicine are especially telling: data is highly siloed, and problems with paper fraud and reproducibility are rampant.

So is there a solution? My tentative idea is: **turn other disciplines into RL-trainable data environments wherever possible.**

Let's start with why math RL works: math problems have automatically verifiable answers, traceable steps, and clear right-or-wrong signals. Break it down: **state space × action space × reward function**. Models repeatedly sample, verify, and update policy — once the paradigm clicks, reasoning capability takes off.

Now consider biology. Wet-lab experiments don't have an automatic verifier, but here's the key insight: **not being able to auto-verify the final answer doesn't mean you can't do RL.** We can break the evaluation into multiple dimensions:

| Dimension           | Question                                                    |
| ------------------- | ----------------------------------------------------------- |
| **Feasibility**     | Are reagents, equipment, and procedures within constraints? |
| **Information Gain** | How much of the hypothesis space does this eliminate?      |
| **Cost**            | Time and consumable overhead                                |
| **Reproducibility** | Are steps standardized? Where are the noise sources?        |
| **Safety**          | Biosafety level, ethics compliance                          |

Any single dimension might be weak and noisy, but together they form a multi-objective `reward signal`. Combined with `PPO/GRPO`, that's enough to give the model an optimizable direction.

> Pipeline: AI proposes hypotheses → generates experimental plans in simulation → multi-dimensional `reward` scoring → `RL` iterative optimization → `top-k` plans handed to humans for execution → results fed back into the `reward model`.

Structurally, it's the same as math RL — the reward just shifts from `True/False` to a multi-dimensional weighted score. The real difficulties are: keeping the `reward model` dimensions orthogonal enough that the model can't `exploit` a loophole in one dimension to game the score, building the simulation environment, and the painfully long human feedback loop — each of these is a hard problem.

But this direction might be right: **turn unstructured disciplinary problems into structured tasks that can be multi-dimensionally scored and optimized through RL.**

---

## Closing Thoughts

Every time I read a top-tier technical report from a major lab, I feel a pang of envy, wishing my own work could have that kind of impact.

{: .notice--info}
Just a passing thought. Now it's back to the research trenches. May technology advance a little faster, and make everyone's lives a little better.

---

## Cite This Post

```bibtex
@misc{xu2026agent,
  author       = {Anjie Xu},
  title        = {From Agent Mania to Research Automation: {AI} Breaking Through the Frontiers of Knowledge},
  year         = {2026},
  month        = may,
  howpublished = {\url{https://anjiexu-pku.github.io/tech/ai/from-agent-mania-to-research-automation/}},
}
```

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

# 从Agent狂欢到科研自动化：AI 加速突破人类知识边界

Openclaw 出来那会，我就一直想写篇博客聊聊这些事，但拖到现在才动笔。

过年期间 Openclaw 爆火，普通人第一次直观感受到 AI 编程的强大。但狂欢过后，大家慢慢回归正常了。年初还在抢购千问、智谱、MiniMax 的 API，上个月 Anthropic 大面积封号，最近 OpenAI 也开始封号，大部分人都买不到 Plus 和 Pro 账号了。

小米从 DeepSeek 挖走了罗福莉，居然一下做出了 MiMo 模型，追到了一线水平。DeepSeek 紧接着发布了 V4，1M 超长上下文注意力，`cache` 命中率做得极强——我这边达到了 **98%**，太夸张了。我花了 60 块钱，用 `Claude Code + DeepSeek-V4-Pro` 深度跑了两天，感觉强度几乎追到了 Claude 4.6 Sonnet 的水平。

还有一件事让我挺佩服的——DeepSeek 用华为的卡跑起了这么大的模型推理。我跟不少做模型训练的同学聊过，他们其实很不乐意用华为的卡，兼容性和各种坑太多了。但 DeepSeek 硬是做出来了。这也正应了他们引用的那句荀子的话：

> 不诱于誉，不恐于诽，率道而行，端然正己。

---

## 数据飞轮的困惑

我一直相信数据飞轮。OpenAI 和 Anthropic 这么强，一定是靠大量用户反馈来优化模型的。所以国内厂商里，我最喜欢 Kimi，因为他们做了 Kimi Code，能通过这个渠道大量收集数据，反哺模型本身。

但 DeepSeek 让我有点困惑。DeepSeek-R1 在长程编程任务上的能力其实不够强，真正拿它来做复杂代码开发的人很少。那他们的数据飞轮明明很弱，为什么还能做到这么强？

想来想去，解法似乎还是那套——**大力蒸馏 Claude/GPT 的成果，加上超强的 `RL`**。

{: .notice--info}
数据飞轮并非万能。在没有海量用户反馈的情况下，靠强 RL + 高质量蒸馏，一样能追到一线水平。这对国内做基座模型的团队来说，可能比盲目堆用户量更务实。

---

## 然后呢？

模型现在已经强到这种程度了：任何一个普通人，都可以轻松完成一些代码和想法的实现。最近应该又要出 GPT-5.6 了，人类还在不断推进 `scaling law`、智能上限、AI infra、芯片算力的极限。但我对 GPT-5.6 没那么期待了——因为现在"只有更高智能的模型才能做的事"，其实变少了。我在想，有没有新一点的东西？

Openclaw 做得很好，但即便 Peter 以每个月百万行代码的速度在生产，Openclaw 仍然有大量问题没法解决。记忆机制那些，还是很糟糕。

这些技术问题，我觉得迟早能解决。但我一直在想，下一个阶段我们可以怎么推进？继续 scale 数据这种方向先不谈——

> **能不能换一个赛道来做？**

---

## 让 AI 去做科研

我自己在做 AI 自动化科研，也就是让 AI 自己去探索科研。科研和写代码不一样，大部分是超长程的任务，不是搭一个 pipeline 就能跑完的。AI 目前没法自主完成那种工程量很大的科研。

但这也就意味着，这里面有几个机会：

### 1. 搭建通用科研平台

比如 VLM 训练这个方向，结合 `Agent` 把主流数据集、数据清理方法、训练 `baseline` 都准备好，搭好代码库。后面的人想做 VLM 算法优化，直接基于这套代码库来做。既方便科研人员改代码发论文，也方便 `Agent` 做科研探索。

### 2. 筛选短程科研任务

很多论文只改了几十行代码，或者换了个数据集——这种就适合 AI 来冲。

### 3. 增强 AI 的长程能力

路子有这么几条：训模型、搭 `harness`、优化 `skill`、把传统科研 pipeline 拆开，让 AI 在部分步骤下受控操作。

### 4. 让 AI 碰理论问题

结合 AI 现在的形式化推导能力，从理论上突破某些问题。让 AI 拿起数学工具去尝试求解。但我理论水平比较薄弱，具体能做什么，我还看不太清楚。这里面最难的其实是——**如何找到一个有价值的问题**。

---

## 真实世界怎么办？

这套方法论，加上 AI 现在超强的代码能力，靠工程能力确实能解决不少问题。但这些就足够了吗？

在虚拟领域（非物理场景），靠极强的工程能力加一些算法 `trick`，能做大部分科研。但一旦涉及真实世界，就麻烦了。

最直接的例子是**具身智能**。研究智能在物理世界的行为，听起来很酷，做起来很痛苦。机械臂的调试、传感器噪声、环境的不确定性——只要 AI 需要接触物理世界，就必须面对这些混沌。虚拟环境你可以反复重启、精确复现，真实世界里一个螺丝松了半圈，整个实验可能就废了。自动化科研在这个层面的困难，还看不到清晰出路。

更麻烦的是跨学科。计算机之外，数学（AI + 形式化这几年发展很快）、物理、化学、生物、材料——这些学科跟每个人生活息息相关，但 AI 的作用始终很受限。生物和医学领域尤其典型，数据相当闭塞，论文造假和复现困难的问题很严重。

那这块有没有解法？我初步的想法是，把其他学科领域尽可能做成可以强化学习的数据环境。

先看为什么数学 RL 跑得通：数学题答案可自动验证，步骤有迹可循，正确与否黑白分明。拆开来看就是**状态空间 × 动作空间 × 奖励函数**，模型反复采样、验证、更新策略——范式一通，推理能力直接起飞。

回到生物。湿实验没有自动验证器，但关键观察是：**不能自动验证最终答案，不等于不能做 RL。** 我们可以把评分拆成多个维度：


| 维度       | 问题                     |
| -------- | ---------------------- |
| **可行性**  | 试剂、设备、操作是否在给定约束内       |
| **信息增益** | 做完能排除多少假设空间            |
| **成本**   | 时间与耗材开销                |
| **可复现性** | 步骤是否标准化，噪声源在哪          |
| **安全性**  | 生物安全等级、伦理合规            |


单个维度可能很弱、很嘈杂，但合在一起就构成了多目标 `reward signal`，配合 `PPO/GRPO` 足够给模型一个可优化的方向。

> 流程：AI 提假设 → 仿真中生成实验方案 → 多维 `reward` 打分 → `RL` 反复优化 → `top-k` 方案交人类执行 → 结果回灌 `reward model`。

本质上和数学 RL 一个结构，只是 reward 从 `True/False` 变成了多维度加权打分。真正的难点在于：`reward model` 各维度要足够正交，不能让模型 `exploit` 某一维漏洞来刷分。以及仿真环境怎么建、人类反馈闭环周期太长——每个都是硬骨头。

但这个方向可能是对的：**把非结构化的学科问题，转化成可以多维度打分、可以 RL 的结构化任务。**

---

## 写在最后

每次读到那些大厂发布的顶级技术报告，我都会心生羡慕，希望自己的工作也能有这么大的影响力。

{: .notice--info}
随口一言，接下来也要继续扎在科研里了。科技发展得快一点，让大家的生活好一点。

---

## 引用本文

```bibtex
@misc{xu2026agent,
  author       = {Anjie Xu},
  title        = {From Agent Mania to Research Automation: {AI} Breaking Through the Frontiers of Knowledge},
  year         = {2026},
  month        = may,
  howpublished = {\url{https://anjiexu-pku.github.io/tech/ai/from-agent-mania-to-research-automation/}},
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
  if (history.replaceState) {
    history.replaceState(null, '', '#' + lang);
  }
}
if (location.hash === '#zh') {
  switchLang('zh');
}
</script>

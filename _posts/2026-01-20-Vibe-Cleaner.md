---
title: "Vibe Code 之后 Vibe Clean：把“能跑”恢复为“可理解”"
date: 2026-01-20
categories:
  - tech
  - ai
tags:
  - python
  - ai
  - software-engineering
---

From Vibe Coder to Vibe Cleaner

# Vibe Code 之后 Vibe Clean：把“能跑”恢复为“可理解”

Date: 2026-01-20


## 0. 背景：AI 编程把“写功能”变得太容易，也把“写屎山”变得太容易

Cursor、Claude Code 这类 AI 编程工具，让落地一个功能变得很快：你描述需求，它就能补齐大量实现细节，代码很快“能跑”。

但现实也很明显：它同样把“把系统写乱”这件事变得更容易。尤其在 Python 这类动态语言里，这种趋势会更明显——因为 Python 的表达方式太自由了：

- 用 dict 传参几乎没有阻力
- 字段可以随时出现、随时缺失
- 同一个概念可以有很多别名
- 默认值和兜底随手就能加

而 AI 写代码时，最擅长的策略之一就是：用更多兼容、更强兜底来让它“现在能跑”。这在短期非常高效，但在长期会让系统越来越难维护。

对比一下 Rust 这类强类型语言，情况往往相反：你很难“先写一坨 dict”糊过去，因为编译器会逼着你回答一些问题：

- 这份数据到底长什么样（结构是什么）？
- 字段是必选还是可选？
- 数据会不会在流程中被修改？谁能修改？
- 错误是怎么表达的？

所以我越来越觉得，除了 vibe coder（快速把功能写出来），还需要 vibe cleaner：在 Python 这种“太容易糊过去”的环境里，把数据形状、不变量、失败语义重新写回代码。

## 1. 一个通用例子：LLM 工作流为什么会越写越厚？

设想你在写一个小型的 LLM 工作流，把用户问题变成答案。它拆成多个 step：

- Parse：解析输入（问题、用户信息、偏好）
- Retrieve（可选）：检索资料片段
- Generate：生成草稿答案
- Verify：校验/自检/格式检查
- Finalize：输出最终结构（正文、引用、置信度、错误信息）

为了方便（也为了让 AI 更好参与编码），接口通常会写成：

```python
async def step(request: dict) -> dict:
    ...
```

这在开始阶段很爽：灵活、迭代快、字段想加就加。但一旦功能叠加，你很快会遇到维护问题：数据在每一步到底长什么样？哪些字段一定存在？失败时返回什么结构？

如果这些问题没有明确答案，系统会开始变得“行为大致对，但难以解释；修改很危险，回归成本很高”。

## 2. 观察：Python + AI 很容易产出“到处解析 dict”的形态

在 Python 里，用 AI 加功能时，经常会出现下面这种模式：

```python
input_data = request.get("input", {})
ctx = request.get("ctx", {})
params = request.get("params", {})

question = (
    input_data.get("q")
    or input_data.get("question")
    or ctx.get("last_question")
    or ""
)

lang = params.get("lang") or ctx.get("lang") or "zh"
```

这种写法本质上是在做两件事：

- 让同一概念有多条来源路径（q / question / last_question …）
- 把优先级和默认策略埋进局部实现里（每个 step 都可能不同）

在动态语言里，这很容易“先跑起来”；在 AI 辅助下，它更容易被不断复制和扩张。结果就是：每次加功能，都会多一些“兼容分支”和“兜底”，系统越来越厚。

## 3. 归因：问题不只是 vibe coding，而是“语言允许你把不变量变成隐式”

这里要抓住关键：复杂度真正来自隐式不变量。

不变量指的是：系统要正确运行，有些约束必须稳定成立，比如：

- question 必须是非空字符串
- citations 是列表且每项必须带 url
- 失败必须带 error_code，否则上层无法做策略

在 Rust 里，你通常会被迫把这些写进类型里（`Option<T>`、`Result<T, E>`、结构体字段是否可选、借用/可变性）。在 Python 里，你完全可以不写——然后用 or ""、get(..., {})、try/except: pass 把它糊过去。

这就是重点：Python 允许你不回答“数据契约是什么”，也能继续写下去。而 AI 工具在“局部正确”的驱动下，天然倾向把这种糊法扩散到全局。

当结构信息不在代码里，而在读者脑内时，可理解性会随着功能增长快速下降。

## 4. 推论：为什么系统会走向“只加不复用”

这条链非常稳定：

- step 间用 dict → dict，字段可选、可变
- 新需求来了，最快办法是再兼容一种输入、再加一个兜底
- 兜底越多，字段语义越模糊（同义字段/别名字段/半成品字段并存）
- 语义越模糊，你越不敢复用已有模块（因为你不确定它依赖的 shape）
- 最后每次迭代都倾向于“再写一套能跑的分支”

结论很直接：系统变乱不是因为写得快，而是因为每次迭代都在增加不确定性。

## 5. Vibe cleaner：在 Python 里“补上 Rust 会逼你做的那部分”

如果把 Rust 的强类型理解成一种“强制提前决策”，那 vibe cleaner 在 Python 里做的，就是把这部分决策补回来：

- 数据结构是什么？
- 哪些字段必选、哪些可选？
- 哪些位置允许修改数据、哪些不允许？
- 错误如何表达，调用方如何处理？

下面是三条最通用的落地方式。

### 5.1 入口收敛：把 dict 解析集中到一个地方

目标：主流程不再到处 `.get()` 猜字段。你只在一个入口解析处处理别名/默认值/优先级。

```python
from dataclasses import dataclass
from typing import Optional, Any


@dataclass(frozen=True)
class StepRequest:
    question: str
    lang: str = "zh"
    user_id: Optional[str] = None
    raw: dict[str, Any] | None = None


def parse_request(request: dict) -> StepRequest:
    input_data = request.get("input", {})
    ctx = request.get("ctx", {})
    params = request.get("params", {})

    question = (
        input_data.get("q")
        or input_data.get("question")
        or ctx.get("last_question")
        or ""
    ).strip()

    lang = (params.get("lang") or ctx.get("lang") or "zh").strip()

    return StepRequest(
        question=question,
        lang=lang,
        user_id=ctx.get("user_id"),
        raw=request,
    )
```

这一步的价值很像 Rust：你至少在入口把“数据契约”集中表达了。

### 5.2 语义收敛：把“同一字段多种形态”变成唯一形态

比如 citations 有多种表示方式，那就做一次性规范化，让主流程只接触一种结构。

```python
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Citation:
    url: str
    title: str = ""
    snippet: str = ""


def normalize_citations(x: Any) -> list[Citation]:
    if not x:
        return []
    if isinstance(x, list) and x and isinstance(x[0], str):
        return [Citation(url=u) for u in x]
    if isinstance(x, list) and x and isinstance(x[0], dict):
        return [
            Citation(
                url=i.get("url", ""),
                title=i.get("title", ""),
                snippet=i.get("snippet", ""),
            )
            for i in x
        ]
    return []
```

这相当于在 Python 里人为制造一个“类型边界”。

### 5.3 错误语义固定：失败也要有结构

Rust 里的 Result<T, E> 会逼你显式处理失败；Python 里你很容易用空值/异常/字典标记混着来。清理的目标是：让失败语义固定下来。

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class StepResult:
    ok: bool
    data: dict
    error_code: str = ""
    error_message: str = ""


def ok(data: dict) -> StepResult:
    return StepResult(ok=True, data=data)


def fail(code: str, msg: str, data: dict | None = None) -> StepResult:
    return StepResult(
        ok=False,
        data=data or {},
        error_code=code,
        error_message=msg,
    )
```

这样调用方不需要通过“空不空”来猜，也不需要到处 try/except。

## 6. 验证：你真的变得更可维护了吗？

vibe cleaner 是否有效，可以用三个指标自检：

- 入口收敛：`request.get(...)` 这类解析逻辑是否基本只剩一个入口？
- 主流程分支减少：主流程里因为“形状不确定”产生的 if/elif 是否明显减少？
- 失败路径一致：失败是否总能用同一种结构表达？调用方是否不再靠空值推断？

这些指标衡量的是：读者需要脑补多少信息。脑补越少，维护就越便宜。

## 7. 结语：AI 让编码更快，但不会自动让系统更清晰

强类型语言靠编译器强迫你提前做决策，Python 的自由度 + AI 的“局部正确”倾向，会自然把系统推向“能跑但难懂”。

vibe cleaner 的意义就是：在你享受 vibe coding 带来的速度之后，补上那些“本来应该明确的数据契约”，把系统从不可维护的方向拉回来。

当然，如果要问，如果你一直说 Rust 这种语言好，你怎么写代码不用 Rust 啊？😭唉，Rust 也有 Rust 的烦恼，它写起来太复杂，我对 Rust 驾驭能力弱，而且最近这些 Agent 工具主要还是 Python 库多。

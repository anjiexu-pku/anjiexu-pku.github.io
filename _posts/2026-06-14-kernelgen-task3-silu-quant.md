---
title: "From SwiGLU Backward to INT8 Quantization: Notes from a KernelGen Challenge 9 Win"
date: 2026-06-14
categories:
  - tech
  - systems
tags:
  - GPU
  - Triton
  - KernelGen
  - Quantization
  - SwiGLU
  - MoE
excerpt: "A reconstruction of our KernelGen Challenge 9 optimization: starting from the SwiGLU backward formula, then walking through 128x128 tiling, fused INT8 quantization, memory bandwidth limits, and per-backend Triton engineering."
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
.kg-challenge-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin: 0 0 1.4em;
  padding: 0.9rem 1rem;
  border: 1px solid rgba(46, 101, 132, 0.22);
  border-left: 4px solid #2e6584;
  border-radius: 6px;
  background: #f7fbfd;
}
.kg-challenge-label {
  margin: 0 0 0.2rem;
  color: #2e6584;
  font-size: 0.78em;
  font-weight: 700;
  text-transform: uppercase;
}
.kg-challenge-desc {
  margin: 0;
  color: #555;
  font-size: 0.92em;
  line-height: 1.45;
}
.kg-challenge-url {
  color: #2e6584;
  overflow-wrap: anywhere;
}
.kg-challenge-button {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 2.25rem;
  padding: 0.45rem 0.8rem;
  border-radius: 4px;
  background: #2e6584;
  color: #fff !important;
  font-size: 0.88em;
  font-weight: 700;
  text-decoration: none;
  white-space: nowrap;
}
.page__content .kg-challenge-button {
  border-bottom: 0;
  text-decoration: none !important;
}
.kg-challenge-button:hover {
  background: #254f68;
  text-decoration: none;
}
.page__content mjx-container[display="true"] {
  max-width: 100%;
  overflow-x: auto;
  overflow-y: hidden;
}
@media (max-width: 600px) {
  .kg-challenge-card {
    align-items: stretch;
    flex-direction: column;
  }
  .kg-challenge-button {
    width: 100%;
  }
  .page__content pre.highlight,
  .page__content pre.highlight code {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .page__content mjx-container[display="true"] {
    font-size: 88%;
  }
}
</style>

<div class="lang-switch">
  <a class="active" href="#en" onclick="switchLang('en');return false">English</a>|
  <a href="#zh" onclick="switchLang('zh');return false">中文</a>
</div>

<div id="lang-en" class="lang-content" markdown="1">

<div class="kg-challenge-card">
  <div>
    <p class="kg-challenge-label">Official challenge page</p>
    <p class="kg-challenge-desc">Challenge 9: <a class="kg-challenge-url" href="https://kernelgen.flagos.io/challenge/9?lang=zh&tab=readme" target="_blank" rel="noopener">https://kernelgen.flagos.io/challenge/9?lang=zh&tab=readme</a></p>
  </div>
  <a class="kg-challenge-button" href="https://kernelgen.flagos.io/challenge/9?lang=zh&tab=readme" target="_blank" rel="noopener">Open Challenge 9</a>
</div>

This note records our optimization process for KernelGen Challenge 9, whose function is named `silu_dot_fwd_bwd_quant_fuse`.

The offline final result was pleasantly dramatic: this task eventually placed first in the offline round. The part worth recording is the fairly plain sequence of constraints behind that result: understand the backward formula, respect BF16 quantization semantics, reduce repeated memory traffic, then split backend paths when one Triton kernel stopped being portable enough.

There is also a small warning hidden in the result. Some high-ranking attempts appeared to run into Wrong Answer cases later. Whether or not a score looks beautiful, this particular operator keeps asking the same question: did we preserve the byte-level quantization contract?

<div class="notice--primary" markdown="1">
<p class="notice__title">The Thread</p>

The article first reconstructs the operator from SwiGLU backward and INT8 quantization. Then it explains why a `128x128` tile is natural for this problem, why the first large win came from fusing M-group and K-group quantization, and why the final implementation became a small collection of backend-specific Triton routes.
</div>

## The Operator in Plain Terms

The function signature is:

```python
def silu_dot_fwd_bwd_quant_fuse(
    x,
    grad_y,
    grad_input_q,
    grad_input_s,
    y_q_t,
    y_s_t,
    group_size=128,
):
    ...
```

The input `x` has shape `[M, 2H]` and BF16 dtype. It is naturally split into two halves:

$$
x = [g, u], \qquad g,u\in\mathbb{R}^{M\times H}.
$$

This is the common SwiGLU-style feed-forward block. During backward, instead of reading a saved activation `y`, the operator recomputes:

$$
\sigma = \operatorname{sigmoid}(g),\qquad
\operatorname{silu}(g)=g\sigma,\qquad
y=\operatorname{silu}(g)\odot u.
$$

Given upstream gradient `grad_y`, the gradients are:

$$
d_u = \operatorname{grad}_y\odot \operatorname{silu}(g),
$$

$$
d_g
=\operatorname{grad}_y\odot u\odot\sigma\odot
\big(1+g(1-\sigma)\big).
$$

The output gradient is:

$$
\operatorname{grad\_input}=[d_g,d_u]\in\mathbb{R}^{M\times 2H}.
$$

The task does not simply return `grad_input` and `y`. It quantizes both for downstream INT8 GEMMs:

| Output | Shape | Meaning |
|---|---:|---|
| `grad_input_q` | `[M, 2H]` INT8 | row-wise, per-128-channel quantized gradient |
| `grad_input_s` | `[M, 2H/128]` FP32 | scales for `grad_input_q` |
| `y_q_t` | `[H, M]` INT8 | transposed, per-128-token-group quantized `y` |
| `y_s_t` | `[H, M/128]` FP32 | scales for `y_q_t` |

The benchmark shapes are fixed:

| `num_experts` | `tokens_per_expert` | `H` |
|---:|---:|---:|
| 8 | 128 | 2560 |
| 8 | 256 | 2560 |
| 16 | 128 | 2560 |
| 16 | 256 | 2560 |
| 32 | 128 | 2560 |
| 32 | 256 | 2560 |
| 8 | 128 | 4096 |
| 8 | 256 | 4096 |
| 16 | 128 | 4096 |
| 16 | 256 | 4096 |
| 32 | 128 | 4096 |
| 32 | 256 | 4096 |

Here $M=\text{num\_experts}\times\text{tokens\_per\_expert}$.

## The Quantization Contract

For a vector group $z$ of length 128, the reference quantizer is essentially:

$$
s=\max\left(\frac{\max_i |z_i|}{127},10^{-10}\right),
\qquad
q_i=\operatorname{int8}\left(\operatorname{clip}\left(\frac{z_i}{s},-127,127\right)\right).
$$

For `grad_input`, the groups are channel chunks inside each row. For `y_q_t`, the groups are token chunks after transposition. This distinction is small in notation but important in memory layout:

```text
grad_input: [M, 2H]  -> quantize every row over channel groups of 128
y:          [M, H]   -> transpose to [H, M], quantize every channel over token groups of 128
```

The correctness check has two layers:

| Check | Tolerance | Consequence |
|---|---:|---|
| FP32 scales | `atol=1e-4`, `rtol=1e-5` | scale semantics cannot drift much |
| dequantized INT8 values | `atol=0.25`, `rtol=0.25` | the downstream GEMM-facing values must match |

The small trap is BF16. The reference computes `grad_input` as BF16 before quantization and also quantizes `y.to(bfloat16).to(float32)`. Skipping that BF16 roundtrip is tempting, and it is often faster, but it changes scales and quantized values. Several failed attempts came from underestimating this detail.

<div class="notice--info" markdown="1">
<p class="notice__title">A Useful Algebraic Rewrite</p>

The derivative can be written in the form used by the optimized kernels:

$$
d_g=\operatorname{grad}_y\odot (u\sigma)\odot (1+g-\operatorname{silu}(g)).
$$

This saves one multiplication in the hot path once `silu_val = g * sigmoid(g)` is already available. It is a small example of the kind of optimization that only becomes visible after writing the math next to the kernel.
</div>

## Why `128x128` Is the Natural Tile

The group size is 128. That number appears twice:

```text
M-group quantization: 128 channels per group
K-group quantization: 128 tokens per group
```

So a tile with 128 tokens and 128 channels closes both loops at once. In one `128x128` tile, a Triton program can:

| Tile product | Reduction axis | Scale count |
|---|---:|---:|
| `d_gate` | channels | 128 scales, one per token |
| `d_up` | channels | 128 scales, one per token |
| `y` | tokens | 128 scales, one per channel |

This gives a clean dataflow:

```text
load gate/up/grad_y tile
    -> sigmoid, silu, y, d_gate, d_up
    -> row reductions for d_gate and d_up
    -> column reduction for y
    -> write three INT8 payloads and three scale vectors
```

The reference path materializes `grad_input` and `y`, then quantizes them through separate tensor operations. The optimized route tries to consume each tile while it is still close to the registers.

## The First Large Win: Fuse the Two Quantizers

The early baseline was around `3.26x`. The first major jump came from locating a memory-traffic problem: K-group quantization was either rereading `x` and recomputing `y`, or paying for a temporary `y` surface. A 2D fused Triton kernel removed that repeated path and lifted the average by about `+4.61x`.

The mechanism is concrete. The K-group quantizer needs `y = silu(gate) * up`; the fused tile keeps those values alive long enough to produce both:

```text
M-group output: quantize [d_gate, d_up] by rows
K-group output: quantize y.T by token groups
```

A rough roofline estimate puts the fused kernel at roughly:

| Quantity per `128x128` tile | Approximate value |
|---|---:|
| BF16 reads | `3 * 128 * 128 * 2` bytes |
| INT8 writes | `3 * 128 * 128` bytes |
| scale writes | `3 * 128 * 4` bytes |
| operational intensity | about `2.2` FLOP/byte |

On an RTX 4090-like roofline, the ridge point is far higher than that. In plain language, this task is deeply memory-bound. Once that is clear, optimization becomes less like inventing clever arithmetic and more like avoiding unnecessary trips through memory.

## A Small Line With a Large Effect

One of the surprisingly valuable changes was:

```python
# less helpful
q = x / (absmax / 127.0)

# better
q = x * (127.0 / absmax)
```

This change came from treating division as a measured bottleneck, not as a cosmetic algebra rewrite. It raised the average speedup by about `+0.92x`. The lesson is modest but useful: tensor division inside Triton should not be assumed cheap, and the compiler may not always rewrite this expression in the way we want across all backends.

This puts the high-value changes in a simple cost-model frame:

| Change | Cost reduced |
|---|---|
| 2D fused tile | rereads and temporary tensors |
| channel-major grid | poorer L2 locality |
| division-to-multiply | slow elementwise division |
| y-first quantization | peak register lifetime |
| platform split | backend-specific codegen and cache behavior |

## The Platform Split

A single beautiful Triton kernel was not the final shape. The platform matrix pushed us toward a more ordinary engineering answer: share the mathematical contract, split the backend paths.

The current implementation detects the backend and dispatches to separate routes:

| Platform route | Implementation idea |
|---|---|
| NVIDIA | dedicated 2D kernel, y-first quantization, `num_warps=16`, `num_stages=1` |
| Hygon/AMD | 2D grid, BF16 quantization, no NVIDIA-style cache hints, `num_warps=8` |
| TianShu | 2D grid, early BF16 `y`, deeper staging, `num_stages=3` |
| MetaX | 2D grid with FP32 absmax/BF16-round scale path |
| T-Head | conservative generic fused route, tuned separately after platform recovery |
| MooreThreads | M-group kernel plus `y` buffer plus K-group buffer quantization |
| Ascend | Triton forward/backward recompute, then PyTorch quantization for correctness |

This table is less elegant than a single abstraction, but it matches the competition reality. The backends differ in warp size, BF16 behavior, cache policy, register pressure, and Triton implementation maturity. A win on one platform could easily be a regression or a Wrong Answer on another.

<div class="notice--warning" markdown="1">
<p class="notice__title">Final Dispatch Matters</p>

Several experimental kernels can appear during development, but they are not necessarily used in the final dispatch. When reading optimization code, the important object is the branch that the submitted function actually launches.
</div>

## MooreThreads Was Its Own Puzzle

MooreThreads was a good reminder that coalescing alone is not a sufficient explanation of performance. Several attempts tried to make the K-group path look more like the 2D fused CUDA path, but extra buffers or larger fused tiles often lost to bandwidth and register pressure.

The route that survived in the current implementation is more pragmatic:

```text
M-group kernel:
    recompute forward/backward
    quantize grad_input
    write BF16 y buffer

K-group buffer kernel:
    read 128x128 BF16 y tiles
    reduce over tokens
    write y_q_t and y_s_t
```

This is not the purest fusion story, but it preserves enough locality while keeping each kernel's register pressure manageable. The final tuning also moved simple kernels toward `num_stages=1`, because there is no deep inner loop that benefits much from software pipelining.

## Correctness Boundaries That Shaped the Work

Several failed attempts were useful because they drew the boundary of the problem:

| Attempt | Outcome |
|---|---|
| skip BF16 roundtrip | scale/quantization mismatches |
| use FP16 intermediate compute on AMD | numerical path drift |
| use PyTorch quantization on general GPU path | launch and framework overhead dominated |
| rely on autotune | T-Head timeout exceeded the platform limit |
| increase work per program too much | fewer blocks and more spills hurt occupancy |
| add temporary buffers broadly | extra memory traffic erased arithmetic savings |

This is also why the offline win felt satisfying. It was not only a matter of chasing the largest visible speedup. A high-speed implementation still had to survive the hidden shape/correctness surface, and the quantization contract made that surface fairly sharp.

## Problem, Fix, and Payoff

The useful way to read the optimization history is as a sequence of bottlenecks we isolated:

| Bottleneck located | Fix | Payoff |
|---|---|---|
| PyTorch/reference surface materialized `grad_input` and `y` | Move recompute and quantization into Triton | From about `3.26x` baseline into the kernel-optimized range |
| K-group quantization reread `x` or needed a temporary `y` surface | Fuse M-group and K-group quantization inside one `128x128` tile | About `+4.61x`, reaching roughly `7.87x` |
| Tile order gave weak L2 locality | Use a channel-major grid | Around `+0.39x` in the measured route |
| Inner-loop quantization still used elementwise division | Rewrite `x / (absmax / 127)` as `x * (127 / absmax)` | About `+0.92x` |
| Backend differences caused performance and correctness regressions | Keep the mathematical contract shared, but split platform dispatch | Stable 7/7 submissions around `10.46x`; offline final first place |

The exact numbers come from submission records and our review notes. Their role here is to mark which cost each change removed, so the narrative stays focused on technical decisions.

## Lessons Worth Keeping

The main lesson is that this operator looks like activation math, but behaves like a quantization and memory-layout problem.

For future kernels, I would keep the following checklist:

| Question | Why it matters |
|---|---|
| What intermediate tensor is largest? | It is probably the first thing to avoid materializing |
| Are two reductions using the same group size? | This may reveal the natural tile |
| Does the reference round to BF16 before quantization? | It determines both scales and INT8 values |
| Is division still present in the inner loop? | It may be an avoidable throughput sink |
| Does a platform need its own route? | Multi-backend Triton is not one architecture |
| Did a change pass all hidden-like shapes? | A fast Wrong Answer is still a failed kernel |

If I compress the work into one sentence, it would be this: the winning route was to align the tile with the quantization groups, keep the data close while producing both quantized outputs, and stop pretending that all seven backends wanted the same kernel.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

<div class="kg-challenge-card">
  <div>
    <p class="kg-challenge-label">官方题面入口</p>
    <p class="kg-challenge-desc">Challenge 9：<a class="kg-challenge-url" href="https://kernelgen.flagos.io/challenge/9?lang=zh&tab=readme" target="_blank" rel="noopener">https://kernelgen.flagos.io/challenge/9?lang=zh&tab=readme</a></p>
  </div>
  <a class="kg-challenge-button" href="https://kernelgen.flagos.io/challenge/9?lang=zh&tab=readme" target="_blank" rel="noopener">打开 Challenge 9</a>
</div>

这篇文章记录的是 KernelGen Challenge 9 的一次优化过程，函数名是 `silu_dot_fwd_bwd_quant_fuse`。

这道题在线下赛最后拿到了第一名。这个结果当然令人开心；不过真正值得留下来的，还是这一路上的约束：先把 SwiGLU backward 算清楚，再守住 BF16 量化语义，然后减少重复搬运，最后在一个通用 Triton kernel 不再足够可靠时，把多后端路径拆开。

结果里还藏着一个小提醒：一些高分方案后来似乎在部分 case 上遇到了 Wrong Answer。无论分数多漂亮，这个算子一直在追问同一个问题：量化后的字节语义有没有被保住？

<div class="notice--primary" markdown="1">
<p class="notice__title">本文的主线</p>

文章先从 SwiGLU 反向和 INT8 量化还原题目本身；然后解释为什么 `128x128` tile 很自然，为什么第一波大收益来自融合 M-group 与 K-group 量化；最后再讲实现为什么变成了一组后端专用 Triton 路径。
</div>

## 先把算子说清楚

题目函数是：

```python
def silu_dot_fwd_bwd_quant_fuse(
    x,
    grad_y,
    grad_input_q,
    grad_input_s,
    y_q_t,
    y_s_t,
    group_size=128,
):
    ...
```

输入 `x` 的形状是 `[M, 2H]`，类型是 BF16。它可以自然地拆成两半：

$$
x = [g, u], \qquad g,u\in\mathbb{R}^{M\times H}.
$$

这对应常见的 SwiGLU 风格 FFN。反向阶段不直接读取保存好的 `y`，而是重新计算：

$$
\sigma = \operatorname{sigmoid}(g),\qquad
\operatorname{silu}(g)=g\sigma,\qquad
y=\operatorname{silu}(g)\odot u.
$$

给定上游梯度 `grad_y`，两个梯度是：

$$
d_u = \operatorname{grad}_y\odot \operatorname{silu}(g),
$$

$$
d_g
=\operatorname{grad}_y\odot u\odot\sigma\odot
\big(1+g(1-\sigma)\big).
$$

于是：

$$
\operatorname{grad\_input}=[d_g,d_u]\in\mathbb{R}^{M\times 2H}.
$$

题目的输出还要把 `grad_input` 和 `y` 量化成后续 INT8 GEMM 要用的格式：

| 输出 | 形状 | 含义 |
|---|---:|---|
| `grad_input_q` | `[M, 2H]` INT8 | 按行、每 128 个 channel 分组量化后的梯度 |
| `grad_input_s` | `[M, 2H/128]` FP32 | `grad_input_q` 的 scale |
| `y_q_t` | `[H, M]` INT8 | 转置后、每 128 个 token 分组量化后的 `y` |
| `y_s_t` | `[H, M/128]` FP32 | `y_q_t` 的 scale |

benchmark 的形状比较固定：

| `num_experts` | `tokens_per_expert` | `H` |
|---:|---:|---:|
| 8 | 128 | 2560 |
| 8 | 256 | 2560 |
| 16 | 128 | 2560 |
| 16 | 256 | 2560 |
| 32 | 128 | 2560 |
| 32 | 256 | 2560 |
| 8 | 128 | 4096 |
| 8 | 256 | 4096 |
| 16 | 128 | 4096 |
| 16 | 256 | 4096 |
| 32 | 128 | 4096 |
| 32 | 256 | 4096 |

这里 $M=\text{num\_experts}\times\text{tokens\_per\_expert}$。

## 量化语义

对长度为 128 的一组向量 $z$，参考量化大致是：

$$
s=\max\left(\frac{\max_i |z_i|}{127},10^{-10}\right),
\qquad
q_i=\operatorname{int8}\left(\operatorname{clip}\left(\frac{z_i}{s},-127,127\right)\right).
$$

对 `grad_input` 来说，分组发生在每一行内部的 channel 维度；对 `y_q_t` 来说，分组发生在转置之后的 token 维度。写成内存形状就是：

```text
grad_input: [M, 2H]  -> 每行按 128 个 channel 一组量化
y:          [M, H]   -> 转置成 [H, M] 后，每个 channel 按 128 个 token 一组量化
```

正确性检查有两层：

| 检查 | 容差 | 含义 |
|---|---:|---|
| FP32 scales | `atol=1e-4`, `rtol=1e-5` | scale 语义不能明显漂移 |
| INT8 反量化值 | `atol=0.25`, `rtol=0.25` | 后续 GEMM 真正看到的值要匹配 |

这里最容易轻视的是 BF16。参考实现会先把 `grad_input` 转成 BF16 再量化，也会把 `y` 走一遍 `to(bfloat16).to(float32)`。跳过这个 roundtrip 很诱人，而且通常更快，但它会改变 scale 和量化值。我们有几次失败尝试，本质上就是低估了这个细节。

<div class="notice--info" markdown="1">
<p class="notice__title">一个有用的代数改写</p>

梯度也可以写成优化 kernel 里使用的形式：

$$
d_g=\operatorname{grad}_y\odot (u\sigma)\odot (1+g-\operatorname{silu}(g)).
$$

当 `silu_val = g * sigmoid(g)` 已经算出来时，这个写法可以少一个热路径里的乘法。这个优化很小，但它说明了一件事：把公式和 kernel 放在一起看，常常会露出一些代码层面不显眼的机会。
</div>

## 为什么是 `128x128` tile

题目里的 group size 是 128。这个 128 同时出现在两个方向：

```text
M-group quantization: 每 128 个 channel 一组
K-group quantization: 每 128 个 token 一组
```

因此，一个包含 128 个 token 和 128 个 channel 的 tile，正好同时闭合了两个量化分组。在一个 `128x128` tile 里，Triton program 可以产生：

| tile 内产物 | reduction 方向 | scale 数量 |
|---|---:|---:|
| `d_gate` | channel | 128 个，每个 token 一个 |
| `d_up` | channel | 128 个，每个 token 一个 |
| `y` | token | 128 个，每个 channel 一个 |

于是数据流可以写成：

```text
load gate/up/grad_y tile
    -> sigmoid, silu, y, d_gate, d_up
    -> d_gate 与 d_up 做行方向 reduction
    -> y 做列方向 reduction
    -> 写回三份 INT8 payload 和三组 scale
```

参考实现会显式物化 `grad_input` 和 `y`，再分别调用量化逻辑。优化版本则尽量在 tile 还停留在寄存器附近时，把两种量化一起做掉。

## 第一波大收益：融合两个量化器

早期 baseline 大约是 `3.26x`。第一波大收益来自一个明确的内存流量问题：K-group 量化要么重复读取 `x` 并重新计算 `y`，要么依赖一个临时 `y` 张量。2D fused Triton kernel 把这条重复路径拿掉，带来了约 `+4.61x` 的平均提升。

具体机制很直接。K-group 量化需要 `y = silu(gate) * up`；融合后的 tile 可以让同一批数据同时产出：

```text
M-group output: 对 [d_gate, d_up] 按行量化
K-group output: 对 y.T 按 token group 量化
```

粗略 roofline 估算显示，一个 fused `128x128` tile 大约是：

| 每个 `128x128` tile | 近似值 |
|---|---:|
| BF16 读取 | `3 * 128 * 128 * 2` bytes |
| INT8 写回 | `3 * 128 * 128` bytes |
| scale 写回 | `3 * 128 * 4` bytes |
| operational intensity | 约 `2.2` FLOP/byte |

如果拿 RTX 4090 这类 GPU 的 roofline 粗看，它的 ridge point 远高于这个数。也就是说，这题本质上非常偏 memory-bound。知道这一点以后，优化就不太像发明复杂算术，而更像少让数据来回搬几趟。

## 一行小改动，收益不小

有一个改动很朴素：

```python
# 不太理想
q = x / (absmax / 127.0)

# 更好
q = x * (127.0 / absmax)
```

这个改动的价值在于，它把逐元素除法从量化内层拿掉了。复盘记录里，这带来了约 `+0.92x` 的平均提升。这个经验并不花哨：Triton 里的 elementwise division 不应默认视为便宜，而且不同 backend 的编译器未必都会把这个表达式改成我们想要的乘法形式。

这些改动背后都有一个相对朴素的成本模型：

| 修改 | 减少的成本 |
|---|---|
| 2D fused tile | 重复读取和临时张量 |
| channel-major grid | 较差的 L2 locality |
| division-to-multiply | 慢的逐元素除法 |
| y-first quantization | 峰值寄存器生命周期 |
| platform split | 后端 codegen 与 cache 行为差异 |

## 多后端拆分

最后的实现没有停在一个漂亮的通用 Triton kernel 上。平台矩阵把我们推向了更朴素的工程答案：数学语义共用，后端路径拆开。

当前实现会检测后端并分发到不同路线：

| 平台路线 | 实现思路 |
|---|---|
| NVIDIA | 专用 2D kernel，先量化 `y` 降低寄存器压力，`num_warps=16`，`num_stages=1` |
| 海光/AMD | 2D grid，BF16 quantization，不使用 NVIDIA 风格 cache hints，`num_warps=8` |
| 天数 | 2D grid，提前把 `y` 转 BF16，`num_stages=3` |
| 沐曦 MetaX | 2D grid，FP32 absmax 后 BF16-round scale 的路线 |
| 平头哥 T-Head | 较保守的 generic fused route，平台恢复后单独调过参数 |
| 摩尔线程 | M-group kernel 加 `y` buffer，再用 K-group buffer kernel 量化 |
| 昇腾 Ascend | Triton 做 forward/backward 重算，量化交给 PyTorch 路线保正确性 |

这张表不如一个统一抽象好看，但它更接近比赛现实。各个平台的 warp size、BF16 行为、cache policy、寄存器压力、Triton 实现成熟度都不一样。一个平台上的收益，到了另一个平台可能就是性能回退，甚至 Wrong Answer。

<div class="notice--warning" markdown="1">
<p class="notice__title">要看最终 dispatch</p>

开发过程中会出现不少实验 kernel，但它们不一定都在最终提交路径里使用。读这类优化代码时，关键是看提交函数到底 launch 了哪一个分支。
</div>

## 摩尔线程这一支

摩尔线程给我的提醒是：coalescing 并不能单独解释性能。我们尝试过让 K-group 路径更像 CUDA 侧的 2D fused kernel，但额外 buffer 或更大的融合 tile 经常输给带宽和寄存器压力。

当前实现里保留下来的路线更务实：

```text
M-group kernel:
    重算 forward/backward
    量化 grad_input
    写 BF16 y buffer

K-group buffer kernel:
    读 128x128 BF16 y tile
    沿 token 方向 reduction
    写 y_q_t 与 y_s_t
```

这条路线没有那么纯粹的 fusion 味道，但它把每个 kernel 的寄存器压力压在比较可控的范围内。最后一些简单 kernel 也倾向于 `num_stages=1`，因为没有深 inner loop 时，软件流水不一定能带来收益，反而可能增加寄存器压力。

## 正确性边界

一些失败尝试很有价值，因为它们帮我们画出了这题的边界：

| 尝试 | 结果 |
|---|---|
| 跳过 BF16 roundtrip | scale 或量化值不匹配 |
| AMD 上用 FP16 intermediate compute | 数值路径漂移 |
| 通用 GPU 路径使用 PyTorch quantization | launch 与框架开销压过收益 |
| 依赖 autotune | T-Head 超过平台超时限制 |
| 每个 program 做太多工作 | block 数减少，寄存器 spill，occupancy 下降 |
| 大范围引入临时 buffer | 额外内存流量吃掉算术收益 |

这也是线下赛第一名比较让人踏实的原因。它靠的不只是最高的可见 speedup。一个快的实现还要能穿过 hidden shape 和正确性检查，而这题的量化语义把这个边界卡得比较紧。

## 问题、解法和收益

更有用的读法，是看我们每次定位到了哪类瓶颈：

| 定位到的问题 | 解法 | 收益 |
|---|---|---|
| PyTorch/reference 路径会物化 `grad_input` 和 `y` | 把重算与量化搬进 Triton | 从约 `3.26x` baseline 进入 kernel 优化区间 |
| K-group 量化会重复读取 `x` 或依赖临时 `y` | 在同一个 `128x128` tile 里融合 M-group 与 K-group 量化 | 约 `+4.61x`，到约 `7.87x` |
| tile 顺序对 L2 locality 不友好 | 使用 channel-major grid | 实测路径里约 `+0.39x` |
| 量化内层仍有逐元素除法 | 把 `x / (absmax / 127)` 改成 `x * (127 / absmax)` | 约 `+0.92x` |
| 多后端对同一 kernel 的响应不同 | 数学语义共用，platform dispatch 拆开 | 稳定 7/7 提交约 `10.46x`，线下 final 第一名 |

这些数字来自提交记录和复盘笔记。它们在文中的作用，是标明每个改动对应消掉了哪一类成本，让叙事围绕技术判断展开。

## 值得保留的经验

这题表面上像激活函数和反向传播，实际更像一个量化与内存布局问题。

以后遇到类似 kernel，我会先问几件事：

| 问题 | 为什么重要 |
|---|---|
| 最大的中间张量是什么？ | 它很可能是最应该避免物化的东西 |
| 是否有两个 reduction 使用同一个 group size？ | 这可能暴露出天然 tile |
| reference 是否在量化前做 BF16 roundtrip？ | 它决定 scale 和 INT8 值 |
| inner loop 里还有没有除法？ | 这可能是可避免的吞吐瓶颈 |
| 某个平台是否需要单独路径？ | 多后端 Triton 背后是多套架构 |
| 改动是否过了所有 hidden-like shape？ | 很快的 Wrong Answer 仍然是失败 kernel |

如果把这次工作压缩成一句话，那就是：把 tile 对齐到量化分组，在数据还热的时候同时产出两类量化结果，然后承认七个平台并不想要同一个 kernel。

</div>

<script>
function switchLang(lang) {
  document.getElementById('lang-en').style.display = lang === 'en' ? '' : 'none';
  document.getElementById('lang-zh').style.display = lang === 'zh' ? '' : 'none';
  document.querySelectorAll('.lang-switch a').forEach(function(el) {
    el.classList.remove('active');
  });
  document.querySelector('.lang-switch a[href="#' + lang + '"]').classList.add('active');
  if (history.replaceState) {
    history.replaceState(null, '', '#' + lang);
  }
  window.dispatchEvent(new CustomEvent('languagechange', { detail: { lang: lang } }));
}

if (location.hash === '#zh') {
  switchLang('zh');
}
</script>

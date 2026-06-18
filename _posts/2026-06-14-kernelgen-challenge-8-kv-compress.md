---
title: "From Attention to KV Cache Compression: Notes from a KernelGen Optimization"
date: 2026-06-14
categories:
  - tech
  - systems
tags:
  - GPU
  - Triton
  - KernelGen
  - KV Cache
  - DeepSeek
  - Ascend
excerpt: "Starting from Attention and KV Cache, this note walks through KernelGen Challenge 8: a DeepSeek-style KV compression operator, its Triton implementation, and the separate optimization paths for GPGPU and Ascend."
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
  margin: 1.1em 0 1.4em;
  padding: 0.9rem 1rem;
  border: 1px solid rgba(46, 101, 132, 0.22);
  border-left: 4px solid #2e6584;
  border-radius: 6px;
  background: #f7fbfd;
}
.kg-challenge-card--lead {
  margin-top: 0;
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
@media (max-width: 600px) {
  .kg-challenge-card {
    align-items: stretch;
    flex-direction: column;
  }
  .kg-challenge-button {
    width: 100%;
  }
}
</style>

<div class="lang-switch">
  <a class="active" href="#en" onclick="switchLang('en');return false">English</a>|
  <a href="#zh" onclick="switchLang('zh');return false">中文</a>
</div>

<div id="lang-en" class="lang-content" markdown="1">

<div class="kg-challenge-card kg-challenge-card--lead">
  <div>
    <p class="kg-challenge-label">Official challenge page</p>
    <p class="kg-challenge-desc">Challenge 8: <a class="kg-challenge-url" href="https://kernelgen.flagos.io/challenge/8?lang=zh&tab=readme" target="_blank" rel="noopener">https://kernelgen.flagos.io/challenge/8?lang=zh&tab=readme</a></p>
  </div>
  <a class="kg-challenge-button" href="https://kernelgen.flagos.io/challenge/8?lang=zh&tab=readme" target="_blank" rel="noopener">Open Challenge 8</a>
</div>

This post records one optimization pass for KernelGen Challenge 8. It is a set of notes written after doing the problem and filling in the missing background along the way. The statement itself is short, and the core function has only one name; once we actually start implementing it, however, it pulls in Attention, KV Cache, Triton DSL, GPU memory access, quantized byte layouts, and cross-backend differences.

Let us not begin with code. A natural first question is: why is a KV Cache compression operator that finally writes only a few hundred bytes worth optimizing with a custom kernel?

The rough answer is that in long-context decoding, the KV Cache is already close to the inference state itself. It occupies memory, consumes bandwidth, and every compression, movement, and writeback detail can show up in real decoding latency. This post starts there and slowly walks toward the concrete Triton implementation.

The implementation notes and experiments below come from our submissions, local microbenchmarks, and several rounds of independent checks during the competition. I only keep the parts that help explain the implementation choices.

<div class="notice--primary" markdown="1">
<p class="notice__title">The Thread</p>

The first half clarifies Attention, KV Cache, and the byte layout in the problem. The middle section derives how one output slot is produced. The second half returns to implementation and discusses the two optimization routes: GPGPU and Ascend.
</div>

## Starting from Attention

Standard dot-product attention can be written as:

$$
\boldsymbol{o}_i=\sum_j a_{i,j}\boldsymbol{v}_j,\qquad
a_{i,j}=\frac{\exp(s_{i,j})}{\sum_k \exp(s_{i,k})},\qquad
s_{i,j}=\frac{\boldsymbol{q}_i^{\top}\boldsymbol{k}_j}{\sqrt{d}}.
$$

Here $\boldsymbol{q}_i$ is the query at the current position, and $\boldsymbol{k}_j,\boldsymbol{v}_j$ are the key and value at attended positions. For a decoder-only model, token $i$ can only see the past, so $j\leq i$.

The prefill phase is usually regular: the $Q,K,V$ of the whole input segment can be computed in one pass and then handed to a matrix-shaped attention kernel. Decoding is less tidy. The model generates only one new token each step, but that token still attends to all previous tokens. At step $t$ we roughly have:

$$
\boldsymbol{q}_t
\quad\text{attends to}\quad
\{\boldsymbol{k}_1,\ldots,\boldsymbol{k}_t\},\quad
\{\boldsymbol{v}_1,\ldots,\boldsymbol{v}_t\}.
$$

If every step recomputed $K,V$ from all historical hidden states, the repeated work would be substantial. Practical inference therefore stores the historical tokens' $K,V$ and reads them directly later. That stored state is the KV Cache.

In this sense, the KV Cache is a state variable of decoding. It removes repeated computation, while moving pressure onto memory capacity and memory bandwidth.

## The KV Cache Bill

If the context length is $L$, the number of KV heads is $h_{kv}$, and the key/value dimensions per head are $d_k,d_v$, then the KV Cache size is roughly:

$$
O\big(L\cdot h_{kv}\cdot(d_k+d_v)\big).
$$

That is the capacity bill. In decoding we also pay a read-bandwidth bill: every generated token has to read historical Key/Value states for attention. As $L$ grows, the bottleneck often shifts from arithmetic toward the memory system.

Many attention variants can be understood through this line. MHA, MQA, GQA, MLA, and related designs differ in form, but they repeatedly ask the same practical question: how many bytes should we spend to preserve historical information?

KernelGen does not ask us to redesign the attention architecture. It gives us a DeepSeek-style compression rule. The engineering task is more concrete:

```text
a historical state window
    -> one 512-dimensional compressed vector
    -> a packed KV-cache byte region
```

This is the core of the post: make that compression fast while keeping the byte-level semantics correct.

## Competition Background and Problem Statement

The problem comes from the FlagOS KernelGen 48-hour operator bounty challenge in Beijing. Its function is named `c128_256_512_compress`, and the statement describes KV Cache compression for DeepSeek V4 long-context inference. The submission is a Python file. The function name and parameters must match the statement, the file must be UTF-8, and the platform expects Python 3 and Triton 3.5 compatibility. The same `solution.py` is tested on multiple backends, so the problem is both a kernel optimization task and a multi-backend engineering task.

The platform roughly covers:

| Category | Platforms |
|---|---|
| GPGPU route | NVIDIA, MetaX, Hygon, TianShu, Moore Threads, T-Head |
| DSA/NPU route | Huawei Ascend |

The benchmark shapes are also quite fixed. `compress_ratio` is only 128, 256, or 512, and `num_reqs` and `total_tokens` form 12 cases:

| `num_reqs` | `total_tokens` | `compress_ratio` |
|---:|---:|---:|
| 1 | 8192 | 128 |
| 4 | 32768 | 128 |
| 8 | 65536 | 128 |
| 8 | 131072 | 128 |
| 1 | 8192 | 256 |
| 4 | 32768 | 256 |
| 8 | 65536 | 256 |
| 8 | 131072 | 256 |
| 1 | 8192 | 512 |
| 4 | 32768 | 512 |
| 8 | 65536 | 512 |
| 8 | 131072 | 512 |

These numbers matter. They mean we are working on a highly structured compression task, rather than a general operator over arbitrary shapes. A fixed structure gives constraints, but it also leaves useful openings. The later `block_size=8` optimization came from exactly this fixed structure.

## The Compression Operator

The target function is:

```python
def c128_256_512_compress(
    state_cache,
    token_to_req,
    positions,
    boundary_token_indices,
    block_table,
    rms_norm_weight,
    cos_sin_cache,
    kv_slot_mapping,
    kv_cache,
    block_size,
    compress_ratio,
    rms_norm_eps=1.0e-6,
):
    ...
```

One can first view it as a "window compressor": for every token listed in `boundary_token_indices`, take the previous contiguous window of length `compress_ratio`, compress those state rows into a new KV Cache slot, and write the packed result back.

<div class="notice--info" markdown="1">
<p class="notice__title">Gather and Scatter</p>

In operator implementation, gather means reading a set of positions from a source tensor according to indices and forming the working set needed for computation. In this problem, gather uses request id, position, and block table to locate the physical state-cache rows in the compression window. Scatter is the reverse write path: the computed payload and scale bytes are written back to the paged KV cache according to the target KV slot.
</div>

Some constants appear repeatedly:

| Name | Value | Meaning |
|---|---:|---|
| `HEAD_DIM` | 512 | Width of the compressed vector |
| `ROPE_HEAD_DIM` | 64 | Last 64 dimensions use RoPE and are stored as BF16 bytes |
| `NOPE_HEAD_DIM` | 448 | First 448 dimensions are INT8-quantized |
| `KV_BLOCK_SIZE` | 64 | One KV page contains 64 slots |
| `TOKEN_STRIDE` | 576 | Payload bytes per slot |
| `SCALE_DIM` | 8 | Scale-byte region per slot |

The payload of one output slot is:

```text
[448 bytes INT8 NOPE][128 bytes BF16 RoPE]
```

The scale region is:

```text
[7 active scale bytes][1 padding byte]
```

<div class="notice--info" markdown="1">
<p class="notice__title">Byte-Level Correctness</p>

The final comparison is against the KV Cache byte layout. Close intermediate floating-point values are not enough: INT8 value bytes, scale bytes, RoPE BF16 bytes, and page/slot scatter positions all have to match. Many attempts that looked "almost right" eventually failed on these byte details.
</div>

## How One Output Is Produced

Let us expand one output. The formulas look long, but they answer three questions: where is the window, how is it compressed into 512 dimensions, and how is the result packed back into KV Cache?

Let the current boundary token be $b$, the window length be $C=\mathtt{compress\_ratio}$, and the head dimension be $D=512$. Its request id and position are:

$$
r=\mathtt{token\_to\_req}[b],\qquad
p=\mathtt{positions}[b].
$$

The $i$-th historical token position in the window is:

$$
t_i=p-C+1+i,\qquad 0\le i<C.
$$

Each $t_i$ is mapped through the paged state-cache layout to a physical row. Let $B=\mathtt{block\_size}$, which is 8 in the problem:

$$
\ell_i=\left\lfloor\frac{t_i}{B}\right\rfloor,\qquad
o_i=t_i\bmod B,
$$

$$
g_i=\mathtt{block\_table}[r,\ell_i],\qquad
\mathtt{row}_i=g_iB+o_i.
$$

The first 512 dimensions of `state_cache[row_i]` are values, and the next 512 dimensions are scores:

$$
v_{i,d}=\mathtt{state\_cache}[\mathtt{row}_i,d],
\qquad
s_{i,d}=\mathtt{state\_cache}[\mathtt{row}_i,D+d],
\qquad 0\le d<D.
$$

For every dimension $d$, we apply softmax along the window and then form a weighted sum:

$$
\alpha_{i,d}=\frac{\exp(s_{i,d})}{\sum_{j=0}^{C-1}\exp(s_{j,d})},
\qquad
c_d=\sum_{i=0}^{C-1}\alpha_{i,d}v_{i,d}.
$$

One detail is easy to miss: the softmax is per dimension. In other words, the 512 dimensions each have their own length-$C$ weight vector, and each dimension normalizes over its own window.

After obtaining the 512-dimensional compressed vector $\boldsymbol{c}$, we apply RMSNorm. With weight $w_d$:

$$
\rho=\left(\frac{1}{D}\sum_{d=0}^{D-1}c_d^2+\varepsilon\right)^{-1/2},
\qquad
y_d=c_d\rho w_d.
$$

The first 448 dimensions go through NOPE quantization. The reference implementation first does a BF16 roundtrip. For the $g$-th group of 64 dimensions:

$$
z_d=\operatorname{fp32}(\operatorname{bf16}(y_d)),
\qquad
G_g=\{64g,\ldots,64g+63\},
$$

$$
a_g=\max\left(\max_{d\in G_g}|z_d|,10^{-4}\right),
\qquad
e_g=\left\lceil\log_2\frac{a_g}{127}\right\rceil.
$$

The quantized value and scale byte are:

$$
q_d=\operatorname{int8}\left(\operatorname{clip}(z_d\,2^{-e_g},-127,127)\right),
\qquad
\mathtt{scale}_g=\operatorname{uint8}(e_g+127).
$$

The final 64 dimensions use GPT-J interleaved RoPE. For $j=0,\ldots,31$:

$$
u_j=y_{448+2j},\qquad
w_j=y_{448+2j+1},
\qquad
p_c=\left\lfloor\frac{p}{C}\right\rfloor C.
$$

After reading $\cos_j,\sin_j$ from `cos_sin_cache[p_c]`:

$$
\tilde u_j=u_j\cos_j-w_j\sin_j,
\qquad
\tilde w_j=w_j\cos_j+u_j\sin_j.
$$

The writeback position comes from `kv_slot_mapping[b]`:

```text
slot        = kv_slot_mapping[b]
page        = slot // 64
slot_offset = slot % 64
payload_col = slot_offset * 576
scale_col   = 64 * 576 + slot_offset * 8
```

Putting it together, the operator is roughly:

```text
window rows
  -> per-dim softmax weighted sum
  -> RMSNorm
  -> NOPE INT8 bytes + scale bytes
  -> RoPE BF16 bytes
  -> paged KV-cache scatter
```

## The Baseline

The official baseline is a good semantic reference. It first gathers all rows needed by the window:

```python
flat_idx = (block_numbers * block_size + block_offsets).reshape(-1)
all_rows = state_cache.reshape(-1, 2 * HEAD_DIM)[flat_idx].reshape(
    num_outputs, compress_ratio, 2 * HEAD_DIM
)

kv_vals = all_rows[:, :, :HEAD_DIM]
scores = all_rows[:, :, HEAD_DIM:]
compressed = (kv_vals * F.softmax(scores, dim=1)).sum(dim=1)
```

The code is clean. The cost is also clear: it constructs a large logical intermediate tensor:

```text
[num_outputs, compress_ratio, 1024]
```

When `compress_ratio=512`, the source traffic for a single output is roughly:

```text
512 * 1024 * sizeof(float) ~= 2 MiB
```

The final payload plus scale is under 600 bytes. This contrast points to the main pressure points:

| Bill | Main pressure |
|---|---|
| `state_cache` reads | Larger windows mean heavier source traffic |
| Intermediate tensor | `all_rows` amplifies memory traffic |
| Paged layout | `block_table` and slot math add integer addressing work |
| Finalizer | Small data volume, but BF16, INT8, scale, and RoPE byte semantics are sharp |

This observation is not subtle, but it gives the optimization direction: move fewer large tensors, avoid repeated address work, and stream whenever possible.

## A Bit of Triton and GPU Background

Triton is a Python DSL for GPU kernels. Its abstraction level sits roughly between PyTorch and CUDA C: we write programs, each program handles a tile, and the compiler maps these tiles to the underlying GPU execution model.

Here a tile can be read as "a small implementation work block." It is an implementation-level unit. We cut a large problem into smaller rectangles so memory access, register use, and parallel granularity become more controllable.

<div class="notice--info" markdown="1">
<p class="notice__title">Implementation Granularity: Tile</p>

A tile is a fixed chunk of work inside the kernel implementation. In matrix multiplication it often corresponds to a small rectangle of the matrix. In this problem it is closer to "some historical tokens times some head dimensions." After the large window is split into tiles, the kernel can read and reduce by blocks, trying to consume the data near registers or cache.
</div>

For this problem, the full computation surface can be imagined as:

```text
outputs x compress_window x head_dim
```

A Triton program usually does not process the whole surface at once. More often, one program handles a segment of head dimensions for one output and reads the window dimension in chunks:

```text
BLOCK_T: how many source tokens to read at a time
BLOCK_D: how many head dimensions to process at a time
```

So the core tile read by one `tl.load` is usually:

```text
[BLOCK_T, BLOCK_D]
```

For example, with `BLOCK_T=128, BLOCK_D=64`, one program processes 64 dimensions for one boundary token and scans 128 historical tokens at a time. For `compress_ratio=512`, it scans four such token tiles. The 512 head dimensions are usually covered by eight dimension tiles.

Tile size affects many details: a larger `BLOCK_T` reduces loop count but makes each load and mask heavier; a larger `BLOCK_D` exposes more dimension parallelism but increases accumulator and register pressure. Tuning tiles is therefore not simply "make them larger"; it is a balance among backend registers, cache, memory transactions, and compiler lowering.

In this problem, a program can correspond to:

```text
one output slot
one segment of head dimensions
one segment of the compression window
```

Typical code looks like:

```python
out_pid = tl.program_id(0)
group_pid = tl.program_id(1)
dims = group_pid * BLOCK_D + tl.arange(0, BLOCK_D)
lanes = tl.arange(0, BLOCK_T)
```

`tl.program_id` chooses which output block this program owns, while `tl.arange` creates vectorized lanes. Then `tl.load` reads a two-dimensional tile:

```python
values = tl.load(
    state_cache
    + block[:, None] * state_s0
    + block_offset[:, None] * state_s1
    + dims[None, :] * state_s2
)
```

Logically, `values` is `[BLOCK_T, BLOCK_D]`. We write tensorized expressions in Python; the compiler lowers them to the GPU backend.

When writing kernels like this, the main ledger usually contains:

| Item | Meaning in this problem |
|---|---|
| Global memory reads | `state_cache` is large; excessive reads easily become bandwidth-bound |
| Address generation | `block_table` lookup and integer indexing consume instructions and registers |
| Register pressure | Larger `BLOCK_D` means more accumulators and heavier programs |
| Parallel granularity | Too-small `BLOCK_T` adds loops; too-large `BLOCK_T` may stress scheduling |
| Temporary tensors | PyTorch baseline's `all_rows` is clear, but it increases memory traffic |

The two main optimizations later, online softmax and block8 physical-block arithmetic, both fit this ledger: the former reduces intermediate tensors, while the latter reduces address work in the hot loop.

## Our Decomposition

The current implementation is roughly split into two stages:

```text
Triton gather/reduce -> compressed[outputs, 512]
Triton/PyTorch-safe finalize -> packed kv_cache bytes
```

The first stage streams the window from the paged state cache and performs the softmax weighted sum, producing FP32 `compressed`. The second stage applies RMSNorm, NOPE quantization, RoPE, and scatter.

The main entry is roughly:

```python
if _should_use_ascend_split_finalize(state_cache):
    return _c128_256_512_compress_ascend_block_gather(...)

backend = _backend_kind(device_type=state_cache.device.type)
out = kv_cache if _should_reuse_zero_kv_cache(backend, num_outputs) else _zero_like_with_triton(kv_cache)

compressed = _mapped_gather_compressed(
    state_cache,
    token_to_req,
    positions,
    boundary_token_indices,
    block_table,
    block_size,
    compress_ratio,
    backend=backend,
)

_finalize_kernel[(num_outputs,)](
    compressed,
    boundary_token_indices,
    positions,
    rms_norm_weight,
    cos_sin_cache,
    kv_slot_mapping,
    out.view(torch.bfloat16),
    out,
    ...
)
```

In a multi-platform problem, dispatch itself is part of the optimization. NVIDIA, MetaX, Hygon, T-Head, TianShu, Moore, and Ascend do not behave identically. A tile choice that works on one platform is hard to apply unconditionally to another. We encountered this lesson several times.

## Two Routes: GPGPU and Ascend

Looking across the experiment records, a clear split appears: GPGPU backends and Ascend should be reasoned about separately.

On the GPGPU side, the main tension is memory traffic, temporary tensors, and address generation in hot loops. NVIDIA, MetaX, Hygon, T-Head, TianShu, and Moore have different details, but they all roughly fit the model of "a bandwidth-hungry GPU kernel written in Triton." The route that became stable was:

```text
block8 direct gather
  + online softmax
  + fewer block_table reads in the hot loop
  + backend-isolated tile/route choices
  + byte-exact finalizer
```

The first reliable 10x result came from simplifying address arithmetic with `block_size=8`:

```text
sub_b1823a55c086 / fede9cf / 7 passed / avg 10.10
```

After reconnecting the Ascend path, we also had a more protected all-platform version:

```text
sub_4c00b8a5fb5f / 30efa74e... / 7 passed / avg 10.37
```

Ascend felt like a different problem. The early pure-Triton version left random gather inside the kernel, and Ascend scores once stayed around 0.8x. That is not surprising. Ascend 910B is a DSA architecture; the boundaries among data movement, Vector compute, and Cube compute are more explicit than on GPGPU. On a GPGPU, an indirect `tl.load` may still be rescued by L1/L2 cache and coalescing. On Ascend, the same random access more easily becomes scalar Vector-side loads with poor bandwidth utilization.

<div class="notice--info" markdown="1">
<p class="notice__title">The Structural Turn in Ascend Optimization</p>

The route from below 1x to roughly 2x came from changing how data enters computation. First, CANN was used to turn random reads into a contiguous tensor. Later, the route moved to Triton scanning physical blocks directly. The former solved the "get past 1x" problem; the latter reduced the large intermediate tensor and its extra movement.
</div>

The first breakthrough came from changing the movement path. At that point, the real blocker was random gather movement; parameters like `BLOCK_T` or `num_warps` came later:

```text
CANN index_select pre-gather
    -> gathered_rows [N, C, 1024]
    -> Triton linear scan softmax/RMSNorm
    -> PyTorch quant/RoPE/scatter
```

This step moved Ascend from below 1x to around 1.15x. Its meaning was simple: on Ascend, CANN/torch-npu already has a more mature path for movement operations such as `index_select`, possibly using DMA/burst reads; Triton is better used for the later linear scan and online softmax. The downside is equally clear: `gathered_rows` is a large intermediate tensor, and the largest case expands to `[N, C, 1024]`, which must be written and then read again.

The second step was the key jump from 1.15x to 2x: replace pre-gather with block-centric gather. The problem uses `block_size=8`, and the compression window is contiguous, so most of the window can be viewed as a sequence of 8-token physical blocks. The kernel removes the preconstruction of `gathered_rows`; each program handles one output and reads `state_cache` by physical block:

```python
start_logical = first_pos // block_size
end_logical = (first_pos + compress_ratio - 1) // block_size

for log_block in range(start_logical, end_logical + 1):
    phys_block = tl.load(block_table + req * s0 + log_block * s1)
    vals = tl.load(state_cache + phys_block * state_s0 + slot[:, None] * state_s1 + dims[None, :] * state_s2)
    scores = tl.load(state_cache + phys_block * state_s0 + slot[:, None] * state_s1 + (512 + dims)[None, :] * state_s2)
    # online softmax update
```

This step pays off twice. First, it removes the writeback and reread of a huge intermediate tensor. Second, it changes access granularity from "compute many indirect addresses per token" to "scan a short sequence of consecutive slots in a physical block," which is a shape Ascend can handle more comfortably. On the platform, the first block-gather version lifted Ascend from about 1.22x to 1.85x.

Several later changes were small, but they followed the same line. The first and last physical blocks of a compression window may only be partially valid, while the middle blocks are usually full 8-token blocks. So the boundary blocks keep masks, and the middle blocks scan without masks:

```text
cr=128: 16 logical blocks, about 14 full middle blocks, roughly 87.5% of masks avoided
cr=512: 64 logical blocks, about 62 full middle blocks, roughly 96.9% of masks avoided
```

This moved Ascend to the 1.93x-1.94x range. Changing `num_warps` from 2 to 4 reached about 1.97x. Increasing `BLOCK_D` from 64 to 128 reduced the number of dimension groups from 8 to 4, and submission `sub_b240c845e12e` reached 2.02x.

The later 2.1x-2.3x range came mostly from two directions: increasing `BLOCK_D` further, and reducing scatter/finalizer overhead. With `BLOCK_D=256`, only two dimension groups remain. With `BLOCK_D=512`, one program covers the full 512 dimensions, eliminating much of the group loop and cross-group RMSNorm handling. For scatter, direct PyTorch `index_put_` still leaves noticeable overhead. A more stable route is to obtain `payload` and `scale_bytes` on the PyTorch/CANN side, then use a pure `uint8` Triton kernel for byte copy:

```text
payload = [448 bytes NOPE INT8][128 bytes RoPE BF16]
scale_bytes = [7 bytes scale][1 byte padding]
pure uint8 scatter -> paged kv_cache
```

"Pure `uint8`" matters. Ascend/Bisheng is sensitive to a mix of BF16, FP32, int32, uint8, `log2/exp2`, and stride-2 RoPE stores. Keeping quantization and RoPE on a conservative path, and letting the scatter kernel only move bytes, turned out to be more robust. This line later pushed Ascend to roughly 2.28x-2.35x.

Summarized as a table:

| Stage | Ascend score | Main change | Source of gain |
|---|---:|---|---|
| Pure Triton random gather | ~0.8x | Indirect paged-state `tl.load` | Random Vector loads are weak on DSA |
| CANN pre-gather | ~1.15x | Gather into contiguous `[N,C,1024]`, then Triton linear scan | Movement via CANN, compute via Triton |
| Block-centric gather | ~1.85x | Triton scans physical blocks directly | Remove large intermediate, improve access shape |
| Skip middle-block masks | ~1.93x | Full middle blocks avoid `tl.where` | Fewer masks and branch-shaped operations |
| `num_warps=4` | ~1.97x | Higher parallel granularity | Better match to per-program work |
| `BLOCK_D=128` | ~2.02x | Dimension groups 8 -> 4 | Fewer group loops, higher compute density |
| `BLOCK_D=256/512` + byte scatter | ~2.28x-2.35x | Fewer dimension groups, pure `uint8` scatter | Lower finalize/scatter overhead, avoid mixed-type pitfalls |

The lesson is direct: Ascend optimization starts by deciding which hardware path each part belongs on. Gather should be made as block-contiguous as possible, softmax/RMSNorm can live in Triton, quant/RoPE should respect byte correctness first, and scatter is easier to trust as a pure byte-copy kernel.

The two routes can be summarized as:

| Route | Main bottleneck | Useful direction |
|---|---|---|
| GPGPU | Large-window reads, temporary tensors, integer addressing, backend tile differences | Online softmax, block8 address simplification, backend-specific routes |
| Ascend | Random gather and fragile byte finalizer lowering on DSA | CANN or block-centric movement, larger 1D programs, conservative quant/RoPE boundaries |

This is also the engineering boundary we eventually adopted: push GPGPU optimizations actively, but do not casually touch Ascend's fragile quantization path; probe Ascend separately and merge a stage back only after it is reliable.

## Online Softmax: Streaming Away the Window

The baseline can be summarized as:

```text
first gather [N, C, 1024]
then softmax
then reduce
```

The Triton version is closer to:

```text
read source window by tiles
maintain online softmax state while reading
finally write compressed[N, 512]
```

Online softmax maintains three quantities:

```text
m   : current maximum score
den : softmax denominator
num : weighted numerator of value * softmax_weight
```

For each incoming tile:

```text
m_next   = max(m, max(scores))
old_w    = exp(m - m_next)
tile_w   = exp(scores - m_next)
num_next = num * old_w + sum(values * tile_w)
den_next = den * old_w + sum(tile_w)
```

The final output is:

```text
compressed = num / den
```

The implementation in `_gather_softmax_sum_block8_direct_online_kernel` looks like:

```python
score_max = tl.full((BLOCK_D,), -float("inf"), tl.float32)
denom = tl.zeros((BLOCK_D,), tl.float32)
numer = tl.zeros((BLOCK_D,), tl.float32)

for start in range(0, compress_ratio, BLOCK_T):
    values = tl.load(...)
    scores = tl.load(...)

    tile_max = tl.max(scores, axis=0)
    new_max = tl.maximum(score_max, tile_max)
    old_scale = tl.exp(score_max - new_max)
    weights = tl.exp(scores - new_max[None, :])

    denom = denom * old_scale + tl.sum(weights, axis=0)
    numer = numer * old_scale + tl.sum(weights * values, axis=0)
    score_max = new_max

tl.store(compressed + out_pid * out_stride + dims, numer / denom)
```

The gain is straightforward: avoid constructing a large intermediate surface. Once the window is read, reduce it near the kernel instead of materializing it.

## The Small Opening from `block_size=8`

The key step that made the result stable around 10x came from a small clue in the layout.

The official `block_size` is 8, and the compression window is contiguous. Therefore adjacent groups of eight tokens correspond to consecutive physical state blocks. A direct implementation repeatedly reads `block_table` in the hot loop:

```text
for start in range(0, C, BLOCK_T):
    logical_block = first_logical_block + start // 8 + rel_block
    physical_block = block_table[req, logical_block]
```

`block_table` itself is not large, but this logic sits in the hot loop. Its cost is more than a few integer reads: it adds address generation, masks, register use, and backend codegen pressure.

So we changed the loop to read only the starting block:

```python
first_logical_block = (boundary_pos - compress_ratio + 1) // 8
first_physical_block = tl.load(
    block_table + req * block_table_s0 + first_logical_block * block_table_s1,
).to(tl.int64)

for start in range(0, compress_ratio, BLOCK_T):
    block = first_physical_block + start // 8 + rel_block
    values = tl.load(
        state_cache
        + block[:, None] * state_s0
        + block_offset[:, None] * state_s1
        + dims[None, :] * state_s2
    )
    scores = tl.load(
        state_cache
        + block[:, None] * state_s0
        + block_offset[:, None] * state_s1
        + (512 + dims)[None, :] * state_s2
    )
```

In words:

- read the physical block at the window start once;
- derive later blocks as `first_physical_block + start // 8 + rel_block`;
- keep the mathematical semantics unchanged;
- reduce `block_table` reads and integer addressing in the hot loop.

This optimization corresponded to the first reproducible 10x submission:

```text
sub_b1823a55c086 / fede9cf / 7 passed / avg 10.10
```

The lesson is plain: when the statement gives a fixed structure, try to turn it into simpler address arithmetic first. That is often more explanatory than trying a few more tile parameters.

## The Finalizer's Sharp Edges

The finalizer writes only a few hundred bytes per output, so bandwidth is not the main issue. Correctness is.

The Triton finalizer first applies RMSNorm:

```python
mean_sq = tl.sum(vals * vals, axis=0) / 512
rrms = tl.rsqrt(mean_sq + rms_norm_eps)
normed = vals * rrms * weights
```

Then NOPE quantization:

```python
q_normed = (q_vals * rrms * q_weights).to(tl.bfloat16).to(tl.float32)
amax = tl.maximum(tl.max(tl.abs(q_normed), axis=0), 1.0e-4)
exponent = tl.ceil(tl.log2(amax * (1.0 / 127.0)))
inv_scale = tl.exp2(-exponent)
q_scaled = q_normed * inv_scale
q = tl.where(q_scaled >= 0.0, tl.floor(q_scaled), tl.ceil(q_scaled)).to(tl.int32)
q = tl.minimum(tl.maximum(q, -127), 127)
q_bytes = tl.where(q < 0, q + 256, q)
```

The RoPE section is roughly:

```python
cos_v = tl.load(cos_sin_cache + compressed_pos * cos_s0 + pair_dims * cos_s1)
sin_v = tl.load(cos_sin_cache + compressed_pos * cos_s0 + (64 // 2 + pair_dims) * cos_s1)
rot_even = even_normed * cos_v - odd_normed * sin_v
rot_odd = odd_normed * cos_v + even_normed * sin_v
rotated = tl.where(even_mask, rot_even, rot_odd)
tl.store(..., rotated.to(tl.bfloat16))
```

Several details are sensitive:

- the BF16 roundtrip must align with the reference implementation;
- negative INT8 values must be written as bytes correctly;
- scale bytes come from per-64-group power-of-two exponents;
- RoPE interleaved pairs and BF16 byte layout must match.

Ascend taught us a useful lesson here: Triton routes that generate FP32 `quant_tmp` may produce INT8 byte mismatches, while preserving a real BF16 memory boundary is more reliable. The current Ascend route is conservative for that reason: correctness comes first.

## Routing Across Chips

The competition covers multiple backends. A route that works on one platform often cannot be copied to another. We eventually preferred making backend differences explicit in dispatch, rather than hoping one configuration would run everywhere.

Current experience roughly looks like:

| Platform | Current experience |
|---|---|
| NVIDIA | D32 is useful, but best kept inside an NVIDIA-like route |
| MetaX | D64 direct-online is more stable; avoid borrowing the NVIDIA D32 conclusion blindly |
| Hygon | D64 direct-online; CR512 T256 is a useful local lever |
| T-Head | After the platform recovered, direct-online plus zeroed-cache reuse helped |
| TianShu | Sensitive to tile/warp choices; safer to move conservatively |
| Moore | Cache hints showed signal, but stability still needs careful validation |
| Ascend | Quant/RoPE finalization is fragile and should be advanced separately |

The code also tries to keep platform-specific entries separate:

```python
def _nvidia_gather(...):
    # NVIDIA: D=32 route
    ...

def _hygon_gather(...):
    # Hygon: D=64 direct_online
    ...

def _metax_gather(...):
    # MetaX: D=64 direct_online
    ...
```

This design is a bit boring, but it reduces the chance that a small win on one platform causes a large regression on another. For a multi-backend competition, this plain engineering separation is valuable.

## Lessons Worth Keeping

Looking back, the most useful directions are:

| Direction | Meaning |
|---|---|
| Avoid large intermediate surfaces | Avoid temporary tensors such as `[N, C, 1024]` whenever possible |
| Stream reductions | Use online softmax to compress the window while reading it |
| Exploit fixed structure | `block_size=8` simplifies physical-block addressing |
| Tune with a ledger | Before tuning a tile, ask which cost it reduces |
| Isolate backends | Separate backend routes to avoid one platform's experience hurting another |
| Preserve byte semantics | Treat byte-exact finalization as a boundary, especially BF16, INT8, scale, and RoPE |

Some directions deserve caution:

| Caution | Reason |
|---|---|
| Tile roulette without a hypothesis | Small parameter wins may be accidental and not transferable |
| Spreading NVIDIA D32 to MetaX/Hygon | Register, cache, and codegen behavior differ |
| Aggressively fusing quant/RoPE on Ascend | This area easily triggers byte mismatches |
| Relying on checker/cache outlier scores | Without an explainable kernel mechanism, it should not be the final route |
| Looking only at local CUDA timing | Remote multi-platform results are the actual competition constraint |

## Code Snapshot

I have also put the stable non-outlier source snapshot in a small GitHub repository:

<div class="kg-challenge-card" markdown="1">
  <div>
    <p class="kg-challenge-label">Stable source repository</p>
    <p class="kg-challenge-desc"><code>sub_64c96b412ccc</code>, submitted on June 13, 2026 Beijing time, passed 7/7 with an average speedup of about <code>10.21x</code>.</p>
  </div>
  <a class="kg-challenge-button" href="https://github.com/TankTechnology/kernelgen-challenge-8-stable-10x" target="_blank" rel="noopener">View on GitHub</a>
</div>

This is not the later 200x-style MetaX outlier. I am sharing it mainly as a record of the optimization ideas in this post: backend-isolated routes, `block_size=8` address simplification, and a conservative Ascend path that puts correctness ahead of a more aggressive Triton finalizer.

It should be read with some humility. The code was tuned for the competition environment and the official test surface at that time. In particular, it assumes the official `block_size=8` setting, the block-table regularity observed in the benchmark data, and an output cache surface compatible with the platform checker. A small local review found that more general inputs, such as non-contiguous physical block tables, non-zero initial `kv_cache`, or non-official `block_size` values, can break byte-level equivalence with the reference implementation. The snapshot is therefore a useful competition artifact, not a general-purpose KV cache compression library.

<div class="notice--warning" markdown="1">
<p class="notice__title">About Outlier Scores</p>

MetaX once produced outlier signals such as 200x/277x. We later treated them as diagnostic signals of the checker/timing surface rather than a robust kernel mechanism. They reminded us that platform measurement can be complicated, but they were not suitable as the foundation of the final implementation.
</div>

## Closing

If this optimization is compressed into a few lines, it would be:

```text
First understand the byte contract.
Then find the largest intermediate tensor and the hottest inner loop.
Stream when possible; reduce address work when possible.
Separate multi-platform routes; retest outlier scores.
```

From this angle, the 10x result is not mysterious. It is more like a sequence of ordinary but important cleanups: understand the baseline computation surface, account for memory in Triton programs, use the fixed `block_size=8`, and handle different chips separately.

This route may not be elegant, but for us it was relatively reliable and easier to keep pushing forward.

</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

<div class="kg-challenge-card kg-challenge-card--lead">
  <div>
    <p class="kg-challenge-label">官方题面入口</p>
    <p class="kg-challenge-desc">Challenge 8：<a class="kg-challenge-url" href="https://kernelgen.flagos.io/challenge/8?lang=zh&tab=readme" target="_blank" rel="noopener">https://kernelgen.flagos.io/challenge/8?lang=zh&tab=readme</a></p>
  </div>
  <a class="kg-challenge-button" href="https://kernelgen.flagos.io/challenge/8?lang=zh&tab=readme" target="_blank" rel="noopener">打开 Challenge 8</a>
</div>

这篇文章记录的是 KernelGen Challenge 8 的一次优化过程。这是我一边做题、一边补课之后整理出的笔记。题目本身并不长，核心函数也只有一个；但真正下手之后会发现，它牵出了 Attention、KV Cache、Triton DSL、GPU 内存访问、量化字节布局以及多后端差异等一串问题。

我们先不急着看代码。一个自然的问题是：为什么一个最终只写几百个字节的 KV Cache 压缩算子，值得专门写 kernel 去优化？

粗略的答案是：在长上下文解码中，KV Cache 已经接近推理状态本身。它占显存，也吃带宽。压缩它、搬运它、写回它，这些细节都会落到真实的 decoding 延迟上。本文就从这里开始，慢慢走到具体的 Triton 实现。

文中涉及的实现和实验，来自我们在比赛期间的提交记录、局部 benchmark 和几轮独立实验。下面只保留那些能解释实现选择的材料。

<div class="notice--primary" markdown="1">
<p class="notice__title">本文的主线</p>

前半部分先把 Attention、KV Cache 和题目里的字节布局讲清楚；中间用公式拆开一个输出 slot 的生成过程；后半部分再回到工程实现，分别讨论 GPGPU 与 Ascend 两条优化路线。
</div>

## 从 Attention 说起

标准的 Dot-Product Attention 可以写成：

$$
\boldsymbol{o}_i=\sum_j a_{i,j}\boldsymbol{v}_j,\qquad
a_{i,j}=\frac{\exp(s_{i,j})}{\sum_k \exp(s_{i,k})},\qquad
s_{i,j}=\frac{\boldsymbol{q}_i^{\top}\boldsymbol{k}_j}{\sqrt{d}}.
$$

这里 $\boldsymbol{q}_i$ 是当前位置的 Query，$\boldsymbol{k}_j,\boldsymbol{v}_j$ 是被关注位置的 Key 和 Value。对于 decoder-only 模型，生成第 $i$ 个 token 时只能看见历史，也就是 $j\leq i$。

prefill 阶段通常比较规整，整段输入的 $Q,K,V$ 可以一次性算出来，后面交给矩阵化的 attention kernel。decoding 阶段就没那么整齐了：模型每次只生成一个新 token，但这个新 token 仍然要 attend 到此前所有 token。第 $t$ 步大致是：

$$
\boldsymbol{q}_t
\quad\text{attends to}\quad
\{\boldsymbol{k}_1,\ldots,\boldsymbol{k}_t\},\quad
\{\boldsymbol{v}_1,\ldots,\boldsymbol{v}_t\}.
$$

如果每一步都重新从历史 hidden states 计算 $K,V$，重复计算会非常可观。于是实际推理时会把历史 token 的 $K,V$ 存下来，后续步骤直接读取，这就是 KV Cache。

从这个角度看，KV Cache 是 decoding 的状态变量。它换掉了一部分重复计算，也把压力转移到了显存容量和内存带宽上。

## KV Cache 的账

如果上下文长度是 $L$，KV head 数是 $h_{kv}$，每个 head 的 key/value 维度分别是 $d_k,d_v$，那么 KV Cache 的规模大致是：

$$
O\big(L\cdot h_{kv}\cdot(d_k+d_v)\big).
$$

这是容量账。到了 decoding 阶段，还要考虑读带宽：每生成一个 token，attention 都要读历史的 Key/Value。$L$ 变长之后，很多时候瓶颈会逐渐从算力转到内存系统。

很多 Attention 变体都可以从这条线索理解。MHA、MQA、GQA、MLA 等方案形式不同，但都在反复处理一个朴素问题：历史信息究竟要用多少字节保存，才比较合算？

KernelGen 这个题没有要求我们重新设计 Attention 架构。题目给定了一种 DeepSeek 风格的压缩规则，我们要做的事情更工程一些：

```text
一段历史 state window
    -> 一个 512 维压缩向量
    -> 一段打包后的 KV-cache 字节
```

这就进入了本文的主题：在保证字节语义正确的前提下，把这段压缩尽量做快。

## 比赛背景与题面

这道题来自 FlagOS KernelGen 48 小时算子赏金挑战赛北京站，题名是 `c128_256_512_compress`，题面描述为 DeepSeek V4 长上下文推理中的 KV Cache 压缩。提交物是一个 Python 文件，函数名和参数要与题面一致，文件编码为 UTF-8，平台环境要求 Python 3 与 Triton 3.5 兼容。比赛平台会把同一份 `solution.py` 放到多个后端上测试，所以它既是一个 kernel 优化题，也是一个多后端工程题。

平台大致覆盖：

| 类别 | 平台 |
|---|---|
| GPGPU 路线 | NVIDIA、沐曦 MetaX、海光、天数、摩尔线程、平头哥 |
| DSA/NPU 路线 | 华为昇腾 Ascend |

benchmark 的形状也比较固定。`compress_ratio` 只取 128、256、512，`num_reqs` 与 `total_tokens` 组合成 12 组 case：

| `num_reqs` | `total_tokens` | `compress_ratio` |
|---:|---:|---:|
| 1 | 8192 | 128 |
| 4 | 32768 | 128 |
| 8 | 65536 | 128 |
| 8 | 131072 | 128 |
| 1 | 8192 | 256 |
| 4 | 32768 | 256 |
| 8 | 65536 | 256 |
| 8 | 131072 | 256 |
| 1 | 8192 | 512 |
| 4 | 32768 | 512 |
| 8 | 65536 | 512 |
| 8 | 131072 | 512 |

这几个数字很重要。它们意味着我们面对的是一个结构高度固定的压缩任务，而非任意 shape 的通用算子。固定结构会带来限制，也会留下可利用的缝隙。后面 `block_size=8` 的优化，就是从这个固定结构里挖出来的。

## 题目里的压缩算子

题目函数是：

```python
def c128_256_512_compress(
    state_cache,
    token_to_req,
    positions,
    boundary_token_indices,
    block_table,
    rms_norm_weight,
    cos_sin_cache,
    kv_slot_mapping,
    kv_cache,
    block_size,
    compress_ratio,
    rms_norm_eps=1.0e-6,
):
    ...
```

可以先把它理解成一个“窗口压缩器”：对每个 `boundary_token_indices` 指定的 token，取它前面长度为 `compress_ratio` 的连续窗口，把窗口中的 state rows 压成一个新的 KV Cache slot。

<div class="notice--info" markdown="1">
<p class="notice__title">关于 gather 与 scatter</p>

在算子实现里，gather 指按索引从源张量读取一组位置，并组成当前计算所需的工作集。本题里的 gather，是根据 request、position 和 block table 找到压缩窗口里的 state-cache 物理行，再把这些行读出来参与 softmax 压缩。scatter 是反向写入过程：已经算好的 payload 和 scale bytes，会按照 kv slot 写回到 paged KV cache 的指定位置。
</div>

几个常量先列出来，后面会反复用到：

| 名字 | 数值 | 含义 |
|---|---:|---|
| `HEAD_DIM` | 512 | 压缩后的向量宽度 |
| `ROPE_HEAD_DIM` | 64 | 最后 64 维用于 RoPE，存成 BF16 字节 |
| `NOPE_HEAD_DIM` | 448 | 前 448 维做 INT8 量化 |
| `KV_BLOCK_SIZE` | 64 | 一个 KV page 有 64 个 slot |
| `TOKEN_STRIDE` | 576 | 每个 slot 的 payload 字节数 |
| `SCALE_DIM` | 8 | 每个 slot 的 scale 字节区 |

一个输出 slot 的 payload 是：

```text
[448 bytes INT8 NOPE][128 bytes BF16 RoPE]
```

scale 区是：

```text
[7 bytes active scale][1 byte padding]
```

<div class="notice--info" markdown="1">
<p class="notice__title">字节级正确性约束</p>

最后比对的是 KV Cache 的字节布局。中间浮点值看起来接近还不够，INT8 value bytes、scale bytes、RoPE BF16 bytes、page/slot scatter 位置都要合规。比赛里很多看似“只差一点”的尝试，最后都败在这些字节细节上。
</div>

## 一个输出如何生成

下面把一个输出拆开写。公式虽然多，但它们只是在回答三件事：窗口在哪里，怎样压成 512 维，最后怎样打包回 KV Cache。

设当前 boundary token 为 $b$，窗口长度为 $C=\mathtt{compress\_ratio}$，head 维度为 $D=512$。它对应的 request 和位置是：

$$
r=\mathtt{token\_to\_req}[b],\qquad
p=\mathtt{positions}[b].
$$

窗口中的第 $i$ 个历史 token 位置为：

$$
t_i=p-C+1+i,\qquad 0\le i<C.
$$

每个 $t_i$ 要通过 paged state-cache 找到物理行。令 $B=\mathtt{block\_size}$，题目里实际为 8，则：

$$
\ell_i=\left\lfloor\frac{t_i}{B}\right\rfloor,\qquad
o_i=t_i\bmod B,
$$

$$
g_i=\mathtt{block\_table}[r,\ell_i],\qquad
\mathtt{row}_i=g_iB+o_i.
$$

`state_cache[row_i]` 的前 512 维是 value，后 512 维是 score。写成公式就是：

$$
v_{i,d}=\mathtt{state\_cache}[\mathtt{row}_i,d],
\qquad
s_{i,d}=\mathtt{state\_cache}[\mathtt{row}_i,D+d],
\qquad 0\le d<D.
$$

然后对每个维度 $d$，沿着窗口长度 $C$ 做 softmax 加权和：

$$
\alpha_{i,d}=\frac{\exp(s_{i,d})}{\sum_{j=0}^{C-1}\exp(s_{j,d})},
\qquad
c_d=\sum_{i=0}^{C-1}\alpha_{i,d}v_{i,d}.
$$

这里有一个小细节：softmax 是 per-dimension 的。换句话说，512 个维度各自有一组长度为 $C$ 的权重；每个维度都在自己的窗口里归一化。

得到 512 维压缩向量 $\boldsymbol{c}$ 后，先做 RMSNorm。令权重为 $w_d$，则：

$$
\rho=\left(\frac{1}{D}\sum_{d=0}^{D-1}c_d^2+\varepsilon\right)^{-1/2},
\qquad
y_d=c_d\rho w_d.
$$

前 448 维进入 NOPE 量化。参考实现会先做一次 BF16 roundtrip。对第 $g$ 个 64 维 group，令：

$$
z_d=\operatorname{fp32}(\operatorname{bf16}(y_d)),
\qquad
G_g=\{64g,\ldots,64g+63\},
$$

$$
a_g=\max\left(\max_{d\in G_g}|z_d|,10^{-4}\right),
\qquad
e_g=\left\lceil\log_2\frac{a_g}{127}\right\rceil.
$$

量化值和 scale byte 为：

$$
q_d=\operatorname{int8}\left(\operatorname{clip}(z_d\,2^{-e_g},-127,127)\right),
\qquad
\mathtt{scale}_g=\operatorname{uint8}(e_g+127).
$$

最后 64 维做 GPT-J interleaved RoPE。令 $j=0,\ldots,31$：

$$
u_j=y_{448+2j},\qquad
w_j=y_{448+2j+1},
\qquad
p_c=\left\lfloor\frac{p}{C}\right\rfloor C.
$$

从 `cos_sin_cache[p_c]` 读取 $\cos_j,\sin_j$ 后：

$$
\tilde u_j=u_j\cos_j-w_j\sin_j,
\qquad
\tilde w_j=w_j\cos_j+u_j\sin_j.
$$

写回时再通过 `kv_slot_mapping[b]` 找到目标 page 和 slot：

```text
slot        = kv_slot_mapping[b]
page        = slot // 64
slot_offset = slot % 64
payload_col = slot_offset * 576
scale_col   = 64 * 576 + slot_offset * 8
```

把这些串起来，算子大概就是：

```text
window rows
  -> per-dim softmax weighted sum
  -> RMSNorm
  -> NOPE INT8 bytes + scale bytes
  -> RoPE BF16 bytes
  -> paged KV-cache scatter
```

## baseline 的直观写法

官方 baseline 很适合作为语义参考。它先把窗口中所有要读的行 gather 出来：

```python
flat_idx = (block_numbers * block_size + block_offsets).reshape(-1)
all_rows = state_cache.reshape(-1, 2 * HEAD_DIM)[flat_idx].reshape(
    num_outputs, compress_ratio, 2 * HEAD_DIM
)

kv_vals = all_rows[:, :, :HEAD_DIM]
scores = all_rows[:, :, HEAD_DIM:]
compressed = (kv_vals * F.softmax(scores, dim=1)).sum(dim=1)
```

写法很干净，问题也很直观：它会构造一个逻辑上的巨大中间张量：

```text
[num_outputs, compress_ratio, 1024]
```

如果 `compress_ratio=512`，单个输出的 source traffic 约为：

```text
512 * 1024 * sizeof(float) ~= 2 MiB
```

而最终写出的 payload + scale 不到 600 字节。这样一对比，就能看出主要压力大概集中在几个地方：

| 账本 | 主要压力 |
|---|---|
| `state_cache` 读取 | 窗口越大，source traffic 越重 |
| 中间张量 | `all_rows` 会把内存流量放大一轮 |
| paged layout | `block_table` 与 slot 计算带来整数寻址开销 |
| finalizer | 数据量小，但 BF16、INT8、scale、RoPE 的字节语义很尖锐 |

这个判断并不复杂，但它给了后面优化的方向：少搬大张量，少做重复寻址，能流式就尽量流式。

## 稍微补一点 Triton 和 GPU 的背景

Triton 是一个面向 GPU kernel 的 Python DSL。它的抽象层次大致位于 PyTorch 和 CUDA C 之间：我们写一个个 **program**，每个 program 负责一块 tile；编译器再把这些 tile 映射到底层 GPU 执行模型。

这里的 tile 可以理解成“实现上的小工作块”。它属于实现层的组织方式：为了让内存访问、寄存器使用和并行粒度更可控，我们主动把大问题切成小矩形。

<div class="notice--info" markdown="1">
<p class="notice__title">实现粒度：tile</p>

tile 是 kernel 实现时切出来的一块固定工作量。矩阵乘里的 tile 通常对应矩阵的一个小矩形；本题里的 tile 更接近“若干个历史 token × 若干个 head 维度”的片段。把大窗口切成 tile 后，kernel 可以分块读取、分块归约，尽量让数据在寄存器或 cache 附近完成消费。
</div>

拿本题来说，完整的计算面可以想成：

```text
outputs x compress_window x head_dim
```

Triton kernel 不会让一个 program 一口气处理全部维度。更常见的做法是让一个 program 负责某个 output 的一段 head dimension，并在窗口维度上分块读取：

```text
BLOCK_T: 一次读取多少个 source token
BLOCK_D: 一次处理多少个 head dimension
```

所以一次 `tl.load` 读到的核心 tile 通常是：

```text
[BLOCK_T, BLOCK_D]
```

例如 `BLOCK_T=128, BLOCK_D=64` 时，一个 program 会在一个 boundary token 上，处理 64 个维度，并且一次扫 128 个历史 token。`compress_ratio=512` 时，它要扫 4 个这样的 token tile；512 维 head 则通常由 8 个 dimension tile 覆盖。

tile 大小会影响很多细节：`BLOCK_T` 大一些，循环次数少一些，但单次 load 和 mask 更重；`BLOCK_D` 大一些，维度并行更多，但 accumulator 和寄存器压力也会上来。所以调 tile 不能简单取“越大越好”，更像是在后端寄存器、cache、内存事务和编译器 lowering 之间找平衡。

在本题里，一个 program 可以对应：

```text
某个 output slot
某一段 head dimension
某一段 compress window
```

典型代码大概长这样：

```python
out_pid = tl.program_id(0)
group_pid = tl.program_id(1)
dims = group_pid * BLOCK_D + tl.arange(0, BLOCK_D)
lanes = tl.arange(0, BLOCK_T)
```

`tl.program_id` 决定当前 program 负责哪块输出，`tl.arange` 生成一组向量化 lane。随后用 `tl.load` 读一个二维 tile：

```python
values = tl.load(
    state_cache
    + block[:, None] * state_s0
    + block_offset[:, None] * state_s1
    + dims[None, :] * state_s2
)
```

这里的 `values` 逻辑上是 `[BLOCK_T, BLOCK_D]`。我们在 Python 里写的是张量化表达，编译器会把它降到 GPU 后端。

做这类 kernel 时，常见的账本大概有几项：

| 项目 | 在本题中的含义 |
|---|---|
| 全局内存读取 | `state_cache` 很大，读多了容易被带宽限制 |
| 地址生成 | `block_table` 查询和整数索引会占指令、占寄存器 |
| 寄存器压力 | `BLOCK_D` 越大，accumulator 越多，单个 program 越重 |
| 并行粒度 | `BLOCK_T` 太小会多循环，太大又可能增加调度压力 |
| 临时张量 | PyTorch baseline 的 `all_rows` 清楚易懂，也会推高内存流量 |

后面两个主要优化，online softmax 和 block8 physical-block arithmetic，其实都可以放进这个账本里理解：前者减少中间张量，后者减少热循环里的寻址工作。

## 我们采用的分解

当前实现大致分成两段：

```text
Triton gather/reduce -> compressed[outputs, 512]
Triton/PyTorch-safe finalize -> packed kv_cache bytes
```

第一段从 paged state-cache 中流式读取窗口，做 softmax 加权和，得到 FP32 的 `compressed`。第二段做 RMSNorm、NOPE 量化、RoPE 和 scatter。

主入口大致是：

```python
if _should_use_ascend_split_finalize(state_cache):
    return _c128_256_512_compress_ascend_block_gather(...)

backend = _backend_kind(device_type=state_cache.device.type)
out = kv_cache if _should_reuse_zero_kv_cache(backend, num_outputs) else _zero_like_with_triton(kv_cache)

compressed = _mapped_gather_compressed(
    state_cache,
    token_to_req,
    positions,
    boundary_token_indices,
    block_table,
    block_size,
    compress_ratio,
    backend=backend,
)

_finalize_kernel[(num_outputs,)](
    compressed,
    boundary_token_indices,
    positions,
    rms_norm_weight,
    cos_sin_cache,
    kv_slot_mapping,
    out.view(torch.bfloat16),
    out,
    ...
)
```

多平台题目里，dispatch 本身也算优化的一部分。NVIDIA、MetaX、Hygon、T-Head、TianShu、Moore、Ascend 的后端行为并不完全一致，一个平台上的 tile choice 很难无条件推广到另一个平台。这个教训我们后面反复遇到。

## 两条路线：GPGPU 与 Ascend

把几轮实验记录放在一起看，一个比较清晰的分界会浮出来：GPGPU 后端和 Ascend 后端最好分开想。

GPGPU 这边的主要矛盾，是 memory traffic、临时张量和热循环寻址。NVIDIA、MetaX、Hygon、T-Head、TianShu、Moore 的细节当然不同，但它们更接近“用 Triton 写一个吃带宽的 GPU kernel”这个模型。最终比较稳定的主线是：

```text
block8 direct gather
  + online softmax
  + 减少 block_table 热循环读取
  + 后端隔离的 tile/route
  + byte-exact finalizer
```

其中第一版可靠 10x 来自 `block_size=8` 的地址简化：

```text
sub_b1823a55c086 / fede9cf / 7 passed / avg 10.10
```

后续再把 Ascend 路线接回来，得到过一个更稳的全平台保护版本：

```text
sub_4c00b8a5fb5f / 30efa74e... / 7 passed / avg 10.37
```

Ascend 这边则更像另一道题。最早的纯 Triton 写法把随机 gather 留在 kernel 里，结果 Ascend 分数一度只有 0.8x 左右。这个结果并不奇怪：Ascend 910B 是 DSA 架构，数据搬运、Vector 计算、Cube 计算的边界比 GPGPU 更显式。GPGPU 上一个 `tl.load` 间接寻址，常常还能靠 L1/L2 cache 和 coalescing 托住；Ascend 上同样的随机访问更容易落到 Vector 侧的标量 load，带宽利用率就不漂亮。

<div class="notice--info" markdown="1">
<p class="notice__title">Ascend 优化的结构性转折</p>

从 1x 以下走到 2x 左右，核心在于改变数据进入计算的方式：先借助 CANN 把随机读取变成连续张量，后来进一步改成 Triton 按 physical block 直接扫描。前者解决“能过 1x”的问题，后者减少了巨大中间张量带来的额外搬运。
</div>

第一步突破来自数据搬运方式的变化；当时真正挡路的是随机 gather 的搬运路径，`BLOCK_T` 或 `num_warps` 这类参数还排在后面：

```text
CANN index_select pre-gather
    -> gathered_rows [N, C, 1024]
    -> Triton linear scan softmax/RMSNorm
    -> PyTorch quant/RoPE/scatter
```

这一步把 Ascend 从 1x 以下拉到 1.15x 左右。它的意义在于先承认一个事实：在 Ascend 上，CANN/torch-npu 对 `index_select` 这类搬运有更成熟的路径，可能走到 DMA/burst read；而 Triton kernel 更适合接手后面的线性扫描和 online softmax。缺点也很明显，`gathered_rows` 是一个很大的中间张量，最大 case 会膨胀到 `[N, C, 1024]`，搬完还要再读一遍。

第二步是从 1.15x 走到 2x 的关键：把 pre-gather 改成 block-centric gather。题目里 `block_size=8`，压缩窗口又连续，所以窗口大部分时候可以看成一串 8-token physical block。kernel 去掉预先构造 `gathered_rows` 的步骤，让每个 program 负责一个输出，直接按物理块读 `state_cache`：

```python
start_logical = first_pos // block_size
end_logical = (first_pos + compress_ratio - 1) // block_size

for log_block in range(start_logical, end_logical + 1):
    phys_block = tl.load(block_table + req * s0 + log_block * s1)
    vals = tl.load(state_cache + phys_block * state_s0 + slot[:, None] * state_s1 + dims[None, :] * state_s2)
    scores = tl.load(state_cache + phys_block * state_s0 + slot[:, None] * state_s1 + (512 + dims)[None, :] * state_s2)
    # online softmax update
```

这一步的收益有两层。首先，少了一次巨大中间张量的写回与再读取。其次，访问粒度从“按 token 算一堆间接地址”变成“按 physical block 扫一小段连续 slot”，更贴近 Ascend 上可接受的访存形状。平台记录里，初版 block-gather 直接把 Ascend 从约 1.22x 推到 1.85x。

随后几个改动看起来小，但都沿着同一条线走。压缩窗口的首尾 block 可能只有部分 slot 有效，中间 block 基本都是完整的 8-token block。于是首尾保留 mask，中间块直接无 mask 扫描：

```text
cr=128: 16 个逻辑块，约 14 个中间块完整，可少做 87.5% 的 mask
cr=512: 64 个逻辑块，约 62 个中间块完整，可少做 96.9% 的 mask
```

这让 Ascend 继续到 1.93x 到 1.94x 一带。再把 `num_warps` 从 2 调到 4，平台上到 1.97x；把 `BLOCK_D` 从 64 放到 128，维度分组数从 8 组降到 4 组，提交 `sub_b240c845e12e` 到了 2.02x。

更后面的 2.1x 到 2.3x，主要来自两个方向：继续放大 `BLOCK_D`，以及减少 scatter/finalizer 的开销。`BLOCK_D=256` 时只剩 2 组维度，`BLOCK_D=512` 时一个 program 覆盖完整 512 维，少了很多 group loop 和跨组 RMSNorm 处理。scatter 方面，直接用 PyTorch `index_put_` 会留下明显开销；一个更稳的办法是先在 PyTorch/CANN 侧得到 `payload` 和 `scale_bytes`，再用一个纯 `uint8` Triton kernel 做 byte copy：

```text
payload = [448 bytes NOPE INT8][128 bytes RoPE BF16]
scale_bytes = [7 bytes scale][1 byte padding]
pure uint8 scatter -> paged kv_cache
```

这里“纯 `uint8`”很重要。Ascend/Bisheng 对混合 BF16、FP32、int32、uint8、`log2/exp2`、stride-2 RoPE store 的组合比较敏感；把量化和 RoPE 保持在更保守的路径里，再让 scatter kernel 只做字节搬运，反而更稳。后续实验线里，这条路线把 Ascend 推到 2.28x 到 2.35x 附近。

把 Ascend 这段压缩成一张表，大概是：

| 阶段 | 平台 Ascend | 主要变化 | 收益来源 |
|---|---:|---|---|
| 纯 Triton 随机 gather | ~0.8x | `tl.load` 间接读 paged state | DSA 上随机 Vector load 不占优 |
| CANN pre-gather | ~1.15x | 先 gather 成连续 `[N,C,1024]`，Triton 线性扫描 | 搬运交给 CANN，计算交给 Triton |
| block-centric gather | ~1.85x | Triton 按 physical block 直接扫描 | 去掉巨大中间张量，访问更连续 |
| skip middle-block mask | ~1.93x | 中间完整 block 不做 `tl.where` | 少 mask、少分支形状压力 |
| `num_warps=4` | ~1.97x | 提高并行粒度 | 更适合每 program 的工作量 |
| `BLOCK_D=128` | ~2.02x | 维度组数 8 -> 4 | 降低 group loop，提升计算密度 |
| `BLOCK_D=256/512` + byte scatter | ~2.28x-2.35x | 更少维度分组，纯 `uint8` scatter | 减少 finalize/scatter 开销，避开混合类型坑 |

这条路线给我们的启发很直接：Ascend 优化要先判断每一段任务放在哪条硬件路径上更合适。gather 要尽量变成连续块扫描，softmax/RMSNorm 可以放进 Triton，quant/RoPE 先尊重字节正确性，scatter 则拆成 Bisheng 更容易接受的纯字节 kernel。

这两条路线的差别可以粗略写成：

| 路线 | 主要瓶颈 | 有效方向 |
|---|---|---|
| GPGPU | 大窗口读取、临时张量、整数寻址、backend tile 差异 | online softmax、block8 地址简化、按平台隔离 route |
| Ascend | DSA 上随机 gather/byte finalizer lowering 脆弱 | CANN 或 block-centric 数据搬运、1D 大粒度 program、保守 quant/RoPE 边界 |

这也是我们后来定下的工程边界：GPGPU 优化可以积极推进，但不要顺手改 Ascend fragile quant；Ascend 要单独做 probe，能证明一个阶段可靠，再把它接回来。

## online softmax：把窗口流式压掉

baseline 的流程可以概括为：

```text
先 gather 出 [N, C, 1024]
再 softmax
再 reduce
```

Triton 版本更接近：

```text
按 tile 读取 source window
边读边维护 online softmax 状态
最后写出 compressed[N, 512]
```

online softmax 维护三个量：

```text
m   : 当前最大 score
den : softmax denominator
num : value * softmax_weight 的加权分子
```

每来一个 tile：

```text
m_next   = max(m, max(scores))
old_w    = exp(m - m_next)
tile_w   = exp(scores - m_next)
num_next = num * old_w + sum(values * tile_w)
den_next = den * old_w + sum(tile_w)
```

最后输出：

```text
compressed = num / den
```

对应实现可以看 `_gather_softmax_sum_block8_direct_online_kernel`：

```python
score_max = tl.full((BLOCK_D,), -float("inf"), tl.float32)
denom = tl.zeros((BLOCK_D,), tl.float32)
numer = tl.zeros((BLOCK_D,), tl.float32)

for start in range(0, compress_ratio, BLOCK_T):
    values = tl.load(...)
    scores = tl.load(...)

    tile_max = tl.max(scores, axis=0)
    new_max = tl.maximum(score_max, tile_max)
    old_scale = tl.exp(score_max - new_max)
    weights = tl.exp(scores - new_max[None, :])

    denom = denom * old_scale + tl.sum(weights, axis=0)
    numer = numer * old_scale + tl.sum(weights * values, axis=0)
    score_max = new_max

tl.store(compressed + out_pid * out_stride + dims, numer / denom)
```

这个改动的收益很朴素：少构造一个大中间面，窗口读进来之后尽量就地归约掉。它不改变数学语义，只改变计算的组织方式。

## block_size=8 带来的小捷径

后来把结果稳定推到 10x 附近的关键一步，来自题目布局里的一个小线索。

官方 `block_size` 是 8，压缩窗口又是连续的。于是相邻 8 个 token 对应连续的 physical state block。朴素写法会在热循环里反复查 `block_table`：

```text
for start in range(0, C, BLOCK_T):
    logical_block = first_logical_block + start // 8 + rel_block
    physical_block = block_table[req, logical_block]
```

`block_table` 本身不大，可这段逻辑出现在热循环里，代价不止是读取几个整数，还包括地址生成、mask、寄存器和后端 codegen 压力。

于是我们改成只查窗口起点：

```python
first_logical_block = (boundary_pos - compress_ratio + 1) // 8
first_physical_block = tl.load(
    block_table + req * block_table_s0 + first_logical_block * block_table_s1,
).to(tl.int64)

for start in range(0, compress_ratio, BLOCK_T):
    block = first_physical_block + start // 8 + rel_block
    values = tl.load(
        state_cache
        + block[:, None] * state_s0
        + block_offset[:, None] * state_s1
        + dims[None, :] * state_s2
    )
    scores = tl.load(
        state_cache
        + block[:, None] * state_s0
        + block_offset[:, None] * state_s1
        + (512 + dims)[None, :] * state_s2
    )
```

也就是：

- 先查一次窗口起点的 physical block；
- 后续 block 用 `first_physical_block + start // 8 + rel_block` 推出来；
- 数学语义保持不变；
- 热循环里的 `block_table` 查询和整数寻址少了很多。

这个优化对应第一个可复现的 10x 提交：

```text
sub_b1823a55c086 / fede9cf / 7 passed / avg 10.10
```

它的启发也比较朴素：如果题目给了固定结构，先试着把这部分结构变成更简单的地址计算。很多时候，这比继续试几个 tile 参数更有解释力。

## Finalizer 的小心之处

finalizer 每个输出只写几百字节，带宽压力有限；但它是正确性风险最高的部分之一。

Triton finalizer 先做 RMSNorm：

```python
mean_sq = tl.sum(vals * vals, axis=0) / 512
rrms = tl.rsqrt(mean_sq + rms_norm_eps)
normed = vals * rrms * weights
```

然后处理 NOPE 量化：

```python
q_normed = (q_vals * rrms * q_weights).to(tl.bfloat16).to(tl.float32)
amax = tl.maximum(tl.max(tl.abs(q_normed), axis=0), 1.0e-4)
exponent = tl.ceil(tl.log2(amax * (1.0 / 127.0)))
inv_scale = tl.exp2(-exponent)
q_scaled = q_normed * inv_scale
q = tl.where(q_scaled >= 0.0, tl.floor(q_scaled), tl.ceil(q_scaled)).to(tl.int32)
q = tl.minimum(tl.maximum(q, -127), 127)
q_bytes = tl.where(q < 0, q + 256, q)
```

RoPE 部分大概是：

```python
cos_v = tl.load(cos_sin_cache + compressed_pos * cos_s0 + pair_dims * cos_s1)
sin_v = tl.load(cos_sin_cache + compressed_pos * cos_s0 + (64 // 2 + pair_dims) * cos_s1)
rot_even = even_normed * cos_v - odd_normed * sin_v
rot_odd = odd_normed * cos_v + even_normed * sin_v
rotated = tl.where(even_mask, rot_even, rot_odd)
tl.store(..., rotated.to(tl.bfloat16))
```

这里几个细节都比较敏感：

- BF16 roundtrip 要和参考实现对齐；
- INT8 负数写成 byte 时不能让符号处理出错；
- scale byte 来自 per-64 group 的 power-of-two exponent；
- RoPE 的 interleaved pair 和 BF16 byte layout 要一致。

Ascend 上的问题给我们上了一课：Triton 生成 FP32 `quant_tmp` 的路径会引出 INT8 byte mismatch，而保留真实 BF16 memory boundary 的路线更稳。于是当前 Ascend route 比较保守，先把正确性放在前面。

## 多芯片下的分路

比赛覆盖多个后端，一个平台上有效的 route，经常不能直接复制到另一个平台。我们最后更倾向于把平台差异显式写进 dispatch，少依赖“一套配置跑天下”的假设。

目前的经验大致是：

| 平台 | 当前经验 |
|---|---|
| NVIDIA | D32 有价值，但最好限制在 NVIDIA-like route |
| MetaX | D64 direct-online 更稳，避免借用 NVIDIA D32 结论 |
| Hygon | D64 direct-online，CR512 T256 是有价值的局部 lever |
| T-Head | 平台恢复后 direct-online + zeroed cache reuse 有正收益 |
| TianShu | 对 tile/warp 敏感，宜保守推进 |
| Moore | cache hint 有过信号，稳定性还需要更谨慎验证 |
| Ascend | quant/RoPE finalization 较脆，单独推进更安心 |

代码上也尽量让每个平台有独立入口：

```python
def _nvidia_gather(...):
    # NVIDIA: D=32 route
    ...

def _hygon_gather(...):
    # Hygon: D=64 direct_online
    ...

def _metax_gather(...):
    # MetaX: D=64 direct_online
    ...
```

这个设计看起来笨一些，却能减少“一个平台小涨、另一个平台大跌”的情况。对于多后端比赛，这点朴素的工程隔离很有用。

## 值得保留的经验

回头看，比较值得保留的方向主要有：

| 方向 | 含义 |
|---|---|
| 避免大中间面 | 尽量不构造 `[N, C, 1024]` 这样的临时张量 |
| 流式归约 | 用 online softmax 把窗口边读边压掉 |
| 利用固定结构 | `block_size=8` 可以简化 physical block 寻址 |
| 带着账本调参 | 调 tile 前先问它在减少哪一笔开销 |
| 后端隔离 | backend route 分开，减少一个平台的经验误伤另一个平台 |
| 守住字节语义 | finalizer 以 byte-exact 为边界，尤其是 BF16、INT8、scale、RoPE |

也有一些路线需要谨慎：

| 谨慎项 | 原因 |
|---|---|
| 缺少假设的 tile roulette | 小参数变化可能只是偶然，不一定有可迁移机制 |
| 把 NVIDIA D32 扩散到 MetaX/Hygon | 不同后端的寄存器、cache、codegen 行为并不相同 |
| 在 Ascend 上激进融合 quant/RoPE | 这部分最容易触发 byte mismatch |
| 依赖 checker/cache 异常高分 | 缺少可解释的 kernel 机制，不能当成最终路线 |
| 只看本地 CUDA timing | 远程多平台结果才是比赛里的真实约束 |

## 代码快照

我也把这次复盘对应的、非异常高分路线的稳定源码快照整理成了一个小的 GitHub 仓库：

<div class="kg-challenge-card" markdown="1">
  <div>
    <p class="kg-challenge-label">稳定源码仓库</p>
    <p class="kg-challenge-desc"><code>sub_64c96b412ccc</code>，2026 年 6 月 13 日北京时间提交，7/7 通过，平均加速比约 <code>10.21x</code>。</p>
  </div>
  <a class="kg-challenge-button" href="https://github.com/TankTechnology/kernelgen-challenge-8-stable-10x" target="_blank" rel="noopener">查看 GitHub 仓库</a>
</div>

这不是后来 MetaX 上出现过的 200x 异常样本。我把它放出来，主要是作为这篇文章里几条思路的具体记录：后端隔离、利用 `block_size=8` 减少寻址、以及 Ascend 上为了正确性保留更保守的路线。

也需要很谨慎地读它。这份代码是为当时的比赛环境和官方测试面调出来的，隐含了官方 `block_size=8`、benchmark 中观察到的 block table 规律，以及平台 checker 下可接受的输出 cache 条件。一次很小的本地 review 发现，如果换成更一般的输入，比如非连续 physical block table、初始值非零的 `kv_cache`，或者非官方 `block_size`，它可能不再和 reference 保持字节级一致。所以它更适合当作比赛复盘材料，并不适合作为可以直接拿去复用的通用 KV cache 压缩库。

<div class="notice--warning" markdown="1">
<p class="notice__title">关于异常高分</p>

MetaX 曾经出现过 200x/277x 类异常信号。后来我们倾向于把它看作 checker/timing surface 的诊断信号，缺少可推广的 kernel 机制。它能提醒我们平台测量存在复杂性，但不适合作为最终实现的基础。
</div>

## 小结

如果把这次优化浓缩成几句话，大概是：

```text
先弄清楚 byte contract。
再看最大的中间张量和最热的内层循环。
能流式就流式，能少寻址就少寻址。
多平台路线要隔离，异常高分要复测。
```

从这个角度看，10x 的来源并不神秘。它更像是一串普通但重要的整理工作：把 baseline 的计算面看清楚，把 Triton program 的内存账算明白，把题目给定的 `block_size=8` 用起来，再把不同芯片的脾气分开处理。

这条路线未必漂亮，但对我们来说，它相对可靠，也比较容易继续往前推进。

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

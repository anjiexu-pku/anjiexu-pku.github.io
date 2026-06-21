---
title: "形式化证明 Huffman 最优性：我们的 splitLeaf / 交换论证方法"
date: 2026-06-21
categories:
  - formal-verification
  - algorithms
tags:
  - Lean4
  - Huffman
  - greedy
  - optimality
  - proof-methodology
excerpt: "整理我们在 Lean 4 中形式化 Huffman 编码最优性的方法：把一次贪心合并反过来写成 splitLeaf，用交换论证证明这个逆操作保持最优性，再用 splitLeaf 与 huffman 的交换律把归纳假设传回原始森林。"
---

> 本文整理 `CfProofs/Greedy/Huffman/` 中 V1 证明的结构，目标是为数学/算法博客提供一份可读的“方法地图”。底层代码约 1700 行 Lean 4，核心定理是 `optimum_huffman`。
>
> 我们的证明方法主要参考了 Jasmin Christian Blanchette 在 Isabelle/HOL 中对 Huffman 算法“课本证明”的形式化（Journal of Automated Reasoning, 2009），尤其是把一次贪心合并反过来写成 `splitLeaf` 的核心思路。

---

## 1. 问题与树模型

我们把前缀码树建模为二叉树 `HuffTree`：

```lean
inductive HuffTree
  | htLeaf (symbol freq : ℕ)
  | htInner (left right : HuffTree)
```

- 每个叶子存一个符号和正频率；
- 内部节点 `htInner l r` 代表把两棵子树合并成一个码字集合；
- `consistent t` 要求任意内部节点的左右子树字母表不交，从而保证它是合法前缀码。

一棵树的代价即编码的期望总 bit 数，也就是**加权外部路径长度**：

```lean
def cost : HuffTree → ℕ
  | htLeaf _ _ => 0
  | htInner l r => cost l + cost r + rootFreq l + rootFreq r
```

其中 `rootFreq t` 是 `t` 中所有叶子频率之和。该递归式等价于

\\[
\\operatorname{cost}(t)=\\sum_{s\\in\\operatorname{alphabet}(t)} \\operatorname{freqOf}(s,t)\\cdot \\operatorname{depthOf}(s,t).
\\]

Huffman 算法在森林上反复合并当前根频率最小的两棵树：

```lean
def insortTree (t : HuffTree) : List HuffTree → List HuffTree
  | [] => [t]
  | u :: us => if rootFreq t ≤ rootFreq u then t :: u :: us else u :: insortTree t us

def huffman : List HuffTree → HuffTree
  | [] => htLeaf 0 0
  | [t] => t
  | t₁ :: t₂ :: rest => huffman (insortTree (htInner t₁ t₂) rest)
```

`insortTree` 按 `rootFreq` 升序插入，保证森林始终有序。

---

## 2. 森林不变式

我们把所有前置条件写成对森林 `ts : List HuffTree` 的五个假设：

```lean
def forest_sorted : List HuffTree → Prop
  | [] => True | [_] => True
  | t₁ :: t₂ :: ts => rootFreq t₁ ≤ rootFreq t₂ ∧ forest_sorted (t₂ :: ts)

def forest_consistent : List HuffTree → Prop
  | [] => True | [t] => consistent t
  | t :: ts => consistent t ∧ forest_consistent ts ∧ (∀ u ∈ ts, Disjoint (alphabet t) (alphabet u))
```

再加上“每棵树都是叶子”和“所有叶子频率为正”。这五个条件构成 Huffman 最优性定理的全部假设：

```lean
theorem optimum_huffman (ts : List HuffTree)
    (h_sorted : forest_sorted ts)
    (h_cons : forest_consistent ts)
    (h_all_leaves : ∀ t ∈ ts, height t = 0)
    (h_pos : ∀ t ∈ ts, rootFreq t > 0)
    (h_nonempty : ts ≠ []) :
    optimum (huffman ts)
```

最优性 `optimum t` 要求：

```lean
def optimum (t : HuffTree) : Prop :=
  consistent t
  ∧ (∀ s ∈ alphabet t, freqOf s t > 0)
  ∧ ∀ u, consistent u → sameFreqs t u → cost t ≤ cost u
```

即 `t` 在所有与它频率分布相同且一致的前缀码树中代价最小。

---

## 3. 证明概览：把一次贪心步“倒过来”

标准 Huffman 归纳证明通常是：

1. 取两个最小频率叶子 `sa(fa), sb(fb)`；
2. 把它们合并成 `sa(fa+fb)`；
3. 对更短的森林用归纳假设；
4. 再把合并的叶子“展开”回 `sa(fa), sb(fb)`，并证明最优性保持。

我们在形式化中把第 4 步显式建模为树操作 `splitLeaf`：

```lean
def splitLeaf (t : HuffTree) (z a b fa fb : ℕ) : HuffTree :=
  match t with
  | htLeaf sym f => if sym = z then htInner (htLeaf a fa) (htLeaf b fb) else htLeaf sym f
  | htInner l r => htInner (splitLeaf l z a b fa fb) (splitLeaf r z a b fa fb)
```

`splitLeaf t z z b fa fb` 把树 `t` 中符号 `z` 的叶子替换为内部节点 `htInner (htLeaf z fa) (htLeaf b fb)`。这正是“合并”的逆操作。

<figure style="text-align:center;">
  <img src="/images/huffman-splitleaf-inverse.png" alt="splitLeaf 是 Huffman 合并步的逆操作" style="max-width: 600px; width: 100%;">
  <figcaption><b>图 1：</b>splitLeaf 把 reduced tree 中频率为 fa+fb 的合并叶子重新分裂为一对同胞叶子，从而把归纳假设传回原森林。</figcaption>
</figure>

于是整个证明可以概括为两条强归纳：

| 层次 | 归纳对象 | 作用 |
|---|---|---|
| **外层** | 森林长度 `ts.length` | 把 Huffman 算法的一次合并步规约到 `splitLeaf` |
| **内层** | 竞争对手 `u` 的节点数 `nodeCount u` | 证明 `splitLeaf` 保持最优性 |

---

## 4. 外层归纳：从森林到 reduced forest

对 `ts.length` 做强归纳。

### 4.1 基例

- **长度 1**：`ts = [htLeaf s f]`，直接用 `optimum_leaf`。

  ```lean
  lemma optimum_leaf (s f : ℕ) (h_f_pos : f > 0) : optimum (htLeaf s f) := by
    refine ⟨by simp [consistent], ?_, ?_⟩
    · simp [alphabet, freqOf, h_f_pos]
    · intro u _ h_sameFreqs
      simpa [cost] using cost_nonneg u
  ```

- **长度 2**：`ts = [htLeaf sa fa, htLeaf sb fb]`。由 `forest_consistent` 得 `sa ≠ sb`，再用 `optimum_two_distinct_leaves`。

  ```lean
  lemma optimum_two_distinct_leaves (sa fa sb fb : ℕ)
      (h_ne : sa ≠ sb) (h_fa_pos : fa > 0) (h_fb_pos : fb > 0) :
      optimum (htInner (htLeaf sa fa) (htLeaf sb fb)) := by
    -- 先验证两个符号的频率为正，再说明任何 competitor 的 cost 都不更低
    ...
  ```

### 4.2 归纳步

设 `ts = htLeaf sa fa :: htLeaf sb fb :: tc :: rest`（长度 ≥ 3）。由于 `forest_sorted`，前两个正是全局频率最小的叶子。

构造 **reduced forest**：

```lean
let reduced := insortTree (htLeaf sa (fa + fb)) (tc :: rest)
```

`Preservation.lean` 负责验证 `reduced` 仍然满足所有不变式，并且长度严格减少。关键引理包括：

- `forest_sorted_insortTree_of_sorted`：插入保持有序；
- `forest_consistent_insortTree_fresh`：因为 `sa` 原本不出现在 `tc :: rest` 中，插入 `htLeaf sa (fa+fb)` 保持不交性；
- `insortTree_length`：长度增加 1，而原长度减 2，故 `reduced.length = ts.length - 1`。

下面是这一步的 Lean 骨架（不变式的具体证明已省略）：

```lean
let reduced := insortTree (htLeaf sa (fa + fb)) (tc :: rest)

have h_reduced_nonempty : reduced ≠ [] := by
  rw [← List.length_pos_iff_ne_nil, insortTree_length]
  omega
have h_reduced_sorted : forest_sorted reduced := ...
have h_reduced_cons : forest_consistent reduced := ...
have h_reduced_leaves : ∀ t ∈ reduced, height t = 0 := ...
have h_reduced_pos : ∀ t ∈ reduced, rootFreq t > 0 := ...
have h_len : reduced.length < n := by
  rw [← hlen]
  simp [reduced, insortTree_length]

have h_opt_reduced : optimum (huffman reduced) :=
  ih reduced.length h_len reduced h_reduced_sorted h_reduced_cons
    h_reduced_leaves h_reduced_pos h_reduced_nonempty rfl
```

于是得到 `optimum (huffman reduced)`。接下来需要把 `huffman reduced` 中的合并叶子重新分裂，并让它等于原森林的 Huffman 输出。

---

## 5. 内层核心：`optimum_splitLeaf`

这是整个证明的“发动机”。定理陈述如下：

```lean
theorem optimum_splitLeaf (t : HuffTree) (z b fa fb : ℕ)
    (h_opt : optimum t)
    (h_z_in : z ∈ alphabet t)
    (hb_not_mem : b ∉ alphabet t)
    (hz_ne_b : z ≠ b)
    (h_fa_pos : fa > 0) (h_fb_pos : fb > 0) (h_fa_le_fb : fa ≤ fb)
    (h_fa_min : ∀ s ∈ alphabet t, fa ≤ freqOf s t)
    (h_fb_min : ∀ s ∈ alphabet t, s ≠ z → fb ≤ freqOf s t)
    (h_sum : freqOf z t = fa + fb) :
    optimum (splitLeaf t z z b fa fb)
```

含义：已知 `t` 最优，把 `t` 中频率为 `fa+fb` 的符号 `z` 分裂成同胞叶子 `z(fa)` 与 `b(fb)`，新树仍最优。条件正是 Huffman 一次合并所满足的。

### 5.1 成本关系

`splitLeaf` 的成本增加量恰好是 `fa + fb`：

```lean
theorem cost_splitLeaf_eq (t : HuffTree) (z a b fa fb : ℕ) (h_cons : consistent t)
    (h_z_in : z ∈ alphabet t) (h_sum : freqOf z t = fa + fb) :
    cost (splitLeaf t z a b fa fb) = cost t + fa + fb := by
  -- 先证 splitLeaf 保持 rootFreq，再对树结构做归纳
  ...
```

因此要证明分裂后的树最优，只需证明：对任意竞争对手 `u`，

\\[
\\operatorname{cost}(t)+fa+fb \\le \\operatorname{cost}(u).
\\]

### 5.2 交换论证（exchange argument）

核心工具是 `cost_exchangeLeaf_le`：

```lean
lemma cost_exchangeLeaf_le (t : HuffTree) (a x : ℕ) (h_cons : consistent t)
    (ha_in : a ∈ alphabet t) (hx_in : x ∈ alphabet t) (h_ne : a ≠ x)
    (h_freq : freqOf a t ≤ freqOf x t)
    (h_depth : (depthOf a t).getD 0 ≤ (depthOf x t).getD 0) :
    (cost (swapFreqs a x (swapLeaves a x t)) : ℤ) ≤ (cost t : ℤ)
```

组合操作 `swapFreqs a x (swapLeaves a x t)` 先交换 `a` 与 `x` 的**位置**，再交换它们的**频率标签**。这样既保留了树的形状，又把 `a` 的频率放到了原来 `x` 的深度。当 `a` 的频率更低且深度更浅时，这次“交换”不会增加成本。这个不等式是 Huffman 贪心最优性的经典解析基础。

### 5.3 deepest sibling pair

为了在竞争对手 `u` 中找到合适的位置应用交换引理，我们递归地取 `u` 中**最深的一对同胞叶子**：

```lean
def deepestSiblingPair (t : HuffTree) : ℕ × ℕ := ...
```

相关引理保证：

- `deepestSiblingPair_mem1 / mem2`：这对符号确实在字母表中；
- `deepestSiblingPair_depth`：它们的深度都等于树高；
- `deepestSiblingPair_areSiblings`：它们确实是同胞。

因为这对叶子在最深处，任何其他符号的深度都不超过它们，这满足了 `cost_exchangeLeaf_le` 的前提。

### 5.4 合并对手中的同胞：`mergePair`

一旦通过有限次交换把 `z, b` 移到同胞位置，就可以用 `mergePair` 把它们合并回单个叶子 `z(fa+fb)`，得到一棵更小的树 `v''`。

```lean
def mergePair (a b z fz : ℕ) : HuffTree → HuffTree
  | htInner (htLeaf x fx) (htLeaf y fy) =>
      if (x = a ∧ y = b) ∨ (x = b ∧ y = a) then htLeaf z fz
      else htInner (htLeaf x fx) (htLeaf y fy)
  | htInner l r => htInner (mergePair a b z fz l) (mergePair a b z fz r)
  | t => t
```

关键引理：

- `cost_mergePair_of_areSiblings`：合并后成本减少 `fa + fb`，即

  ```lean
  lemma cost_mergePair_of_areSiblings (t : HuffTree) (a b z fa fb : ℕ)
      (h_sib : areSiblings a b t) (h_cons : consistent t) (h_ne : a ≠ b)
      (h_fa : freqOf a t = fa) (h_fb : freqOf b t = fb) (h_fz : fz = fa + fb) :
      (cost (mergePair a b z fz t) : ℤ) = (cost t : ℤ) - (fa : ℤ) - (fb : ℤ) := by
    -- 对 areSiblings 归纳，直接计算同胞对合并前后的 cost
    ...
  ```

  用整数写出来就是
  \\[
  \\operatorname{cost}(v'') = \\operatorname{cost}(u) - fa - fb.
  \\]
- `nodeCount_mergePair_lt_of_areSiblings`：节点数严格减少，提供内层强归纳的测度。

于是原目标等价于
\\[
\\operatorname{cost}(t) \\le \\operatorname{cost}(v'').
\\]
而 `v''` 与 `t` 同频率分布且一致，故由 `t` 的最优性直接得到。

### 5.5 情形枚举

`optimum_splitLeaf` 的证明本质上是一场关于最深同胞对 `(x, y)` 与目标符号 `z, b` 相对关系的大规模分类讨论：

- `x = z`：
  - `y = b`：直接完成；
  - `y ≠ b`：交换 `b ↔ y`。
- `x = b`：
  - `y = z`：调整顺序得到 `z, b`；
  - `y ≠ z`：先交换 `z ↔ b`，再交换 `b ↔ y`。
- `x ∉ {z, b}`：
  - `y = z`：交换 `b ↔ x` 再交换 `z ↔ b`；
  - `y ≠ z`：交换 `z ↔ x` 得到 `z, y`，再处理 `y = b` 与否。

如果某个分支出现 `y` 不在原树 `t` 的字母表中（频率为 0），则可以直接剪枝并应用归纳假设。

---

## 6. 关键桥梁：`splitLeaf` 与 `huffman` 可交换

外层归纳得到 `optimum (huffman reduced)`，内层 `optimum_splitLeaf` 给出

```lean
optimum (splitLeaf (huffman reduced) sa sa sb fa fb)
```

最后需要把这个表达式变回 `huffman (htLeaf sa fa :: htLeaf sb fb :: tc :: rest)`。

`Commutation.lean` 证明了 `splitLeaf` 可以拉到 `huffman` 外面：

```lean
theorem splitLeaf_huffman_commute (s1 s2 f1 f2 : ℕ) (rest : List HuffTree)
    (h_s1_notin_rest : ∀ t ∈ rest, s1 ∉ alphabet t) :
    splitLeaf (huffman (insortTree (htLeaf s1 (f1+f2)) rest)) s1 s1 s2 f1 f2
    = huffman (insortTree (htInner (htLeaf s1 f1) (htLeaf s2 f2)) rest)
```

右端再把 `htInner (htLeaf s1 f1) (htLeaf s2 f2)` 插入有序森林，正好等价于原森林 `htLeaf sa fa :: htLeaf sb fb :: tc :: rest` 的 Huffman 输出。

在 `Optimal.lean` 中，最后一步这样完成：

```lean
have h_opt_split : optimum (splitLeaf (huffman reduced) sa sa sb fa fb) := by
  apply optimum_splitLeaf (huffman reduced) sa sb fa fb
    h_opt_reduced h_a_in_reduced h_b_notin_reduced h_ne
    h_fa_pos h_fb_pos h_fa_le_fb h_fa_min h_fb_min h_freq_a

have h_eq : splitLeaf (huffman reduced) sa sa sb fa fb =
    huffman (htLeaf sa fa :: htLeaf sb fb :: tc :: rest) := by
  rw [show reduced = insortTree (htLeaf sa (fa + fb)) (tc :: rest) by rfl]
  rw [splitLeaf_huffman_commute sa sb fa fb (tc :: rest) h_a_notin_tc_rest]
  simp [huffman, insortTree, unite]

rw [h_eq] at h_opt_split
exact h_opt_split
```

这正是为什么我们要把“合并两个最小叶子”表述成 `splitLeaf` 的逆操作：它让归纳假设与算法步骤之间有了一个干净的代数恒等式。

---

## 7. 文件依赖与模块化

V1 证明按功能拆成 7 个文件，形成清晰的依赖链：

<figure style="text-align:center;">
  <img src="/images/huffman-v1-deps.png" alt="V1 文件依赖图" style="max-width: 720px; width: 100%;">
  <figcaption><b>图 2：</b>V1 证明的模块依赖关系。Base 提供数据类型和树手术；Swap* 与 MergeLemmas 提供交换/合并论证；Preservation 与 Commutation 把森林不变式与 Huffman 算法衔接；Optimal 组装出最终定理。</figcaption>
</figure>

| 文件 | 主要职责 |
|---|---|
| `Base.lean` | `HuffTree`、`cost`、`huffman`、`splitLeaf`、`swapLeaves`、`mergePair` 等定义与局部引理 |
| `SwapBasic.lean` | `swapLeaves` 保持 `rootFreq` 与 `cost` |
| `SwapFreqDepth.lean` | 交换后频率/深度的精确变化 |
| `SwapDisjoint.lean` | 交换保持一致性、`cost_exchangeLeaf_le` |
| `MergeLemmas.lean` | `mergePair` 的成本、节点数、一致性、频率分布 |
| `Preservation.lean` | 森林不变式在 `insortTree` / `huffman` 下的保持 |
| `Commutation.lean` | `splitLeaf_huffman_commute` |
| `Optimal.lean` | `optimum_splitLeaf` 与 `optimum_huffman` |

---

## 8. 形式化中的典型模式

在把上述数学论证写成 Lean 4 时，有几个反复出现的模式：

1. **形状操作 + 频率操作分离**
   - `swapLeaves` 只换符号位置；
   - `replaceFreq` / `swapFreqs` 只换频率标签；
   - 组合使用实现“把低频符号放到更深位置”。

2. **整数桥接**
   许多成本等式带减法（如 `cost_mergePair`），先在 `ℤ` 中处理，再用 `exact_mod_cast` / `push_cast` 转回 `ℕ`。

3. **强归纳测度**
   外层对森林长度，内层对竞争对手节点数。

4. **分类讨论**
   `optimum_splitLeaf` 的核心是符号相等与否的分支，配合 `by_cases`、`rcases` 与 `omega`。

5. **零频率符号剪枝**
   当竞争对手中出现不在原树字母表中的符号时，其频率为 0，可以直接 `mergePair` 合并，把问题归约到更小的实例。

---

## 9. 结论

V1 证明的核心方法论可以概括为一句话：

> **把 Huffman 的一次贪心合并反过来写成 `splitLeaf`，用交换论证证明这个逆操作保持最优性，再用 `splitLeaf` 与 `huffman` 的交换律把归纳假设传回原始森林。**

这一结构使得我们可以：

- 复用经典的“最深同胞对 + 交换”论证；
- 把算法的归纳步骤与树手术的代数性质解耦；
- 在形式化中按 Base → Swap → Merge → Preservation → Commutation → Optimal 的层次组织代码。

---

## 10. 参考文献

1. **Donald E. Knuth**, *The Art of Computer Programming, Vol. 1: Fundamental Algorithms*, 3rd ed., Addison-Wesley, 1997. 见 Section 2.3.4.5 对 Huffman 编码与最优性证明的经典论述。

2. **Thomas H. Cormen, Charles E. Leiserson, Ronald L. Rivest, Clifford Stein**, *Introduction to Algorithms*, 3rd ed., MIT Press, 2009. 见 Section 16.3 “Huffman Codes” 中的交换论证与贪心选择性质。

3. **Laurent Théry**, “Formalising Huffman’s Algorithm,” *Research Report*, Università degli Studi dell’Aquila, 2004. Coq 形式化，覆盖了前缀码与满二叉树之间的同构，规模较大。
   - HAL: <https://hal.archives-ouvertes.fr/hal-02149909>

4. **Jasmin Christian Blanchette**, “Proof Pearl: Mechanizing the Textbook Proof of Huffman’s Algorithm,” *Journal of Automated Reasoning*, Vol. 43, No. 1, 2009, pp. 1–18. Isabelle/HOL 形式化，Archive of Formal Proofs 条目。
   - PDF: <https://www.tcs.ifi.lmu.de/staff/jasmin-blanchette/jar2009-huffman.pdf>
   - AFP: <https://www.isa-afp.org/entries/Huffman.html>

5. 我们的 Lean 4 实现：`CfProofs/Greedy/Huffman/` 目录，见 `Optimal.lean` 中的 `optimum_huffman` 与 `optimum_splitLeaf`。

---

## 11. 附录 A：正确性检查清单

在把证明上传之前，我检查了以下几个容易出错的点：

| 检查项 | 说明 | 对应代码 |
|---|---|---|
| `cost` 与加权外部路径长度等价 | 递归定义 `cost (htInner l r) = cost l + cost r + rootFreq l + rootFreq r` 等价于 `Σ freq·depth`；`optimum` 定义要求在所有同频率分布的一致树中代价最小。 | `Base.lean` 中 `cost`、`optimum` |
| 基例确实最优 | `optimum_leaf` 与 `optimum_two_distinct_leaves` 直接验证。 | `Optimal.lean` 开头 |
| `splitLeaf` 的成本增量正确 | `cost_splitLeaf_eq` 严格给出 `cost t + fa + fb`。 | `Base.lean` |
| 外层归纳测度严格递减 | 原森林去掉两个最小叶子，插入一个合并叶子，长度从 `n` 变为 `n-1`。 | `insortTree_length` + `omega` |
| 合并后的叶子符号在剩余森林中新鲜 | 由 `forest_consistent` 推出 `sa ∉ rest`，这是 `forest_consistent_insortTree_fresh` 的前提。 | `Optimal.lean` 归纳步 |
| `optimum_splitLeaf` 的前提与 Huffman 合并步一致 | `fa ≤ fb`、`fa, fb` 是两个最小频率、`freqOf z t = fa + fb`、`b` 新鲜。 | `Optimal.lean` 归纳步 |
| 内层归纳测度严格递减 | `mergePair` 合并同胞对时节点数严格减少（`nodeCount_mergePair_lt_of_areSiblings`）。 | `MergeLemmas.lean` |
| 交换不等式方向正确 | `cost_exchangeLeaf_le` 展开后得到 `(freq_a - freq_x)(depth_x - depth_a) ≤ 0`，与“低频放更深不增 cost”一致。 | `SwapDisjoint.lean` |
| `splitLeaf` 与 `huffman` 可交换 | `splitLeaf_huffman_commute` 把“先 Huffman 再 split”与“先 split 再 Huffman”等同。 | `Commutation.lean` |
| 整个项目通过 `lake build` | 无错误、无未完成目标（`sorry`）。 | 见附录 B |

---

## 12. 附录 B：编译报告

我在本地完整编译了包含该证明的 Lean 4 项目，结果如下：

- **工具链**：`leanprover/lean4:v4.29.1`
- **Lake 版本**：`5.0.0-src+f72c35b (Lean version 4.29.1)`
- **编译命令**：`lake build`
- **编译结果**：`Build completed successfully (16524 jobs)`
- **核心目标**：`CfProofs.Greedy.Huffman.Optimal` 构建成功
- **状态**：无错误、无未完成目标

> 说明：构建过程中只有一些 `unusedSimpArgs` / `unusedVariables` 的 linter warning，这些是代码风格提示，不影响定理正确性。

---


---
## 13. 附录 C：完整证明源码

下面把 V1 证明的全部 8 个 Lean 4 源文件直接贴在文中。每个文件可以展开查看，方便读者对照阅读。

> 提示：点击文件名即可展开/折叠对应源码。

<details>
<summary><b>Base.lean</b> — 数据类型、成本模型、树手术</summary>

{% raw %}
```lean
import Mathlib
/-!
# Huffman Coding — Optimal Prefix Code in Lean 4
Multi-agent formal verification (CLRS Ch. 16.3).
-/
open List

inductive HuffTree : Type
  | htLeaf (symbol freq : ℕ) | htInner (left right : HuffTree)
  deriving Repr, DecidableEq
open HuffTree

def rootFreq : HuffTree → ℕ
  | htLeaf _ f => f | htInner l r => rootFreq l + rootFreq r
def alphabet : HuffTree → Finset ℕ
  | htLeaf s _ => {s} | htInner l r => alphabet l ∪ alphabet r
def consistent : HuffTree → Prop
  | htLeaf _ _ => True
  | htInner l r => consistent l ∧ consistent r ∧ Disjoint (alphabet l) (alphabet r)
def height : HuffTree → ℕ
  | htLeaf _ _ => 0 | htInner l r => max (height l) (height r) + 1
def depthOf (s : ℕ) : HuffTree → Option ℕ
  | htLeaf sym _ => if sym = s then some 0 else none
  | htInner l r =>
    match depthOf s l with
    | some d => some (d + 1)
    | none => match depthOf s r with | some d => some (d + 1) | none => none
def freqOf (s : ℕ) : HuffTree → ℕ
  | htLeaf sym f => if sym = s then f else 0
  | htInner l r => freqOf s l + freqOf s r
def cost : HuffTree → ℕ
  | htLeaf _ _ => 0 | htInner l r => cost l + cost r + rootFreq l + rootFreq r
def nodeCount : HuffTree → ℕ
  | htLeaf _ _ => 1
  | htInner l r => 1 + nodeCount l + nodeCount r

lemma height_eq_zero_iff (t : HuffTree) : height t = 0 ↔ ∃ s f, t = htLeaf s f := by
  constructor
  · intro h; cases t with
    | htLeaf s f => exact ⟨s, f, rfl⟩
    | htInner l r => simp [height] at h
  · rintro ⟨s, f, rfl⟩; rfl
def sameFreqs (t u : HuffTree) : Prop := ∀ s, freqOf s t = freqOf s u
def optimum (t : HuffTree) : Prop :=
  consistent t ∧ (∀ s ∈ alphabet t, freqOf s t > 0) ∧ ∀ u, consistent u → sameFreqs t u → cost t ≤ cost u
def unite (t₁ t₂ : HuffTree) : HuffTree := htInner t₁ t₂
def insortTree (t : HuffTree) : List HuffTree → List HuffTree
  | [] => [t]
  | u :: us => if rootFreq t ≤ rootFreq u then t :: u :: us else u :: insortTree t us
def huffman : List HuffTree → HuffTree
  | [] => htLeaf 0 0 | [t] => t
  | t₁ :: t₂ :: rest => huffman (insortTree (unite t₁ t₂) rest)
termination_by forest => forest.length
decreasing_by
  simp_wf
  have hlen : (insortTree (unite t₁ t₂) rest).length = rest.length + 1 := by
    induction rest with
    | nil => simp [insortTree]
    | cons u us ih => simp [insortTree]; split <;> simp [ih, add_comm, add_left_comm]
  omega
def forest_consistent : List HuffTree → Prop
  | [] => True | [t] => consistent t
  | t :: ts => consistent t ∧ forest_consistent ts ∧ (∀ u ∈ ts, Disjoint (alphabet t) (alphabet u))
def forest_sorted : List HuffTree → Prop
  | [] => True | [_] => True
  | t₁ :: t₂ :: ts => rootFreq t₁ ≤ rootFreq t₂ ∧ forest_sorted (t₂ :: ts)
def replaceFreq (sym newFreq : ℕ) : HuffTree → HuffTree
  | htLeaf s f => if s = sym then htLeaf s newFreq else htLeaf s f
  | htInner l r => htInner (replaceFreq sym newFreq l) (replaceFreq sym newFreq r)
def swapFreqs (a c : ℕ) (t : HuffTree) : HuffTree :=
  replaceFreq c (freqOf a t) (replaceFreq a (freqOf c t) t)
def splitLeaf (t : HuffTree) (z a b fa fb : ℕ) : HuffTree :=
  match t with
  | htLeaf sym f => if sym = z then htInner (htLeaf a fa) (htLeaf b fb) else htLeaf sym f
  | htInner l r => htInner (splitLeaf l z a b fa fb) (splitLeaf r z a b fa fb)
def swapLeaves (a b : ℕ) : HuffTree → HuffTree
  | htLeaf s f => if s = a then htLeaf b f else if s = b then htLeaf a f else htLeaf s f
  | htInner l r => htInner (swapLeaves a b l) (swapLeaves a b r)
def mergePair (a b z fz : ℕ) : HuffTree → HuffTree
  | htInner (htLeaf x fx) (htLeaf y fy) =>
    if (x = a ∧ y = b) ∨ (x = b ∧ y = a) then htLeaf z fz
    else htInner (htLeaf x fx) (htLeaf y fy)
  | htInner l r => htInner (mergePair a b z fz l) (mergePair a b z fz r)
  | t => t

lemma nodeCount_swapLeaves_eq (a b : ℕ) (t : HuffTree) : nodeCount (swapLeaves a b t) = nodeCount t := by
  induction t with
  | htLeaf s f => unfold swapLeaves; simp [nodeCount]; split_ifs <;> simp [nodeCount]
  | htInner l r ihl ihr => unfold swapLeaves; simp [nodeCount, ihl, ihr]

lemma nodeCount_replaceFreq_eq (sym f : ℕ) (t : HuffTree) : nodeCount (replaceFreq sym f t) = nodeCount t := by
  induction t with
  | htLeaf s f' => unfold replaceFreq; simp [nodeCount]; split_ifs <;> simp [nodeCount]
  | htInner l r ihl ihr => unfold replaceFreq; simp [nodeCount, ihl, ihr]

-- Trivial
theorem rootFreq_nonneg (t : HuffTree) : rootFreq t ≥ 0 := by
  induction t with | htLeaf _ _ => omega | htInner _ _ ihl ihr => rw [rootFreq]; omega
theorem cost_nonneg (t : HuffTree) : cost t ≥ 0 := by
  induction t with | htLeaf _ _ => simp [cost] | htInner _ _ ihl ihr => rw [cost]; omega

-- Layer A lemmas

theorem freqOf_eq_zero_of_not_mem (s : ℕ) (t : HuffTree) (h : s ∉ alphabet t) : freqOf s t = 0 := by
  induction t with
  | htLeaf sym f =>
    have hs : sym ≠ s := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [freqOf, hs]
  | htInner l r ihl ihr =>
    have hl : s ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : s ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    simp [freqOf, ihl hl, ihr hr]


theorem depthOf_none_of_not_mem (s : ℕ) (t : HuffTree) (h : s ∉ alphabet t) : depthOf s t = none := by
  induction t with
  | htLeaf sym f =>
    have hs : sym ≠ s := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [depthOf, hs]
  | htInner l r ihl ihr =>
    have hl : s ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : s ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    simp [depthOf, ihl hl, ihr hr]

theorem depthOf_some_of_mem (s : ℕ) (t : HuffTree) (h : s ∈ alphabet t) : ∃ d, depthOf s t = some d := by
  induction t with
  | htLeaf sym f => simp [alphabet] at h; subst h; exact ⟨0, by simp [depthOf]⟩
  | htInner l r ihl ihr =>
    have h_union : s ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using h
    rcases Finset.mem_union.1 h_union with (hl | hr)
    · rcases ihl hl with ⟨d, hd⟩; refine ⟨d + 1, ?_⟩; rw [depthOf]; simp [hd]
    · by_cases hl' : s ∈ alphabet l
      · rcases ihl hl' with ⟨d, hd⟩; refine ⟨d + 1, ?_⟩; rw [depthOf]; simp [hd]
      · have h_none_l : depthOf s l = none := depthOf_none_of_not_mem s l hl'
        rcases ihr hr with ⟨d, hd⟩
        refine ⟨d + 1, ?_⟩; rw [depthOf]; simp [h_none_l, hd]

theorem alphabet_replaceFreq (sym newFreq : ℕ) (t : HuffTree) :
    alphabet (replaceFreq sym newFreq t) = alphabet t := by
  induction t with
  | htLeaf s f => unfold replaceFreq; split <;> simp [alphabet]
  | htInner l r ihl ihr => simp [replaceFreq, alphabet, ihl, ihr]

theorem consistent_replaceFreq (sym newFreq : ℕ) (t : HuffTree) (h_cons : consistent t) :
    consistent (replaceFreq sym newFreq t) := by
  induction t with
  | htLeaf s f => unfold replaceFreq; split <;> simp [consistent]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    rw [replaceFreq, consistent]
    refine ⟨ihl hcl, ihr hcr, ?_⟩
    rw [alphabet_replaceFreq sym newFreq l, alphabet_replaceFreq sym newFreq r]
    exact hd

theorem freqOf_replaceFreq_of_ne (sym newFreq other : ℕ) (t : HuffTree) (h_ne : other ≠ sym) :
    freqOf other (replaceFreq sym newFreq t) = freqOf other t := by
  induction t with
  | htLeaf s f =>
    by_cases h_eq : s = sym
    · subst h_eq; simp [replaceFreq, freqOf, Ne.symm h_ne]
    · simp [replaceFreq, freqOf, h_eq]
  | htInner l r ihl ihr => simp [replaceFreq, freqOf, ihl, ihr]

private lemma rootFreq_replaceFreq_id_of_not_mem (sym newFreq : ℕ) (t : HuffTree) (h : sym ∉ alphabet t) :
    rootFreq (replaceFreq sym newFreq t) = rootFreq t := by
  induction t with
  | htLeaf s f =>
    have hs : s ≠ sym := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [replaceFreq, rootFreq, hs]
  | htInner l r ihl ihr =>
    have hl : sym ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : sym ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    simp [replaceFreq, rootFreq, ihl hl, ihr hr]

private lemma cost_replaceFreq_id_of_not_mem (sym newFreq : ℕ) (t : HuffTree) (h : sym ∉ alphabet t) :
    cost (replaceFreq sym newFreq t) = cost t := by
  induction t with
  | htLeaf s f =>
    have hs : s ≠ sym := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [replaceFreq, cost, hs]
  | htInner l r ihl ihr =>
    have hl : sym ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : sym ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    have h_root_l : rootFreq (replaceFreq sym newFreq l) = rootFreq l :=
      rootFreq_replaceFreq_id_of_not_mem sym newFreq l hl
    have h_root_r : rootFreq (replaceFreq sym newFreq r) = rootFreq r :=
      rootFreq_replaceFreq_id_of_not_mem sym newFreq r hr
    simp [replaceFreq, cost, ihl hl, ihr hr, h_root_l, h_root_r]

theorem rootFreq_replaceFreq_eq_int (sym newFreq : ℕ) (t : HuffTree) (h_cons : consistent t)
    (h_sym_in : sym ∈ alphabet t) :
    (rootFreq (replaceFreq sym newFreq t) : ℤ) = (rootFreq t : ℤ) + ((newFreq : ℤ) - (freqOf sym t : ℤ)) := by
  induction t with
  | htLeaf s f => simp [alphabet] at h_sym_in; subst h_sym_in; simp [replaceFreq, rootFreq, freqOf]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_union : sym ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using h_sym_in
    rcases Finset.mem_union.1 h_union with (hl_in | hr_in)
    · have hr_not : sym ∉ alphabet r := by
        have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
        intro hmem
        have h_mem_inter : sym ∈ alphabet l ∩ alphabet r := Finset.mem_inter.mpr ⟨hl_in, hmem⟩
        rw [h_empty] at h_mem_inter; simp at h_mem_inter
      have h_freq_r : freqOf sym r = 0 := freqOf_eq_zero_of_not_mem sym r hr_not
      have h_root_r : rootFreq (replaceFreq sym newFreq r) = rootFreq r :=
        rootFreq_replaceFreq_id_of_not_mem sym newFreq r hr_not
      have h_ih := ihl hcl hl_in
      simp [replaceFreq, rootFreq, freqOf, h_freq_r, h_root_r, h_ih]; ring
    · have hl_not : sym ∉ alphabet l := by
        have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
        intro hmem
        have h_mem_inter : sym ∈ alphabet l ∩ alphabet r := Finset.mem_inter.mpr ⟨hmem, hr_in⟩
        rw [h_empty] at h_mem_inter; simp at h_mem_inter
      have h_freq_l : freqOf sym l = 0 := freqOf_eq_zero_of_not_mem sym l hl_not
      have h_root_l : rootFreq (replaceFreq sym newFreq l) = rootFreq l :=
        rootFreq_replaceFreq_id_of_not_mem sym newFreq l hl_not
      have h_ih := ihr hcr hr_in
      simp [replaceFreq, rootFreq, freqOf, h_freq_l, h_root_l, h_ih]; ring

theorem cost_replaceFreq_eq (sym newFreq : ℕ) (t : HuffTree) (h_cons : consistent t) :
    (cost (replaceFreq sym newFreq t) : ℤ) = (cost t : ℤ) +
    ((newFreq : ℤ) - (freqOf sym t : ℤ)) * ((depthOf sym t).getD 0 : ℤ) := by
  induction t with
  | htLeaf s f =>
    by_cases h_eq : s = sym
    · subst h_eq; simp [replaceFreq, cost, freqOf, depthOf]
    · simp [replaceFreq, cost, freqOf, depthOf, h_eq]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    by_cases h_sym_l : sym ∈ alphabet l
    · have h_sym_not_r : sym ∉ alphabet r := by
        intro hm
        have h_mem_inter : sym ∈ alphabet l ∩ alphabet r := Finset.mem_inter.mpr ⟨h_sym_l, hm⟩
        rw [h_disjoint] at h_mem_inter; simp at h_mem_inter
      have h_freq_r : freqOf sym r = 0 := freqOf_eq_zero_of_not_mem sym r h_sym_not_r
      have h_depth_r : depthOf sym r = none := depthOf_none_of_not_mem sym r h_sym_not_r
      rcases depthOf_some_of_mem sym l h_sym_l with ⟨dl, h_depth_l⟩
      have h_root_l := rootFreq_replaceFreq_eq_int sym newFreq l hcl h_sym_l
      have h_cost_r_id : cost (replaceFreq sym newFreq r) = cost r :=
        cost_replaceFreq_id_of_not_mem sym newFreq r h_sym_not_r
      have h_root_r_id : rootFreq (replaceFreq sym newFreq r) = rootFreq r :=
        rootFreq_replaceFreq_id_of_not_mem sym newFreq r h_sym_not_r
      have h_ih := ihl hcl
      simp [replaceFreq, cost, rootFreq, freqOf, depthOf,
        h_freq_r, h_depth_r, h_depth_l, h_cost_r_id, h_root_r_id, h_ih, h_root_l]; ring
    · by_cases h_sym_r : sym ∈ alphabet r
      · have h_sym_not_l : sym ∉ alphabet l := h_sym_l
        have h_freq_l : freqOf sym l = 0 := freqOf_eq_zero_of_not_mem sym l h_sym_not_l
        have h_depth_l : depthOf sym l = none := depthOf_none_of_not_mem sym l h_sym_not_l
        rcases depthOf_some_of_mem sym r h_sym_r with ⟨dr, h_depth_r⟩
        have h_root_r := rootFreq_replaceFreq_eq_int sym newFreq r hcr h_sym_r
        have h_cost_l_id : cost (replaceFreq sym newFreq l) = cost l :=
          cost_replaceFreq_id_of_not_mem sym newFreq l h_sym_not_l
        have h_root_l_id : rootFreq (replaceFreq sym newFreq l) = rootFreq l :=
          rootFreq_replaceFreq_id_of_not_mem sym newFreq l h_sym_not_l
        have h_ih := ihr hcr
        simp [replaceFreq, cost, rootFreq, freqOf, depthOf,
          h_freq_l, h_depth_l, h_depth_r, h_cost_l_id, h_root_l_id, h_ih, h_root_r]; ring
      · have h_freq_l : freqOf sym l = 0 := freqOf_eq_zero_of_not_mem sym l h_sym_l
        have h_freq_r : freqOf sym r = 0 := freqOf_eq_zero_of_not_mem sym r h_sym_r
        have h_depth_l : depthOf sym l = none := depthOf_none_of_not_mem sym l h_sym_l
        have h_depth_r : depthOf sym r = none := depthOf_none_of_not_mem sym r h_sym_r
        have h_cost_l : cost (replaceFreq sym newFreq l) = cost l :=
          cost_replaceFreq_id_of_not_mem sym newFreq l h_sym_l
        have h_cost_r : cost (replaceFreq sym newFreq r) = cost r :=
          cost_replaceFreq_id_of_not_mem sym newFreq r h_sym_r
        have h_root_l : rootFreq (replaceFreq sym newFreq l) = rootFreq l :=
          rootFreq_replaceFreq_id_of_not_mem sym newFreq l h_sym_l
        have h_root_r : rootFreq (replaceFreq sym newFreq r) = rootFreq r :=
          rootFreq_replaceFreq_id_of_not_mem sym newFreq r h_sym_r
        simp [replaceFreq, cost, rootFreq, freqOf, depthOf,
          h_freq_l, h_freq_r, h_depth_l, h_depth_r, h_cost_l, h_cost_r, h_root_l, h_root_r]

-- Layer B: Exchange lemma

private lemma depthOf_replaceFreq_of_ne (sym newFreq other : ℕ) (t : HuffTree) (h_ne : other ≠ sym) :
    depthOf other (replaceFreq sym newFreq t) = depthOf other t := by
  induction t with
  | htLeaf s f => unfold replaceFreq; split <;> simp [depthOf, h_ne]
  | htInner l r ihl ihr => simp [replaceFreq, depthOf, ihl, ihr]

theorem cost_swapFreqs_le (t : HuffTree) (a c : ℕ)
    (h_cons : consistent t)
    (h_freq : freqOf a t ≤ freqOf c t)
    (h_depth : (depthOf a t).getD 0 ≤ (depthOf c t).getD 0)
    (h_ne : a ≠ c) :
    cost (swapFreqs a c t) ≤ cost t := by
  have ha_ne_c_sym : c ≠ a := Ne.symm h_ne
  have h_cons' : consistent (replaceFreq a (freqOf c t) t) :=
    consistent_replaceFreq a (freqOf c t) t h_cons
  have h_freq_c_unchanged : freqOf c (replaceFreq a (freqOf c t) t) = freqOf c t :=
    freqOf_replaceFreq_of_ne a (freqOf c t) c t ha_ne_c_sym
  have h_depth_c_unchanged : depthOf c (replaceFreq a (freqOf c t) t) = depthOf c t :=
    depthOf_replaceFreq_of_ne a (freqOf c t) c t ha_ne_c_sym
  have h1 := cost_replaceFreq_eq a (freqOf c t) t h_cons
  have h2 := cost_replaceFreq_eq c (freqOf a t) (replaceFreq a (freqOf c t) t) h_cons'
  have h_cost_int : (cost (swapFreqs a c t) : ℤ) ≤ (cost t : ℤ) := by
    rw [swapFreqs, h2, h_freq_c_unchanged, h_depth_c_unchanged, h1]
    have h_nonneg : 0 ≤ (freqOf c t : ℤ) - (freqOf a t : ℤ) := by omega
    have h_nonpos : ((depthOf a t).getD 0 : ℤ) - ((depthOf c t).getD 0 : ℤ) ≤ 0 := by omega
    nlinarith
  exact_mod_cast h_cost_int

-- Layer B: splitLeaf infrastructure

lemma splitLeaf_eq_of_z_not_mem (t : HuffTree) (z a b fa fb : ℕ) (h : z ∉ alphabet t) :
    splitLeaf t z a b fa fb = t := by
  induction t with
  | htLeaf sym f =>
    have hs : sym ≠ z := by intro heq; subst heq; exact h (by simp [alphabet])
    simp [splitLeaf, hs]
  | htInner l r ihl ihr =>
    have hl : z ∉ alphabet l := by intro hm; apply h; simp [alphabet, hm]
    have hr : z ∉ alphabet r := by intro hm; apply h; simp [alphabet, hm]
    simp [splitLeaf, ihl hl, ihr hr]

theorem rootFreq_splitLeaf_eq (t : HuffTree) (z a b fa fb : ℕ) (h_cons : consistent t)
    (h_z_in : z ∈ alphabet t) (h_sum : freqOf z t = fa + fb) :
    rootFreq (splitLeaf t z a b fa fb) = rootFreq t := by
  induction t with
  | htLeaf sym f =>
    simp [alphabet] at h_z_in; subst h_z_in
    have hf : f = fa + fb := by simp [freqOf] at h_sum; omega
    simp [splitLeaf, rootFreq, hf]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    have h_union : z ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using h_z_in
    rcases Finset.mem_union.1 h_union with (hl_in | hr_in)
    · have hr_not : z ∉ alphabet r := by
        intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hl_in, hm⟩
        rw [h_disjoint] at hm_inter; simp at hm_inter
      have h_freq_r : freqOf z r = 0 := freqOf_eq_zero_of_not_mem z r hr_not
      have h_sum_l : freqOf z l = fa + fb := by
        simp [freqOf] at h_sum; rw [h_freq_r] at h_sum; omega
      have h_split_r : splitLeaf r z a b fa fb = r :=
        splitLeaf_eq_of_z_not_mem r z a b fa fb hr_not
      have h_ih := ihl hcl hl_in h_sum_l
      simp [splitLeaf, rootFreq, h_split_r, h_ih]
    · have hl_not : z ∉ alphabet l := by
        intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hr_in⟩
        rw [h_disjoint] at hm_inter; simp at hm_inter
      have h_freq_l : freqOf z l = 0 := freqOf_eq_zero_of_not_mem z l hl_not
      have h_sum_r : freqOf z r = fa + fb := by
        simp [freqOf] at h_sum; rw [h_freq_l] at h_sum; omega
      have h_split_l : splitLeaf l z a b fa fb = l :=
        splitLeaf_eq_of_z_not_mem l z a b fa fb hl_not
      have h_ih := ihr hcr hr_in h_sum_r
      simp [splitLeaf, rootFreq, h_split_l, h_ih]

theorem cost_splitLeaf_eq (t : HuffTree) (z a b fa fb : ℕ) (h_cons : consistent t)
    (h_z_in : z ∈ alphabet t) (h_sum : freqOf z t = fa + fb) :
    cost (splitLeaf t z a b fa fb) = cost t + fa + fb := by
  have rootFreq_splitLeaf_eq' : ∀ (t' : HuffTree), consistent t' → z ∈ alphabet t' →
      freqOf z t' = fa + fb → rootFreq (splitLeaf t' z a b fa fb) = rootFreq t' := by
    intro t' hc hzin hs
    induction t' with
    | htLeaf sym f =>
      simp [alphabet] at hzin; subst hzin
      have hf : f = fa + fb := by simp [freqOf] at hs; omega
      simp [splitLeaf, rootFreq, hf]
    | htInner l r ihl ihr =>
      rcases hc with ⟨hcl, hcr, hd⟩
      have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
      have h_union : z ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using hzin
      rcases Finset.mem_union.1 h_union with (hl_in | hr_in)
      · have hr_not : z ∉ alphabet r := by
          intro hm
          have hm_inter := Finset.mem_inter.mpr ⟨hl_in, hm⟩
          rw [h_disjoint] at hm_inter; simp at hm_inter
        have h_freq_r : freqOf z r = 0 := freqOf_eq_zero_of_not_mem z r hr_not
        have h_sum_l : freqOf z l = fa + fb := by
          simp [freqOf] at hs; rw [h_freq_r] at hs; omega
        have h_split_r : splitLeaf r z a b fa fb = r :=
          splitLeaf_eq_of_z_not_mem r z a b fa fb hr_not
        have h_ih := ihl hcl hl_in h_sum_l
        simp [splitLeaf, rootFreq, h_split_r, h_ih]
      · have hl_not : z ∉ alphabet l := by
          intro hm
          have hm_inter := Finset.mem_inter.mpr ⟨hm, hr_in⟩
          rw [h_disjoint] at hm_inter; simp at hm_inter
        have h_freq_l : freqOf z l = 0 := freqOf_eq_zero_of_not_mem z l hl_not
        have h_sum_r : freqOf z r = fa + fb := by
          simp [freqOf] at hs; rw [h_freq_l] at hs; omega
        have h_split_l : splitLeaf l z a b fa fb = l :=
          splitLeaf_eq_of_z_not_mem l z a b fa fb hl_not
        have h_ih := ihr hcr hr_in h_sum_r
        simp [splitLeaf, rootFreq, h_split_l, h_ih]
  induction t with
  | htLeaf sym f =>
    simp [alphabet] at h_z_in; subst h_z_in
    have hf : f = fa + fb := by simp [freqOf] at h_sum; omega
    simp [splitLeaf, cost, rootFreq, hf]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    have h_union : z ∈ alphabet l ∪ alphabet r := by simpa [alphabet] using h_z_in
    rcases Finset.mem_union.1 h_union with (hl_in | hr_in)
    · have hr_not : z ∉ alphabet r := by
        intro hm
        have hm_inter := Finset.mem_inter.mpr ⟨hl_in, hm⟩
        rw [h_disjoint] at hm_inter; simp at hm_inter
      have h_freq_r : freqOf z r = 0 := freqOf_eq_zero_of_not_mem z r hr_not
      have h_sum_l : freqOf z l = fa + fb := by
        simp [freqOf] at h_sum; rw [h_freq_r] at h_sum; omega
      have h_split_r : splitLeaf r z a b fa fb = r :=
        splitLeaf_eq_of_z_not_mem r z a b fa fb hr_not
      have h_ih := ihl hcl hl_in h_sum_l
      have h_root_l : rootFreq (splitLeaf l z a b fa fb) = rootFreq l :=
        rootFreq_splitLeaf_eq l z a b fa fb hcl hl_in h_sum_l
      simp [splitLeaf, cost, h_split_r, h_ih, h_root_l]; omega
    · have hl_not : z ∉ alphabet l := by
        intro hm
        have hm_inter := Finset.mem_inter.mpr ⟨hm, hr_in⟩
        rw [h_disjoint] at hm_inter; simp at hm_inter
      have h_freq_l : freqOf z l = 0 := freqOf_eq_zero_of_not_mem z l hl_not
      have h_sum_r : freqOf z r = fa + fb := by
        simp [freqOf] at h_sum; rw [h_freq_l] at h_sum; omega
      have h_split_l : splitLeaf l z a b fa fb = l :=
        splitLeaf_eq_of_z_not_mem l z a b fa fb hl_not
      have h_ih := ihr hcr hr_in h_sum_r
      have h_root_r : rootFreq (splitLeaf r z a b fa fb) = rootFreq r :=
        rootFreq_splitLeaf_eq r z a b fa fb hcr hr_in h_sum_r
      simp [splitLeaf, cost, h_split_l, h_ih, h_root_r]; omega


lemma z_not_mem_alphabet_splitLeaf (t : HuffTree) (z a b fa fb : ℕ)
    (hz_ne_a : z ≠ a) (hz_ne_b : z ≠ b) :
    z ∉ alphabet (splitLeaf t z a b fa fb) := by
  induction t with
  | htLeaf sym f =>
    by_cases hz : sym = z
    · subst hz; simp [splitLeaf, alphabet, hz_ne_a, hz_ne_b]
    · simp [splitLeaf, alphabet, hz, Ne.symm hz]
  | htInner l r ihl ihr =>
    simp [splitLeaf, alphabet, ihl, ihr]
```
{% endraw %}
</details>

<details>
<summary><b>SwapBasic.lean</b> — swapLeaves 基本性质</summary>

{% raw %}
```lean
import CfProofs.Greedy.Huffman.Base
open HuffTree

lemma rootFreq_swapLeaves_eq (a b : ℕ) (t : HuffTree) : rootFreq (swapLeaves a b t) = rootFreq t := by
  induction t with
  | htLeaf s f =>
    by_cases hsa : s = a
    · rw [hsa]; simp [swapLeaves, rootFreq]
    · by_cases hsb : s = b
      · rw [hsb]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, rootFreq]
        · simp [swapLeaves, rootFreq, hba]
      · simp [swapLeaves, rootFreq, hsa, hsb]
  | htInner l r ihl ihr => simp [swapLeaves, rootFreq, ihl, ihr]

lemma cost_swapLeaves_eq (a b : ℕ) (t : HuffTree) : cost (swapLeaves a b t) = cost t := by
  induction t with
  | htLeaf s f =>
    by_cases hsa : s = a
    · rw [hsa]; simp [swapLeaves, cost]
    · by_cases hsb : s = b
      · rw [hsb]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, cost]
        · simp [swapLeaves, cost, hba]
      · simp [swapLeaves, cost, hsa, hsb]
  | htInner l r ihl ihr =>
    have hrfl := rootFreq_swapLeaves_eq a b l
    have hrfr := rootFreq_swapLeaves_eq a b r
    simp [swapLeaves, cost, ihl, ihr, hrfl, hrfr]
```
{% endraw %}
</details>

<details>
<summary><b>SwapFreqDepth.lean</b> — 交换后的频率 / 深度</summary>

{% raw %}
```lean
import CfProofs.Greedy.Huffman.Base
open HuffTree

lemma freqOf_swapLeaves_of_not_is (a b s : ℕ) (t : HuffTree) (h_ne_a : s ≠ a) (h_ne_b : s ≠ b) :
    freqOf s (swapLeaves a b t) = freqOf s t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, freqOf, h_ne_a.symm, h_ne_b.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, freqOf, h_ne_a.symm, h_ne_b.symm]
        · simp [swapLeaves, freqOf, h_ne_a.symm, h_ne_b.symm, hba]
      · simp [swapLeaves, freqOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, freqOf, ihl, ihr]

lemma freqOf_swapLeaves_at_a (a b : ℕ) (t : HuffTree) (h_ne : a ≠ b) :
    freqOf a (swapLeaves a b t) = freqOf b t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, freqOf, h_ne, h_ne.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, freqOf, h_ne.symm]
        · simp [swapLeaves, freqOf, h_ne.symm, hba]
      · simp [swapLeaves, freqOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, freqOf, ihl, ihr]

lemma freqOf_swapLeaves_at_b (a b : ℕ) (t : HuffTree) (h_ne : a ≠ b) :
    freqOf b (swapLeaves a b t) = freqOf a t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, freqOf, h_ne, h_ne.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, freqOf, h_ne]
        · simp [swapLeaves, freqOf, hba, h_ne, h_ne.symm]
      · simp [swapLeaves, freqOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, freqOf, ihl, ihr]

lemma depthOf_swapLeaves_of_not_is (a b s : ℕ) (t : HuffTree) (h_ne_a : s ≠ a) (h_ne_b : s ≠ b) :
    depthOf s (swapLeaves a b t) = depthOf s t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, depthOf, h_ne_a.symm, h_ne_b.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, depthOf, h_ne_a.symm, h_ne_b.symm]
        · simp [swapLeaves, depthOf, h_ne_a.symm, h_ne_b.symm, hba]
      · simp [swapLeaves, depthOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, depthOf, ihl, ihr]

lemma depthOf_swapLeaves_at_a (a b : ℕ) (t : HuffTree) (h_ne : a ≠ b) :
    depthOf a (swapLeaves a b t) = depthOf b t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, depthOf, h_ne, h_ne.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, depthOf, h_ne.symm]
        · simp [swapLeaves, depthOf, h_ne.symm, hba]
      · simp [swapLeaves, depthOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, depthOf, ihl, ihr]

lemma depthOf_swapLeaves_at_b (a b : ℕ) (t : HuffTree) (h_ne : a ≠ b) :
    depthOf b (swapLeaves a b t) = depthOf a t := by
  induction t with
  | htLeaf sym f =>
    by_cases h_eq_a : sym = a
    · rw [h_eq_a]; simp [swapLeaves, depthOf, h_ne, h_ne.symm]
    · by_cases h_eq_b : sym = b
      · rw [h_eq_b]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, depthOf, h_ne]
        · simp [swapLeaves, depthOf, hba, h_ne, h_ne.symm]
      · simp [swapLeaves, depthOf, h_eq_a, h_eq_b]
  | htInner l r ihl ihr => simp [swapLeaves, depthOf, ihl, ihr]

lemma depthOf_replaceFreq_eq (sym newFreq s : ℕ) (t : HuffTree) :
    depthOf s (replaceFreq sym newFreq t) = depthOf s t := by
  induction t with
  | htLeaf sym' f =>
    by_cases h : sym' = sym
    · subst h; simp [replaceFreq, depthOf]
    · simp [replaceFreq, depthOf, h]
  | htInner l r ihl ihr => simp [replaceFreq, depthOf, ihl, ihr]

lemma depthOf_swapFreqs_eq (a c s : ℕ) (t : HuffTree) :
    depthOf s (swapFreqs a c t) = depthOf s t := by
  rw [swapFreqs, depthOf_replaceFreq_eq, depthOf_replaceFreq_eq]
```
{% endraw %}
</details>

<details>
<summary><b>SwapDisjoint.lean</b> — 交换保持一致性、cost_exchangeLeaf_le</summary>

{% raw %}
```lean
import CfProofs.Greedy.Huffman.Base
import CfProofs.Greedy.Huffman.SwapBasic
import CfProofs.Greedy.Huffman.SwapFreqDepth
open HuffTree

def swapSym (a b s : ℕ) : ℕ := if s = a then b else if s = b then a else s

lemma swapSym_involutive (a b : ℕ) : Function.Involutive (swapSym a b) := by
  intro s
  dsimp [swapSym]
  by_cases hsa : s = a
  · subst s; simp
  · by_cases hsb : s = b
    · subst s
      by_cases hba : b = a
      · subst b; simp
      · have h1 : swapSym a b b = a := by dsimp [swapSym]; simp [hba]
        have h2 : swapSym a b a = b := by dsimp [swapSym]; simp
        calc
          swapSym a b (swapSym a b b) = swapSym a b a := by rw [h1]
          _ = b := h2
    · simp [hsa, hsb]

lemma swapSym_injective (a b : ℕ) : Function.Injective (swapSym a b) :=
  (swapSym_involutive a b).injective

lemma alphabet_swapLeaves_eq_image (a b : ℕ) (t : HuffTree) :
    alphabet (swapLeaves a b t) = (alphabet t).image (swapSym a b) := by
  induction t with
  | htLeaf s f =>
    by_cases hsa : s = a
    · subst s; simp [swapLeaves, alphabet, swapSym]
    · by_cases hsb : s = b
      · subst s; simp [swapLeaves, alphabet, swapSym, hsa]
      · simp [swapLeaves, alphabet, swapSym, hsa, hsb]
  | htInner l r ihl ihr =>
    simp [swapLeaves, alphabet, ihl, ihr, Finset.image_union]

lemma swapLeaves_preserves_disjoint (a b : ℕ) (l r : HuffTree)
    (hd : Disjoint (alphabet l) (alphabet r)) :
    Disjoint (alphabet (swapLeaves a b l)) (alphabet (swapLeaves a b r)) := by
  rw [alphabet_swapLeaves_eq_image a b l, alphabet_swapLeaves_eq_image a b r]
  exact (Finset.disjoint_image (swapSym_injective a b)).mpr hd

lemma consistent_swapLeaves (a b : ℕ) (t : HuffTree) (h_cons : consistent t) :
    consistent (swapLeaves a b t) := by
  induction t with
  | htLeaf s f =>
    by_cases hsa : s = a
    · rw [hsa]; simp [swapLeaves, consistent]
    · by_cases hsb : s = b
      · rw [hsb]; by_cases hba : b = a
        · rw [hba]; simp [swapLeaves, consistent]
        · simp [swapLeaves, consistent, hba]
      · simp [swapLeaves, consistent, hsa, hsb]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    rw [swapLeaves, consistent]
    have h_l := ihl hcl; have h_r := ihr hcr
    have hd' : Disjoint (alphabet (swapLeaves a b l)) (alphabet (swapLeaves a b r)) :=
      swapLeaves_preserves_disjoint a b l r hd
    exact ⟨h_l, h_r, hd'⟩

lemma freqOf_replaceFreq_eq_of_mem (sym f : ℕ) (t : HuffTree) (h_sym : sym ∈ alphabet t) (h_cons : consistent t) :
    freqOf sym (replaceFreq sym f t) = f := by
  induction t with
  | htLeaf s g =>
    simp [alphabet] at h_sym; subst h_sym; simp [replaceFreq, freqOf]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    simp [replaceFreq, freqOf]
    simp [alphabet] at h_sym
    rcases h_sym with (hl | hr)
    · have hr_not : sym ∉ alphabet r := by
        intro hm; have hi := Finset.mem_inter.mpr ⟨hl, hm⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      have h_r : freqOf sym (replaceFreq sym f r) = 0 :=
        freqOf_eq_zero_of_not_mem sym (replaceFreq sym f r)
          (by rw [alphabet_replaceFreq sym f r]; exact hr_not)
      rw [ihl hl hcl, h_r, add_zero]
    · have hl_not : sym ∉ alphabet l := by
        intro hm; have hi := Finset.mem_inter.mpr ⟨hm, hr⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      have h_l : freqOf sym (replaceFreq sym f l) = 0 :=
        freqOf_eq_zero_of_not_mem sym (replaceFreq sym f l)
          (by rw [alphabet_replaceFreq sym f l]; exact hl_not)
      rw [ihr hr hcr, h_l, zero_add]

lemma freqOf_exchangeLeaf (t : HuffTree) (a x s : ℕ) (h_ne : a ≠ x)
    (ha_in : a ∈ alphabet t) (hx_in : x ∈ alphabet t) (h_cons : consistent t) :
    freqOf s (swapFreqs a x (swapLeaves a x t)) = freqOf s t := by
  have h_ne' : x ≠ a := Ne.symm h_ne
  let t' := swapLeaves a x t
  have h_cons_t' : consistent t' := consistent_swapLeaves a x t h_cons
  have ha_t' : freqOf a t' = freqOf x t := freqOf_swapLeaves_at_a a x t h_ne
  have hx_t' : freqOf x t' = freqOf a t := freqOf_swapLeaves_at_b a x t h_ne
  have ha_mem_t' : a ∈ alphabet t' := by
    rw [alphabet_swapLeaves_eq_image a x t, Finset.mem_image]
    exact ⟨x, hx_in, by dsimp [swapSym]; simp [h_ne']⟩
  have hx_mem_t' : x ∈ alphabet t' := by
    rw [alphabet_swapLeaves_eq_image a x t, Finset.mem_image]
    exact ⟨a, ha_in, by dsimp [swapSym]; simp⟩
  by_cases hs_a : s = a
  · rw [hs_a]
    dsimp [swapFreqs]
    rw [hx_t', ha_t']
    -- freqOf a (replaceFreq x (freqOf x t) (replaceFreq a (freqOf a t) t'))
    rw [freqOf_replaceFreq_of_ne x (freqOf x t) a (replaceFreq a (freqOf a t) t') h_ne]
    rw [freqOf_replaceFreq_eq_of_mem a (freqOf a t) t' ha_mem_t' h_cons_t']
  · by_cases hs_x : s = x
    · rw [hs_x]
      dsimp [swapFreqs]
      rw [hx_t', ha_t']
      -- freqOf x (replaceFreq x (freqOf x t) (replaceFreq a (freqOf a t) t'))
      have h_cons_t1 : consistent (replaceFreq a (freqOf a t) t') :=
        consistent_replaceFreq a (freqOf a t) t' h_cons_t'
      have hx_mem_t1 : x ∈ alphabet (replaceFreq a (freqOf a t) t') := by
        rw [alphabet_replaceFreq a (freqOf a t) t']; exact hx_mem_t'
      rw [freqOf_replaceFreq_eq_of_mem x (freqOf x t) (replaceFreq a (freqOf a t) t') hx_mem_t1 h_cons_t1]
    · -- s ≠ a and s ≠ x
      have hs_t' : freqOf s t' = freqOf s t :=
        freqOf_swapLeaves_of_not_is a x s t hs_a hs_x
      have hs_ne_a : s ≠ a := hs_a
      have hs_ne_x : s ≠ x := hs_x
      dsimp [swapFreqs]
      -- freqOf s (replaceFreq x (freqOf a t') (replaceFreq a (freqOf x t') t'))
      rw [hx_t', ha_t']
      -- freqOf s (replaceFreq x (freqOf x t) (replaceFreq a (freqOf a t) t'))
      rw [freqOf_replaceFreq_of_ne x (freqOf x t) s (replaceFreq a (freqOf a t) t') hs_ne_x]
      rw [freqOf_replaceFreq_of_ne a (freqOf a t) s t' hs_ne_a, hs_t']

lemma cost_exchangeLeaf_le (t : HuffTree) (a x : ℕ) (h_cons : consistent t)
    (ha_in : a ∈ alphabet t) (hx_in : x ∈ alphabet t) (h_ne : a ≠ x)
    (h_freq : freqOf a t ≤ freqOf x t)
    (h_depth : (depthOf a t).getD 0 ≤ (depthOf x t).getD 0) :
    (cost (swapFreqs a x (swapLeaves a x t)) : ℤ) ≤ (cost t : ℤ) := by
  have h_ne' : x ≠ a := Ne.symm h_ne
  let t1 := swapLeaves a x t
  have h_cost_t1 : cost t1 = cost t := cost_swapLeaves_eq a x t
  have h_cons_t1 : consistent t1 := consistent_swapLeaves a x t h_cons
  have h_fa_t1 : freqOf a t1 = freqOf x t := freqOf_swapLeaves_at_a a x t h_ne
  have h_fx_t1 : freqOf x t1 = freqOf a t := freqOf_swapLeaves_at_b a x t h_ne
  have h_da_val : (depthOf a t1).getD 0 = (depthOf x t).getD 0 := by
    have h := depthOf_swapLeaves_at_a a x t h_ne; simp [t1, h]
  have h_dx_val : (depthOf x t1).getD 0 = (depthOf a t).getD 0 := by
    have h := depthOf_swapLeaves_at_b a x t h_ne; simp [t1, h]
  let t2 := replaceFreq a (freqOf x t1) t1
  have h_cons_t2 : consistent t2 := consistent_replaceFreq a (freqOf x t1) t1 h_cons_t1
  have h_fx_t2 : freqOf x t2 = freqOf x t1 := by
    simp [t2, freqOf_replaceFreq_of_ne a (freqOf x t1) x t1 h_ne']
  have h_dx_t2_val : (depthOf x t2).getD 0 = (depthOf x t1).getD 0 := by
    simp [t2, depthOf_replaceFreq_eq a (freqOf x t1) x t1]
  calc
    (cost (swapFreqs a x (swapLeaves a x t)) : ℤ)
        = (cost (swapFreqs a x t1) : ℤ) := by simp [t1]
    _ = (cost (replaceFreq x (freqOf a t1) t2) : ℤ) := by simp [t2, swapFreqs]
    _ = (cost t2 : ℤ) + (((freqOf a t1 : ℤ) - (freqOf x t2 : ℤ)) * ((depthOf x t2).getD 0 : ℤ)) :=
      cost_replaceFreq_eq x (freqOf a t1) t2 h_cons_t2
    _ = (cost t2 : ℤ) + (((freqOf x t : ℤ) - (freqOf a t : ℤ)) * ((depthOf a t).getD 0 : ℤ)) := by
      simp [h_fa_t1, h_fx_t2, h_fx_t1, h_dx_t2_val, h_dx_val]
    _ = ((cost t : ℤ) + (((freqOf a t : ℤ) - (freqOf x t : ℤ)) * ((depthOf x t).getD 0 : ℤ))) +
        (((freqOf x t : ℤ) - (freqOf a t : ℤ)) * ((depthOf a t).getD 0 : ℤ)) := by
      have h_t2_eq_raw := cost_replaceFreq_eq a (freqOf x t1) t1 h_cons_t1
      have h_t2_eq : (cost t2 : ℤ) = (cost t1 : ℤ) + (((freqOf x t1 : ℤ) - (freqOf a t1 : ℤ)) * ((depthOf a t1).getD 0 : ℤ)) := by
        simpa [t2] using h_t2_eq_raw
      rw [h_t2_eq]
      simp [h_cost_t1, h_fx_t1, h_fa_t1, h_da_val]
    _ = (cost t : ℤ) + (((freqOf a t : ℤ) - (freqOf x t : ℤ)) * (((depthOf x t).getD 0 : ℤ) - ((depthOf a t).getD 0 : ℤ))) := by ring
    _ ≤ (cost t : ℤ) := by
      have h_fa_le_fx_int : (freqOf a t : ℤ) ≤ (freqOf x t : ℤ) := by exact_mod_cast h_freq
      have h_da_le_dx_int : ((depthOf a t).getD 0 : ℤ) ≤ ((depthOf x t).getD 0 : ℤ) := by exact_mod_cast h_depth
      nlinarith
```
{% endraw %}
</details>

<details>
<summary><b>MergeLemmas.lean</b> — mergePair 的代数</summary>

{% raw %}
```lean
import CfProofs.Greedy.Huffman.Base
open HuffTree

inductive areSiblings (a b : ℕ) : HuffTree → Prop
  | here (fa fb : ℕ) : areSiblings a b (htInner (htLeaf a fa) (htLeaf b fb))
  | here' (fa fb : ℕ) : areSiblings a b (htInner (htLeaf b fb) (htLeaf a fa))
  | inLeft (l r : HuffTree) : areSiblings a b l → areSiblings a b (htInner l r)
  | inRight (l r : HuffTree) : areSiblings a b r → areSiblings a b (htInner l r)

lemma mergePair_eq_self_of_not_mem (a b z fz : ℕ) (t : HuffTree)
    (ha : a ∉ alphabet t) (hb : b ∉ alphabet t) : mergePair a b z fz t = t := by
  induction t with
  | htLeaf s f => simp [mergePair]
  | htInner l r ihl ihr =>
    have ha_l : a ∉ alphabet l := by intro hm; apply ha; simp [alphabet, hm]
    have hb_l : b ∉ alphabet l := by intro hm; apply hb; simp [alphabet, hm]
    have ha_r : a ∉ alphabet r := by intro hm; apply ha; simp [alphabet, hm]
    have hb_r : b ∉ alphabet r := by intro hm; apply hb; simp [alphabet, hm]
    have hl := ihl ha_l hb_l
    have hr := ihr ha_r hb_r
    cases l with
    | htLeaf sl fl =>
      cases r with
      | htLeaf sr fr =>
        have h_not_pair : ¬ ((sl = a ∧ sr = b) ∨ (sl = b ∧ sr = a)) := by
          intro h; rcases h with (⟨hsl, hsr⟩ | ⟨hsl, hsr⟩)
          · subst hsl hsr; exact ha (by simp [alphabet])
          · subst hsl hsr; exact ha (by simp [alphabet])
        simp [mergePair, h_not_pair, hl, hr]
      | htInner _ _ => simp [mergePair, hl, hr]
    | htInner _ _ => simp [mergePair, hl, hr]

lemma nodeCount_mergePair_le (a b z fz : ℕ) (t : HuffTree) :
    nodeCount (mergePair a b z fz t) ≤ nodeCount t := by
  induction t with
  | htLeaf s f => simp [mergePair, nodeCount]
  | htInner l r ihl ihr =>
    cases l with
    | htLeaf x fx =>
      cases r with
      | htLeaf y fy =>
        simp [mergePair, nodeCount]
        by_cases hc : (x = a ∧ y = b) ∨ (x = b ∧ y = a)
        · simp [hc, nodeCount]
        · simp [hc, nodeCount]
      | htInner rl rr =>
        have hm : mergePair a b z fz (htInner (htLeaf x fx) (htInner rl rr)) =
          htInner (htLeaf x fx) (mergePair a b z fz (htInner rl rr)) := by simp [mergePair]
        rw [hm]; simp [nodeCount] at ihr ⊢
        omega
    | htInner ll lr =>
      cases r with
      | htLeaf y fy =>
        have hm : mergePair a b z fz (htInner (htInner ll lr) (htLeaf y fy)) =
          htInner (mergePair a b z fz (htInner ll lr)) (htLeaf y fy) := by simp [mergePair]
        rw [hm]; simp [nodeCount] at ihl ⊢
        omega
      | htInner rl rr =>
        have hm : mergePair a b z fz (htInner (htInner ll lr) (htInner rl rr)) =
          htInner (mergePair a b z fz (htInner ll lr)) (mergePair a b z fz (htInner rl rr)) := by simp [mergePair]
        rw [hm]; simp [nodeCount] at ihl ihr ⊢
        omega

lemma areSiblings_mem_alphabet {a b : ℕ} {t : HuffTree} (h_sib : areSiblings a b t) :
    a ∈ alphabet t ∧ b ∈ alphabet t := by
  induction h_sib with
  | here fa fb => simp [alphabet]
  | here' fa fb => simp [alphabet]
  | inLeft l r h ih =>
    rcases ih with ⟨ha, hb⟩
    exact ⟨Finset.mem_union_left _ ha, Finset.mem_union_left _ hb⟩
  | inRight l r h ih =>
    rcases ih with ⟨ha, hb⟩
    exact ⟨Finset.mem_union_right _ ha, Finset.mem_union_right _ hb⟩

lemma nodeCount_mergePair_lt_of_areSiblings (t : HuffTree) (a b z fz : ℕ)
    (h_sib : areSiblings a b t) (h_ne : a ≠ b) :
    nodeCount (mergePair a b z fz t) < nodeCount t := by
  induction h_sib with
  | here fa fb =>
    simp [mergePair, nodeCount]
  | here' fa fb =>
    simp [mergePair, nodeCount]
  | inLeft l r h_sib_l ih =>
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      have h_l : nodeCount (mergePair a b z fz (htInner ll lr)) < nodeCount (htInner ll lr) := ih
      have h_r : nodeCount (mergePair a b z fz r) ≤ nodeCount r := nodeCount_mergePair_le a b z fz r
      simp [nodeCount] at h_l h_r ⊢
      have hm : mergePair a b z fz (htInner (htInner ll lr) r) =
        htInner (mergePair a b z fz (htInner ll lr)) (mergePair a b z fz r) := by simp [mergePair]
      rw [hm]; simp [nodeCount]
      omega
  | inRight l r h_sib_r ih =>
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      have h_l : nodeCount (mergePair a b z fz l) ≤ nodeCount l := nodeCount_mergePair_le a b z fz l
      have h_r : nodeCount (mergePair a b z fz (htInner rl rr)) < nodeCount (htInner rl rr) := ih
      simp [nodeCount] at h_l h_r ⊢
      have hm : mergePair a b z fz (htInner l (htInner rl rr)) =
        htInner (mergePair a b z fz l) (mergePair a b z fz (htInner rl rr)) := by simp [mergePair]
      rw [hm]; simp [nodeCount]
      omega

lemma rootFreq_mergePair_of_areSiblings (t : HuffTree) (a b z fz : ℕ)
    (h_sib : areSiblings a b t) (h_cons : consistent t) (h_ne : a ≠ b) (h_fz : fz = freqOf a t + freqOf b t) :
    rootFreq (mergePair a b z fz t) = rootFreq t := by
  induction h_sib with
  | here fa fb =>
    simp [mergePair, rootFreq, freqOf, h_ne, h_ne.symm, h_fz]
  | here' fa fb =>
    simp [mergePair, rootFreq, freqOf, h_ne, h_ne.symm, h_fz]; omega
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨ha_l, hb_l⟩
    have ha_r : a ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨ha_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    -- From disjointness: freqOf a r = 0 and freqOf b r = 0, so h_fz applies to l
    have h_fz_l : fz = freqOf a l + freqOf b l := by
      rw [freqOf, freqOf, freqOf_eq_zero_of_not_mem a r ha_r, freqOf_eq_zero_of_not_mem b r hb_r] at h_fz
      simpa [add_comm, add_left_comm, add_assoc] using h_fz
    have h_merge_r : mergePair a b z fz r = r := mergePair_eq_self_of_not_mem a b z fz r ha_r hb_r
    have h_root_l : rootFreq (mergePair a b z fz l) = rootFreq l := ih hcl h_fz_l
    -- Expand mergePair on htInner l r. Since areSiblings a b l, l cannot be htLeaf.
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      simp [mergePair, rootFreq, h_merge_r, h_root_l]
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨ha_r, hb_r⟩
    have ha_l : a ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, ha_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_fz_r : fz = freqOf a r + freqOf b r := by
      rw [freqOf, freqOf, freqOf_eq_zero_of_not_mem a l ha_l, freqOf_eq_zero_of_not_mem b l hb_l] at h_fz
      simpa [add_comm, add_left_comm, add_assoc] using h_fz
    have h_merge_l : mergePair a b z fz l = l := mergePair_eq_self_of_not_mem a b z fz l ha_l hb_l
    have h_root_r : rootFreq (mergePair a b z fz r) = rootFreq r := ih hcr h_fz_r
    -- Expand mergePair. Since areSiblings a b r, r cannot be htLeaf.
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      simp [mergePair, rootFreq, h_merge_l, h_root_r]

lemma cost_mergePair_of_areSiblings (t : HuffTree) (a b z fa fb : ℕ)
    (h_sib : areSiblings a b t) (h_cons : consistent t) (h_ne : a ≠ b)
    (h_fa : freqOf a t = fa) (h_fb : freqOf b t = fb) (h_fz : fz = fa + fb) :
    (cost (mergePair a b z fz t) : ℤ) = (cost t : ℤ) - (fa : ℤ) - (fb : ℤ) := by
  revert h_cons h_fa h_fb h_fz
  induction h_sib with
  | here fa' fb' =>
    intro h_cons h_fa h_fb h_fz
    have h_fa_val : freqOf a (htInner (htLeaf a fa') (htLeaf b fb')) = fa' := by
      simp [freqOf, h_ne, h_ne.symm]
    have h_fb_val : freqOf b (htInner (htLeaf a fa') (htLeaf b fb')) = fb' := by
      simp [freqOf, h_ne, h_ne.symm]
    rw [h_fa_val] at h_fa; rw [h_fb_val] at h_fb; subst h_fa; subst h_fb
    have h_cost_merged : cost (mergePair a b z fz (htInner (htLeaf a fa') (htLeaf b fb'))) = 0 := by
      simp [mergePair, cost]
    have h_cost_t : cost (htInner (htLeaf a fa') (htLeaf b fb')) = fa' + fb' := by
      simp [cost, rootFreq]
    rw [h_cost_merged, h_cost_t]; push_cast; omega
  | here' fa' fb' =>
    intro h_cons h_fa h_fb h_fz
    have h_fa_val : freqOf a (htInner (htLeaf b fb') (htLeaf a fa')) = fa' := by
      simp [freqOf, h_ne, h_ne.symm]
    have h_fb_val : freqOf b (htInner (htLeaf b fb') (htLeaf a fa')) = fb' := by
      simp [freqOf, h_ne, h_ne.symm]
    rw [h_fa_val] at h_fa; rw [h_fb_val] at h_fb; subst h_fa; subst h_fb
    have h_cost_merged : cost (mergePair a b z fz (htInner (htLeaf b fb') (htLeaf a fa'))) = 0 := by
      simp [mergePair, cost]
    have h_cost_t : cost (htInner (htLeaf b fb') (htLeaf a fa')) = fa' + fb' := by
      simp [cost, rootFreq]; omega
    rw [h_cost_merged, h_cost_t]; push_cast; omega
  | inLeft l r h_sib_l ih =>
    intro h_cons h_fa h_fb h_fz
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨ha_l, hb_l⟩
    have ha_r : a ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨ha_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_freq_l_a : freqOf a l = fa := by
      rw [← h_fa, freqOf, freqOf_eq_zero_of_not_mem a r ha_r]; simp
    have h_freq_l_b : freqOf b l = fb := by
      rw [← h_fb, freqOf, freqOf_eq_zero_of_not_mem b r hb_r]; simp
    have h_root_l : rootFreq (mergePair a b z fz l) = rootFreq l :=
      rootFreq_mergePair_of_areSiblings l a b z fz h_sib_l hcl h_ne (by rw [h_freq_l_a, h_freq_l_b]; exact h_fz)
    have h_cost_l : (cost (mergePair a b z fz l) : ℤ) = (cost l : ℤ) - (fa : ℤ) - (fb : ℤ) :=
      ih hcl h_freq_l_a h_freq_l_b h_fz
    have h_cost_r : cost (mergePair a b z fz r) = cost r := by
      simp [mergePair_eq_self_of_not_mem a b z fz r ha_r hb_r]
    have h_root_r : rootFreq (mergePair a b z fz r) = rootFreq r := by
      simp [mergePair_eq_self_of_not_mem a b z fz r ha_r hb_r]
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      simp [mergePair, cost, h_cost_l, h_cost_r, h_root_l, h_root_r]; ring
  | inRight l r h_sib_r ih =>
    intro h_cons h_fa h_fb h_fz
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨ha_r, hb_r⟩
    have ha_l : a ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, ha_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_freq_r_a : freqOf a r = fa := by
      rw [← h_fa, freqOf, freqOf_eq_zero_of_not_mem a l ha_l]; simp
    have h_freq_r_b : freqOf b r = fb := by
      rw [← h_fb, freqOf, freqOf_eq_zero_of_not_mem b l hb_l]; simp
    have h_root_r : rootFreq (mergePair a b z fz r) = rootFreq r :=
      rootFreq_mergePair_of_areSiblings r a b z fz h_sib_r hcr h_ne (by rw [h_freq_r_a, h_freq_r_b]; exact h_fz)
    have h_cost_r : (cost (mergePair a b z fz r) : ℤ) = (cost r : ℤ) - (fa : ℤ) - (fb : ℤ) :=
      ih hcr h_freq_r_a h_freq_r_b h_fz
    have h_cost_l : cost (mergePair a b z fz l) = cost l := by
      simp [mergePair_eq_self_of_not_mem a b z fz l ha_l hb_l]
    have h_root_l : rootFreq (mergePair a b z fz l) = rootFreq l := by
      simp [mergePair_eq_self_of_not_mem a b z fz l ha_l hb_l]
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      simp [mergePair, cost, h_cost_l, h_cost_r, h_root_l, h_root_r]; ring

lemma alphabet_mergePair_subset (a b z fz : ℕ) (t : HuffTree) :
    alphabet (mergePair a b z fz t) ⊆ alphabet t ∪ {z} := by
  induction t with
  | htLeaf s f => simp [mergePair]
  | htInner l r ihl ihr =>
    intro x hx
    cases l with
    | htLeaf sl fl =>
      cases r with
      | htLeaf sr fr =>
        by_cases hpair : (sl = a ∧ sr = b) ∨ (sl = b ∧ sr = a)
        · -- mergePair returns htLeaf z fz
          have h_merge_val : mergePair a b z fz (htInner (htLeaf sl fl) (htLeaf sr fr)) = htLeaf z fz := by
            simp [mergePair, hpair]
          have hx' : x ∈ alphabet (htLeaf z fz) := by rwa [h_merge_val] at hx
          rcases Finset.mem_singleton.mp hx' with rfl
          simp
        · -- mergePair returns htInner (htLeaf sl fl) (htLeaf sr fr)
          have h_merge_val : mergePair a b z fz (htInner (htLeaf sl fl) (htLeaf sr fr)) =
                             htInner (htLeaf sl fl) (htLeaf sr fr) := by
            simp [mergePair, hpair]
          have hx' : x ∈ alphabet (htInner (htLeaf sl fl) (htLeaf sr fr)) := by rwa [h_merge_val] at hx
          -- hx' : x ∈ {sl} ∪ {sr}, goal: x ∈ ({sl} ∪ {sr}) ∪ {z}
          exact Finset.mem_union_left _ hx'
      | htInner rl rr =>
        simp only [mergePair, alphabet] at hx ⊢
        rcases Finset.mem_union.mp hx with (hx_l | hx_r)
        · apply Finset.mem_union_left; apply Finset.mem_union_left; exact hx_l
        · have h := ihr hx_r
          rcases Finset.mem_union.mp h with (h' | h')
          · apply Finset.mem_union_left; apply Finset.mem_union_right; exact h'
          · apply Finset.mem_union_right; exact h'
    | htInner ll lr =>
      cases r with
      | htLeaf sr fr =>
        simp only [mergePair, alphabet] at hx ⊢
        rcases Finset.mem_union.mp hx with (hx_l | hx_r)
        · have h := ihl hx_l
          rcases Finset.mem_union.mp h with (h' | h')
          · apply Finset.mem_union_left; apply Finset.mem_union_left; exact h'
          · apply Finset.mem_union_right; exact h'
        · apply Finset.mem_union_left; apply Finset.mem_union_right; exact hx_r
      | htInner rl rr =>
        simp only [mergePair, alphabet] at hx ⊢
        rcases Finset.mem_union.mp hx with (hx_l | hx_r)
        · have h := ihl hx_l
          rcases Finset.mem_union.mp h with (h' | h')
          · apply Finset.mem_union_left; apply Finset.mem_union_left; exact h'
          · apply Finset.mem_union_right; exact h'
        · have h := ihr hx_r
          rcases Finset.mem_union.mp h with (h' | h')
          · apply Finset.mem_union_left; apply Finset.mem_union_right; exact h'
          · apply Finset.mem_union_right; exact h'

lemma consistent_mergePair_of_areSiblings (t : HuffTree) (a b z fz : ℕ)
    (h_sib : areSiblings a b t) (h_cons : consistent t) (hz_fresh : z ∉ alphabet t) :
    consistent (mergePair a b z fz t) := by
  induction h_sib with
  | here fa fb => simp [mergePair, consistent]
  | here' fa fb => simp [mergePair, consistent]
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have hz_l : z ∉ alphabet l := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have hz_r : z ∉ alphabet r := by intro hz; apply hz_fresh; simp [alphabet, hz]
    rcases areSiblings_mem_alphabet h_sib_l with ⟨ha_l, hb_l⟩
    have ha_r : a ∉ alphabet r := by
      intro hm; have h_inter := Finset.mem_inter.mpr ⟨ha_l, hm⟩
      rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at h_inter; simp at h_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have h_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at h_inter; simp at h_inter
    have h_merge_r : mergePair a b z fz r = r :=
      mergePair_eq_self_of_not_mem a b z fz r ha_r hb_r
    have h_l := ih hcl hz_l
    have h_disjoint_merge : Disjoint (alphabet (mergePair a b z fz l)) (alphabet r) := by
      have h_sub : alphabet (mergePair a b z fz l) ⊆ alphabet l ∪ {z} :=
        alphabet_mergePair_subset a b z fz l
      have h_disj_sup : Disjoint (alphabet l ∪ {z}) (alphabet r) := by
        rw [Finset.disjoint_union_left]
        exact ⟨hd, by rw [Finset.disjoint_singleton_left]; exact hz_r⟩
      exact Finset.disjoint_of_subset_left h_sub h_disj_sup
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      simp [mergePair, h_merge_r, consistent]
      exact ⟨h_l, hcr, h_disjoint_merge⟩
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have hz_l : z ∉ alphabet l := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have hz_r : z ∉ alphabet r := by intro hz; apply hz_fresh; simp [alphabet, hz]
    rcases areSiblings_mem_alphabet h_sib_r with ⟨ha_r, hb_r⟩
    have ha_l : a ∉ alphabet l := by
      intro hm; have h_inter := Finset.mem_inter.mpr ⟨hm, ha_r⟩
      rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at h_inter; simp at h_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have h_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at h_inter; simp at h_inter
    have h_merge_l : mergePair a b z fz l = l :=
      mergePair_eq_self_of_not_mem a b z fz l ha_l hb_l
    have h_r := ih hcr hz_r
    have h_disjoint_merge : Disjoint (alphabet l) (alphabet (mergePair a b z fz r)) := by
      have h_sub : alphabet (mergePair a b z fz r) ⊆ alphabet r ∪ {z} :=
        alphabet_mergePair_subset a b z fz r
      have h_disj_sup : Disjoint (alphabet l) (alphabet r ∪ {z}) := by
        rw [Finset.disjoint_union_right]
        exact ⟨hd, by rw [Finset.disjoint_singleton_right]; exact hz_l⟩
      exact Finset.disjoint_of_subset_right h_sub h_disj_sup
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      simp [mergePair, h_merge_l, consistent]
      exact ⟨hcl, h_r, h_disjoint_merge⟩

lemma freqOf_mergePair_of_areSiblings (t : HuffTree) (a b z : ℕ)
    (h_sib : areSiblings a b t) (h_cons : consistent t) (hz_fresh : z ∉ alphabet t) (s : ℕ) :
    freqOf s (mergePair a b z (freqOf a t + freqOf b t) t) =
    if s = z then freqOf a t + freqOf b t
    else if s = a ∨ s = b then 0
    else freqOf s t := by
  cases h_sib with
  | here fa fb =>
    rcases h_cons with ⟨_, _, hd⟩
    have h_ne : a ≠ b := by
      intro heq; subst heq
      have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
      simp [alphabet] at h_empty
    have hz_ne_a : z ≠ a := by intro heq; subst heq; apply hz_fresh; simp [alphabet]
    have hz_ne_b : z ≠ b := by intro heq; subst heq; apply hz_fresh; simp [alphabet]
    have h_freq_sum : freqOf a (htInner (htLeaf a fa) (htLeaf b fb)) +
                     freqOf b (htInner (htLeaf a fa) (htLeaf b fb)) = fa + fb := by
      simp [freqOf, h_ne, h_ne.symm]
    have h_merge_val : mergePair a b z (freqOf a (htInner (htLeaf a fa) (htLeaf b fb)) +
                                        freqOf b (htInner (htLeaf a fa) (htLeaf b fb)))
                                        (htInner (htLeaf a fa) (htLeaf b fb)) =
                       htLeaf z (fa + fb) := by
      rw [h_freq_sum]; simp [mergePair]
    rw [h_merge_val, freqOf, h_freq_sum]
    by_cases hsz : s = z
    · subst s; simp
    · rw [if_neg (Ne.symm hsz), if_neg hsz]
      by_cases hsa : s = a
      · subst s; simp
      · by_cases hsb : s = b
        · subst s; simp
        · have h_freq_s : freqOf s (htInner (htLeaf a fa) (htLeaf b fb)) = 0 := by
            simp [freqOf, hsa, hsb, Ne.symm hsa, Ne.symm hsb]
          simp [hsa, hsb, h_freq_s]
  | here' fb_a fa_a =>
    rcases h_cons with ⟨_, _, hd⟩
    have h_ne : a ≠ b := by
      intro heq; subst heq
      have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
      simp [alphabet] at h_empty
    have hz_ne_a : z ≠ a := by intro heq; subst heq; apply hz_fresh; simp [alphabet]
    have hz_ne_b : z ≠ b := by intro heq; subst heq; apply hz_fresh; simp [alphabet]
    have h_freq_sum : freqOf a (htInner (htLeaf b fa_a) (htLeaf a fb_a)) +
                     freqOf b (htInner (htLeaf b fa_a) (htLeaf a fb_a)) = fa_a + fb_a := by
      simp [freqOf, h_ne, h_ne.symm]; omega
    have h_merge_val : mergePair a b z (freqOf a (htInner (htLeaf b fa_a) (htLeaf a fb_a)) +
                                        freqOf b (htInner (htLeaf b fa_a) (htLeaf a fb_a)))
                                        (htInner (htLeaf b fa_a) (htLeaf a fb_a)) =
                       htLeaf z (fa_a + fb_a) := by
      rw [h_freq_sum]; simp [mergePair]
    rw [h_merge_val, freqOf, h_freq_sum]
    by_cases hsz : s = z
    · subst s; simp
    · rw [if_neg (Ne.symm hsz), if_neg hsz]
      by_cases hsa : s = a
      · subst s; simp
      · by_cases hsb : s = b
        · subst s; simp
        · have h_freq_s : freqOf s (htInner (htLeaf b fa_a) (htLeaf a fb_a)) = 0 := by
            simp [freqOf, hsa, hsb, Ne.symm hsa, Ne.symm hsb]
          simp [hsa, hsb, h_freq_s]
  | inLeft l r h_sib_l =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨ha_l, hb_l⟩
    have ha_r : a ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨ha_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hz_l : z ∉ alphabet l := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have hz_r : z ∉ alphabet r := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have h_freq_ar : freqOf a r = 0 := freqOf_eq_zero_of_not_mem _ _ ha_r
    have h_freq_br : freqOf b r = 0 := freqOf_eq_zero_of_not_mem _ _ hb_r
    have h_freq_zr : freqOf z r = 0 := freqOf_eq_zero_of_not_mem _ _ hz_r
    cases l with
    | htLeaf _ _ => exfalso; cases h_sib_l
    | htInner ll lr =>
      -- t = htInner (htInner ll lr) r; compute freq sum
      let l' := htInner ll lr
      have h_fz_l : freqOf a (htInner (htInner ll lr) r) + freqOf b (htInner (htInner ll lr) r) =
                   freqOf a (htInner ll lr) + freqOf b (htInner ll lr) := by
        simp [freqOf, h_freq_ar, h_freq_br]
      rw [h_fz_l]
      have h_merge_r' : mergePair a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr)) r = r :=
        mergePair_eq_self_of_not_mem a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr)) r ha_r hb_r
      have h_freq_l := freqOf_mergePair_of_areSiblings (htInner ll lr) a b z h_sib_l hcl hz_l s
      have h_mp : mergePair a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr))
                                 (htInner (htInner ll lr) r) =
                 htInner (mergePair a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr)) (htInner ll lr))
                        (mergePair a b z (freqOf a (htInner ll lr) + freqOf b (htInner ll lr)) r) := by
        delta mergePair; simp
      rw [h_mp, h_merge_r']
      -- Goal: freqOf s (htInner (mergePair ... (htInner ll lr)) r) = ...
      -- Expand only the top-level freqOf
      conv => lhs; rw [freqOf]
      -- Now freqOf s (mergePair ... (htInner ll lr)) + freqOf s r = ...
      rw [h_freq_l]
      by_cases hsz : s = z
      · subst s; simp [h_freq_zr]
      · by_cases hsa : s = a
        · subst s; simp [h_freq_ar]
        · by_cases hsb : s = b
          · subst s; simp [h_freq_br]
          · simp [hsz, hsa, hsb, freqOf]
  | inRight l r h_sib_r =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨ha_r, hb_r⟩
    have ha_l : a ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, ha_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hz_l : z ∉ alphabet l := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have hz_r : z ∉ alphabet r := by intro hz; apply hz_fresh; simp [alphabet, hz]
    have h_freq_al : freqOf a l = 0 := freqOf_eq_zero_of_not_mem _ _ ha_l
    have h_freq_bl : freqOf b l = 0 := freqOf_eq_zero_of_not_mem _ _ hb_l
    have h_freq_zl : freqOf z l = 0 := freqOf_eq_zero_of_not_mem _ _ hz_l
    cases r with
    | htLeaf _ _ => exfalso; cases h_sib_r
    | htInner rl rr =>
      -- t = htInner l (htInner rl rr); compute freq sum
      have h_fz_r : freqOf a (htInner l (htInner rl rr)) + freqOf b (htInner l (htInner rl rr)) =
                   freqOf a (htInner rl rr) + freqOf b (htInner rl rr) := by
        simp [freqOf, h_freq_al, h_freq_bl]
      rw [h_fz_r]
      have h_merge_l' : mergePair a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr)) l = l :=
        mergePair_eq_self_of_not_mem a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr)) l ha_l hb_l
      have h_freq_r := freqOf_mergePair_of_areSiblings (htInner rl rr) a b z h_sib_r hcr hz_r s
      have h_mp : mergePair a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr))
                                 (htInner l (htInner rl rr)) =
                 htInner (mergePair a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr)) l)
                        (mergePair a b z (freqOf a (htInner rl rr) + freqOf b (htInner rl rr)) (htInner rl rr)) := by
        delta mergePair; simp
      rw [h_mp, h_merge_l']
      conv => lhs; rw [freqOf]
      rw [h_freq_r]
      by_cases hsz : s = z
      · subst s; simp [h_freq_zl]
      · by_cases hsa : s = a
        · subst s; simp [h_freq_al]
        · by_cases hsb : s = b
          · subst s; simp [h_freq_bl]
          · simp [hsz, hsa, hsb, freqOf]
```
{% endraw %}
</details>

<details>
<summary><b>Preservation.lean</b> — 森林不变式与 Huffman 语义</summary>

{% raw %}
```lean
import CfProofs.Greedy.Huffman.Base
import CfProofs.Greedy.Huffman.Commutation

open HuffTree

/-! # Huffman preserves forest frequencies and alphabet

For a non-empty forest `ts`, the tree `huffman ts` encodes exactly the same
symbols with the same frequencies as the whole forest, and it is consistent
whenever the forest is consistent.
-/

def forest_freq (ts : List HuffTree) (s : ℕ) : ℕ := (ts.map (freqOf s)).sum

def forest_alphabet : List HuffTree → Finset ℕ
  | [] => ∅
  | t :: ts => alphabet t ∪ forest_alphabet ts

lemma mem_forest_alphabet (ts : List HuffTree) (s : ℕ) :
    s ∈ forest_alphabet ts ↔ ∃ t ∈ ts, s ∈ alphabet t := by
  induction ts with
  | nil => simp [forest_alphabet]
  | cons t ts ih =>
    simp [forest_alphabet, ih]

lemma forest_freq_cons (t : HuffTree) (ts : List HuffTree) (s : ℕ) :
    forest_freq (t :: ts) s = freqOf s t + forest_freq ts s := by
  simp [forest_freq]

lemma forest_alphabet_cons (t : HuffTree) (ts : List HuffTree) :
    forest_alphabet (t :: ts) = alphabet t ∪ forest_alphabet ts := by
  simp [forest_alphabet]

lemma forest_freq_insortTree (t : HuffTree) (ts : List HuffTree) (s : ℕ) :
    forest_freq (insortTree t ts) s = forest_freq (t :: ts) s := by
  induction ts generalizing t with
  | nil => simp [insortTree, forest_freq]
  | cons u us ih =>
    simp [insortTree]
    by_cases h : rootFreq t ≤ rootFreq u
    · simp [h, forest_freq]
    · simp [h, forest_freq]
      have h_ih := ih t
      simp [forest_freq] at h_ih ⊢
      omega

lemma forest_alphabet_insortTree (t : HuffTree) (ts : List HuffTree) :
    forest_alphabet (insortTree t ts) = forest_alphabet (t :: ts) := by
  induction ts generalizing t with
  | nil => simp [insortTree, forest_alphabet]
  | cons u us ih =>
    simp [insortTree, forest_alphabet]
    by_cases h : rootFreq t ≤ rootFreq u
    · simp [h, forest_alphabet]
    · simp [h, ih, forest_alphabet]
      ac_rfl

lemma freqOf_huffman_eq_forest_freq (ts : List HuffTree) (s : ℕ) (h_nonempty : ts ≠ []) :
    freqOf s (huffman ts) = forest_freq ts s := by
  induction ts using huffman.induct with
  | case1 => exfalso; exact h_nonempty rfl
  | case2 t => simp [huffman, forest_freq]
  | case3 t1 t2 rest IH =>
    have h_rec : insortTree (unite t1 t2) rest ≠ [] := by
      rw [← List.length_pos_iff_ne_nil, insortTree_length]
      omega
    simp [huffman, forest_freq_insortTree, IH h_rec]
    simp [forest_freq]
    have h_unite : freqOf s (unite t1 t2) = freqOf s t1 + freqOf s t2 := by
      simp [unite, freqOf]
    rw [h_unite]
    omega

lemma alphabet_huffman_eq_forest_alphabet (ts : List HuffTree) (h_nonempty : ts ≠ []) :
    alphabet (huffman ts) = forest_alphabet ts := by
  induction ts using huffman.induct with
  | case1 => exfalso; exact h_nonempty rfl
  | case2 t => simp [huffman, forest_alphabet]
  | case3 t1 t2 rest IH =>
    have h_rec : insortTree (unite t1 t2) rest ≠ [] := by
      rw [← List.length_pos_iff_ne_nil, insortTree_length]
      omega
    simp [huffman, forest_alphabet_insortTree, IH h_rec]
    simp [forest_alphabet]
    have h_unite : alphabet (unite t1 t2) = alphabet t1 ∪ alphabet t2 := by
      simp [unite, alphabet]
    rw [h_unite]
    ac_rfl

lemma forest_sorted_insortTree_head (t : HuffTree) (ts : List HuffTree)
    (h_sorted : forest_sorted (t :: ts)) : forest_sorted (insortTree t ts) := by
  induction ts generalizing t with
  | nil => simp [insortTree, forest_sorted]
  | cons u us ih =>
    have htu : rootFreq t ≤ rootFreq u := by
      simp [forest_sorted] at h_sorted
      exact h_sorted.1
    simp [insortTree, htu]
    simpa [forest_sorted] using h_sorted

lemma forest_consistent_cons_iff (t : HuffTree) (ts : List HuffTree) :
    forest_consistent (t :: ts) ↔
      consistent t ∧ forest_consistent ts ∧ ∀ u ∈ ts, Disjoint (alphabet t) (alphabet u) := by
  cases ts with
  | nil => simp [forest_consistent]
  | cons u us => simp [forest_consistent]

lemma forest_consistent_tail (t : HuffTree) (ts : List HuffTree)
    (h_cons : forest_consistent (t :: ts)) : forest_consistent ts := by
  rw [forest_consistent_cons_iff] at h_cons
  exact h_cons.2.1

lemma forall_mem_tail {α : Type*} {P : α → Prop} (t : α) (ts : List α)
    (h : ∀ x ∈ t :: ts, P x) : ∀ x ∈ ts, P x := by
  intro x hx
  exact h x (by simp [hx])

lemma forest_consistent_insortTree_fresh (z fz : ℕ) (ts : List HuffTree)
    (h_fresh : ∀ t ∈ ts, z ∉ alphabet t)
    (h_cons : forest_consistent ts) :
    forest_consistent (insortTree (htLeaf z fz) ts) := by
  induction ts with
  | nil =>
    simp [insortTree, forest_consistent]
    simp [consistent]
  | cons u us ih =>
    have h_fresh_u : z ∉ alphabet u := h_fresh u (by simp)
    have h_fresh_us : ∀ t ∈ us, z ∉ alphabet t := forall_mem_tail u us h_fresh
    have h_cons_us : forest_consistent us := forest_consistent_tail u us h_cons
    rw [forest_consistent_cons_iff] at h_cons
    have hcu : consistent u := h_cons.1
    have hdisj_u : ∀ w ∈ us, Disjoint (alphabet u) (alphabet w) := h_cons.2.2
    simp [insortTree]
    split_ifs with h
    · -- fresh leaf becomes the head: htLeaf z fz :: u :: us
      rw [forest_consistent_cons_iff]
      refine ⟨by simp [consistent], ?_, ?_⟩
      · rw [forest_consistent_cons_iff]
        refine ⟨hcu, h_cons_us, hdisj_u⟩
      · intro w hw
        simp [alphabet] at hw ⊢
        cases hw with
        | inl h_eq =>
          rw [h_eq]
          exact h_fresh_u
        | inr h_mem =>
          exact h_fresh_us w h_mem
    · -- recurse: u :: insortTree (htLeaf z fz) us
      rw [forest_consistent_cons_iff]
      have h_cons_insort : forest_consistent (insortTree (htLeaf z fz) us) :=
        ih h_fresh_us h_cons_us
      have hdisj_u_insort : ∀ w ∈ insortTree (htLeaf z fz) us, Disjoint (alphabet u) (alphabet w) := by
        intro w hw
        rw [mem_insortTree] at hw
        cases hw with
        | inl h_eq =>
          rw [h_eq]
          simp [alphabet]
          exact h_fresh_u
        | inr h_mem =>
          exact hdisj_u w h_mem
      refine ⟨hcu, h_cons_insort, hdisj_u_insort⟩

lemma forest_freq_pos_of_all_leaves_pos (ts : List HuffTree) (s : ℕ)
    (h_leaves : ∀ t ∈ ts, height t = 0)
    (h_pos : ∀ t ∈ ts, rootFreq t > 0)
    (h_mem : s ∈ forest_alphabet ts) :
    forest_freq ts s > 0 := by
  rw [mem_forest_alphabet] at h_mem
  rcases h_mem with ⟨t, ht, hs⟩
  have h_leaf : height t = 0 := h_leaves t ht
  rcases height_eq_zero_iff t |>.mp h_leaf with ⟨sym, f, ht_eq⟩
  rw [ht_eq] at ht hs
  simp [alphabet] at hs
  subst hs
  have hf_pos : f > 0 := by
    simpa [rootFreq] using h_pos (htLeaf s f) ht
  have h_freq_pos : freqOf s (htLeaf s f) > 0 := by simp [freqOf]; exact hf_pos
  have h_sum_pos : forest_freq ts s > 0 := by
    simp [forest_freq]
    have h1 : freqOf s (htLeaf s f) ∈ ts.map (freqOf s) := by
      apply List.mem_map_of_mem
      exact ht
    have h2 : freqOf s (htLeaf s f) ≤ (ts.map (freqOf s)).sum := by
      apply List.single_le_sum
      · intro x _; exact Nat.zero_le x
      · exact h1
    omega
  exact h_sum_pos

lemma forest_freq_eq_zero_of_not_mem (ts : List HuffTree) (s : ℕ)
    (h : s ∉ forest_alphabet ts) : forest_freq ts s = 0 := by
  simp [forest_freq]
  apply List.sum_eq_zero
  intro x hx
  rcases List.mem_map.mp hx with ⟨t, ht, rfl⟩
  have h_not_mem : s ∉ alphabet t := by
    by_contra h_mem
    have : s ∈ forest_alphabet ts := by
      rw [mem_forest_alphabet]
      refine ⟨t, ht, h_mem⟩
    contradiction
  have h_zero : freqOf s t = 0 := freqOf_eq_zero_of_not_mem s t h_not_mem
  simp [h_zero]

lemma forest_freq_eq_rootFreq_of_mem_leaf (ts : List HuffTree) (s : ℕ) (t : HuffTree)
    (h_leaves : ∀ u ∈ ts, height u = 0)
    (h_cons : forest_consistent ts)
    (ht : t ∈ ts)
    (hs : s ∈ alphabet t) :
    forest_freq ts s = rootFreq t := by
  induction ts generalizing t with
  | nil => simp at ht
  | cons u us ih =>
    by_cases h_eq : t = u
    · -- t is the head
      subst h_eq
      simp [forest_freq]
      have h_zero : forest_freq us s = 0 := by
        apply forest_freq_eq_zero_of_not_mem
        rw [mem_forest_alphabet]
        intro h
        rcases h with ⟨v, hv, h_mem⟩
        have h_disjoint : Disjoint (alphabet t) (alphabet v) := by
          rw [forest_consistent_cons_iff] at h_cons
          exact h_cons.2.2 v hv
        have h_s_in_tv : s ∈ alphabet t ∩ alphabet v := by
          simp [hs, h_mem]
        rw [Finset.disjoint_iff_inter_eq_empty.mp h_disjoint] at h_s_in_tv
        simp at h_s_in_tv
      have h_freq_t : freqOf s t = rootFreq t := by
        have h_leaf_t : height t = 0 := h_leaves t (by simp)
        rcases height_eq_zero_iff t |>.mp h_leaf_t with ⟨sym, f, ht_eq⟩
        rw [ht_eq] at hs
        simp [alphabet] at hs
        subst hs
        rw [ht_eq]
        simp [freqOf, rootFreq]
      simp [h_freq_t, forest_freq] at h_zero ⊢
      omega
    · -- t is in the tail
      have h_mem' : t ∈ us := by
        simp [h_eq] at ht
        exact ht
      simp [forest_freq]
      have h_zero : freqOf s u = 0 := by
        have h_not_mem : s ∉ alphabet u := by
          rw [forest_consistent_cons_iff] at h_cons
          have h_disjoint : Disjoint (alphabet u) (alphabet t) := h_cons.2.2 t h_mem'
          intro h_su
          have h_s_in_ut : s ∈ alphabet u ∩ alphabet t := by
            simp [h_su, hs]
          rw [Finset.disjoint_iff_inter_eq_empty.mp h_disjoint] at h_s_in_ut
          simp at h_s_in_ut
        exact freqOf_eq_zero_of_not_mem s u h_not_mem
      have h_rec : forest_freq us s = rootFreq t := by
        apply ih
        · intro v hv
          exact h_leaves v (by simp [hv])
        · rw [forest_consistent_cons_iff] at h_cons
          exact h_cons.2.1
        · exact h_mem'
        · exact hs
      simp [forest_freq] at h_rec ⊢
      simp [h_zero, h_rec]


-- Sortedness lemmas for insertion into a forest

lemma forest_sorted_tail (t : HuffTree) (ts : List HuffTree)
    (h_sorted : forest_sorted (t :: ts)) : forest_sorted ts := by
  cases ts with
  | nil => simp [forest_sorted]
  | cons u us => simpa [forest_sorted] using h_sorted.2

lemma forest_sorted_insortTree_of_sorted (t : HuffTree) (ts : List HuffTree)
    (h_sorted : forest_sorted ts) : forest_sorted (insortTree t ts) := by
  induction ts generalizing t with
  | nil => simp [insortTree, forest_sorted]
  | cons u us ih =>
    have h_sorted_us : forest_sorted us := forest_sorted_tail u us h_sorted
    have ih' := ih t h_sorted_us
    simp [insortTree]
    by_cases h : rootFreq t ≤ rootFreq u
    · simp [h, forest_sorted, h_sorted]
    · simp [h]
      have h_ne : insortTree t us ≠ [] := by
        rw [← List.length_pos_iff_ne_nil, insortTree_length]
        omega
      have h1 : rootFreq u ≤ rootFreq ((insortTree t us).head h_ne) := by
        cases us with
        | nil =>
          simp [insortTree]
          omega
        | cons v vs =>
          simp [insortTree]
          by_cases h2 : rootFreq t ≤ rootFreq v
          · simp [h2]; omega
          · simp [h2]; simp [forest_sorted] at h_sorted; omega
      have ih' := ih t h_sorted_us
      cases h_r : insortTree t us with
      | nil =>
        exfalso
        exact h_ne h_r
      | cons x xs =>
        simp [h_r] at h1 ih'
        simp [forest_sorted]
        constructor
        · exact h1
        · exact ih'

-- Consistency is preserved by insertion and by Huffman merging

lemma forest_consistent_insortTree (t : HuffTree) (ts : List HuffTree)
    (h_cons : forest_consistent (t :: ts)) :
    forest_consistent (insortTree t ts) := by
  induction ts generalizing t with
  | nil => simpa [insortTree]
  | cons u us ih =>
    have h_cons_u_us : forest_consistent (u :: us) := by
      rw [forest_consistent_cons_iff] at h_cons
      exact h_cons.2.1
    have h_cons_us : forest_consistent us :=
      forest_consistent_tail u us h_cons_u_us
    have h_cons_t_us : forest_consistent (t :: us) := by
      rw [forest_consistent_cons_iff]
      refine ⟨?_, h_cons_us, ?_⟩
      · rw [forest_consistent_cons_iff] at h_cons
        exact h_cons.1
      · intro w hw
        rw [forest_consistent_cons_iff] at h_cons
        exact h_cons.2.2 w (by simp [hw])
    have ih' := ih t h_cons_t_us
    simp [insortTree]
    by_cases h : rootFreq t ≤ rootFreq u
    · -- insortTree places t at the head: t :: u :: us
      simp [h]
      exact h_cons
    · -- insortTree keeps u at the head
      simp [h]
      rw [forest_consistent_cons_iff]
      refine ⟨?_, ih', ?_⟩
      · rw [forest_consistent_cons_iff] at h_cons_u_us
        exact h_cons_u_us.1
      · intro w hw
        rw [mem_insortTree] at hw
        rcases hw with rfl | hw
        · -- w = t
          rw [forest_consistent_cons_iff] at h_cons
          have hdisj : Disjoint (alphabet w) (alphabet u) :=
            h_cons.2.2 u (by simp)
          exact Disjoint.symm hdisj
        · -- w ∈ us
          rw [forest_consistent_cons_iff] at h_cons_u_us
          exact h_cons_u_us.2.2 w hw

lemma consistent_unite (t1 t2 : HuffTree)
    (h1 : consistent t1) (h2 : consistent t2)
    (hdisj : Disjoint (alphabet t1) (alphabet t2)) :
    consistent (unite t1 t2) := by
  simp [unite, consistent, h1, h2, hdisj]

lemma forest_consistent_unite_head (t1 t2 : HuffTree) (rest : List HuffTree)
    (h_cons : forest_consistent (t1 :: t2 :: rest)) :
    forest_consistent (unite t1 t2 :: rest) := by
  cases rest with
  | nil =>
    simp [forest_consistent]
    have h1 : consistent t1 := h_cons.1
    have h2 : consistent t2 := h_cons.2.1
    have h12 : Disjoint (alphabet t1) (alphabet t2) := h_cons.2.2 t2 (by simp)
    exact consistent_unite t1 t2 h1 h2 h12
  | cons r rs =>
    rw [forest_consistent_cons_iff] at h_cons
    rw [forest_consistent_cons_iff]
    have h1 : consistent t1 := h_cons.1
    have h2 : consistent t2 := h_cons.2.1.1
    have hrs : forest_consistent (r :: rs) := h_cons.2.1.2.1
    have h2r : ∀ w ∈ r :: rs, Disjoint (alphabet t2) (alphabet w) := h_cons.2.1.2.2
    have h12 : Disjoint (alphabet t1) (alphabet t2) := h_cons.2.2 t2 (by simp)
    have h1rs : ∀ w ∈ r :: rs, Disjoint (alphabet t1) (alphabet w) := by
      intro w hw
      exact h_cons.2.2 w (by simp [hw])
    refine ⟨consistent_unite t1 t2 h1 h2 h12, hrs, ?_⟩
    intro w hw
    simp [unite, alphabet]
    constructor
    · exact h1rs w hw
    · exact h2r w hw

lemma consistent_huffman_of_consistent (ts : List HuffTree)
    (h_nonempty : ts ≠ []) (h_cons : forest_consistent ts) :
    consistent (huffman ts) := by
  induction ts using huffman.induct with
  | case1 =>
    exfalso; exact h_nonempty rfl
  | case2 t =>
    simp [huffman]
    simp [forest_consistent] at h_cons
    exact h_cons
  | case3 t1 t2 rest IH =>
    have h_rec : insortTree (unite t1 t2) rest ≠ [] := by
      rw [← List.length_pos_iff_ne_nil, insortTree_length]
      omega
    simp [huffman]
    apply IH h_rec
    apply forest_consistent_insortTree
    apply forest_consistent_unite_head
    exact h_cons

-- Positivity of frequencies in a Huffman tree

lemma freqOf_huffman_pos_of_mem (ts : List HuffTree) (s : ℕ)
    (h_nonempty : ts ≠ [])
    (h_leaves : ∀ t ∈ ts, height t = 0)
    (h_pos : ∀ t ∈ ts, rootFreq t > 0)
    (h_cons : forest_consistent ts)
    (h_mem : s ∈ alphabet (huffman ts)) :
    freqOf s (huffman ts) > 0 := by
  rw [freqOf_huffman_eq_forest_freq ts s h_nonempty]
  rw [alphabet_huffman_eq_forest_alphabet ts h_nonempty] at h_mem
  exact forest_freq_pos_of_all_leaves_pos ts s h_leaves h_pos h_mem

-- Sortedness implies the head frequency is a lower bound for the tail

lemma rootFreq_le_of_mem_sorted (t : HuffTree) (ts : List HuffTree)
    (h_sorted : forest_sorted (t :: ts)) :
    ∀ u ∈ ts, rootFreq t ≤ rootFreq u := by
  induction ts generalizing t with
  | nil => simp
  | cons v vs ih =>
    intro u hu
    simp [forest_sorted] at h_sorted
    by_cases huv : u = v
    · rw [huv]; exact h_sorted.1
    · have hu' : u ∈ vs := by
        simp [huv] at hu
        exact hu
      have htv : rootFreq t ≤ rootFreq v := h_sorted.1
      have h_sorted_t_vs : forest_sorted (t :: vs) := by
        cases vs with
        | nil => simp [forest_sorted]
        | cons w ws =>
          simp [forest_sorted]
          constructor
          · -- rootFreq t ≤ rootFreq w
            have hvw : rootFreq v ≤ rootFreq w := by
              apply ih v h_sorted.2 w (by simp)
            omega
          · exact h_sorted.2.2
      have htw : rootFreq t ≤ rootFreq u := ih t h_sorted_t_vs u hu'
      exact htw
```
{% endraw %}
</details>

<details>
<summary><b>Commutation.lean</b> — splitLeaf 与 huffman 交换律</summary>

{% raw %}
```lean
import CfProofs.Greedy.Huffman.Base

open HuffTree

/-!
# splitLeaf–huffman Commutation Lemma

Blanchette (2009) "Proof Pearl", translated to Lean 4.

`splitLeaf (huffman ts) s1 s1 s2 f1 f2 = huffman (ts.map (λ t => splitLeaf t s1 s1 s2 f1 f2))`

**Key condition**: `rootFreq (splitLeaf t) = rootFreq t` for all trees `t` in the forest.
This is preserved by `unite` (rootFreq adds) and `insortTree` (comparisons use rootFreq).
No consistency or disjointness required.
-/

lemma insortTree_length (t : HuffTree) (ts : List HuffTree) : (insortTree t ts).length = ts.length + 1 := by
  induction ts with
  | nil => simp [insortTree]
  | cons u us ih => simp [insortTree]; split <;> simp [ih]

@[simp] lemma splitLeaf_unite (l r : HuffTree) (z a b fa fb : ℕ) :
    splitLeaf (unite l r) z a b fa fb = unite (splitLeaf l z a b fa fb) (splitLeaf r z a b fa fb) := by
  simp [unite, splitLeaf]

/-- `rootFreq` of `unite` is the sum. -/
@[simp] lemma rootFreq_unite (t1 t2 : HuffTree) : rootFreq (unite t1 t2) = rootFreq t1 + rootFreq t2 := by
  simp [unite, rootFreq]

/-! ### RootFreq preservation is the ONLY condition needed -/

lemma rootFreq_splitLeaf_unite (t1 t2 : HuffTree) (s1 s2 f1 f2 : ℕ)
    (h1 : rootFreq (splitLeaf t1 s1 s1 s2 f1 f2) = rootFreq t1)
    (h2 : rootFreq (splitLeaf t2 s1 s1 s2 f1 f2) = rootFreq t2) :
    rootFreq (splitLeaf (unite t1 t2) s1 s1 s2 f1 f2) = rootFreq (unite t1 t2) := by
  simp [h1, h2]

/-! ### `insortTree` commutation with `map splitLeaf` -/

lemma map_splitLeaf_insortTree (U : HuffTree) (ts : List HuffTree) (s1 s2 f1 f2 : ℕ)
    (hU_rf : rootFreq (splitLeaf U s1 s1 s2 f1 f2) = rootFreq U)
    (hts_rf : ∀ t ∈ ts, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t) :
    (insortTree U ts).map (λ t => splitLeaf t s1 s1 s2 f1 f2)
    = insortTree (splitLeaf U s1 s1 s2 f1 f2) (ts.map (λ t => splitLeaf t s1 s1 s2 f1 f2)) := by
  induction ts generalizing U with
  | nil => simp [insortTree]
  | cons t us ih =>
    have h_us_rf : ∀ u ∈ us, rootFreq (splitLeaf u s1 s1 s2 f1 f2) = rootFreq u :=
      fun u hu => hts_rf u (by simp [hu])
    have ht_rf := hts_rf t (by simp)
    simp [insortTree, List.map_cons]
    by_cases h_rf : rootFreq U ≤ rootFreq t
    · have h_rf' : rootFreq (splitLeaf U s1 s1 s2 f1 f2) ≤ rootFreq (splitLeaf t s1 s1 s2 f1 f2) := by
        rw [hU_rf, ht_rf]; exact h_rf
      simp [h_rf, h_rf']
    · have h_rf' : ¬ rootFreq (splitLeaf U s1 s1 s2 f1 f2) ≤ rootFreq (splitLeaf t s1 s1 s2 f1 f2) := by
        rw [hU_rf, ht_rf]; exact h_rf
      simp [h_rf, h_rf', ih U hU_rf h_us_rf]

/-! ### `insortTree` membership -/

lemma mem_insortTree (t : HuffTree) (ts : List HuffTree) (u : HuffTree) :
    u ∈ insortTree t ts ↔ u = t ∨ u ∈ ts := by
  induction ts generalizing t with
  | nil => simp [insortTree]
  | cons v vs ih =>
    simp [insortTree]
    by_cases h : rootFreq t ≤ rootFreq v
    · simp [h, ih, or_assoc]
    · simp [h, ih, or_assoc, or_comm, or_left_comm]

lemma forall_mem_insortTree {P : HuffTree → Prop} {U : HuffTree} {ts : List HuffTree}
    (hU : P U) (hts : ∀ t ∈ ts, P t) : ∀ t ∈ insortTree U ts, P t := by
  intro t ht
  rcases (mem_insortTree U ts t).mp ht with (rfl | ht')
  · exact hU
  · exact hts t ht'

/-! ### MAIN THEOREM -/

theorem splitLeaf_huffman_commute_general (ts : List HuffTree) (s1 s2 f1 f2 : ℕ)
    (h_nonempty : ts ≠ [])
    (h_rf_forest : ∀ t ∈ ts, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t) :
    splitLeaf (huffman ts) s1 s1 s2 f1 f2
    = huffman (ts.map (λ t => splitLeaf t s1 s1 s2 f1 f2)) := by
  induction ts using huffman.induct with
  | case1 =>
    exfalso; exact h_nonempty rfl
  | case2 t => simp [huffman]
  | case3 t1 t2 rest IH =>
    have h1_rf := h_rf_forest t1 (by simp)
    have h2_rf := h_rf_forest t2 (by simp)
    have h_rest_rf : ∀ t ∈ rest, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
      fun t ht => h_rf_forest t (by simp [ht])
    let U := unite t1 t2
    -- rootFreq preserved for U
    have hU_rf : rootFreq (splitLeaf U s1 s1 s2 f1 f2) = rootFreq U :=
      rootFreq_splitLeaf_unite t1 t2 s1 s2 f1 f2 h1_rf h2_rf
    -- rootFreq preserved for the recursive forest (U + rest, via insortTree)
    have h_rec_rf : ∀ t ∈ insortTree U rest,
        rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
      forall_mem_insortTree (P := λ t => rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t)
        hU_rf h_rest_rf
    simp [huffman, List.map_cons, splitLeaf_unite, U]
    have h_nonempty_rec : insortTree U rest ≠ [] := by
      rw [← List.length_pos_iff_ne_nil, insortTree_length U rest]
      omega
    rw [IH h_nonempty_rec h_rec_rf]
    have hU_rf' : rootFreq (splitLeaf U s1 s1 s2 f1 f2) = rootFreq U :=
      h_rec_rf U ((mem_insortTree U rest U).mpr (Or.inl rfl))
    have h_rest_rf' : ∀ t ∈ rest, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
      fun t ht => h_rec_rf t ((mem_insortTree U rest t).mpr (Or.inr ht))
    rw [map_splitLeaf_insortTree U rest s1 s2 f1 f2 hU_rf' h_rest_rf']
    rfl

/-! ### `splitLeaf` identity on a whole forest -/

lemma map_splitLeaf_id_of_not_mem (s1 s2 f1 f2 : ℕ) (ts : List HuffTree)
    (h : ∀ t ∈ ts, s1 ∉ alphabet t) : ts.map (λ t => splitLeaf t s1 s1 s2 f1 f2) = ts := by
  induction ts with
  | nil => rfl
  | cons t ts ih =>
    have h_t : s1 ∉ alphabet t := h t (by simp)
    have h_ts : ∀ t' ∈ ts, s1 ∉ alphabet t' := fun t' ht' => h t' (by simp [ht'])
    simp [splitLeaf_eq_of_z_not_mem t s1 s1 s2 f1 f2 h_t, ih h_ts]

/-! ### Special case for `optimum_huffman` -/

/--
Given a forest `rest` where `s1` appears only as `htLeaf s1 (f1+f2)` (the combined leaf),
we have the commutation:

`splitLeaf (huffman (insortTree (htLeaf s1 (f1+f2)) rest)) s1 s1 s2 f1 f2`
`= huffman (insortTree (htInner (htLeaf s1 f1) (htLeaf s2 f2)) rest)`

Requires: `s1 ∉ alphabet t` for all `t ∈ rest`, so that `splitLeaf` does nothing on `rest`.
-/
theorem splitLeaf_huffman_commute (s1 s2 f1 f2 : ℕ) (rest : List HuffTree)
    (h_s1_notin_rest : ∀ t ∈ rest, s1 ∉ alphabet t) :
    splitLeaf (huffman (insortTree (htLeaf s1 (f1+f2)) rest)) s1 s1 s2 f1 f2
    = huffman (insortTree (htInner (htLeaf s1 f1) (htLeaf s2 f2)) rest) := by
  let LF := htLeaf s1 (f1+f2)
  let IF := htInner (htLeaf s1 f1) (htLeaf s2 f2)
  -- rootFreq is preserved for LF itself (both sides = f1+f2)
  have h_LF_rf : rootFreq (splitLeaf LF s1 s1 s2 f1 f2) = rootFreq LF := by
    simp [LF, splitLeaf, rootFreq]
  -- rootFreq is preserved for rest (splitLeaf is identity since s1 ∉ alphabet)
  have h_rest_rf : ∀ t ∈ rest, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t := by
    intro t ht
    have h_id : splitLeaf t s1 s1 s2 f1 f2 = t :=
      splitLeaf_eq_of_z_not_mem t s1 s1 s2 f1 f2 (h_s1_notin_rest t ht)
    rw [h_id]
  -- rootFreq preserved for the whole insortTree forest
  have h_rf_forest : ∀ t ∈ insortTree LF rest,
      rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
    forall_mem_insortTree (P := λ t => rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t)
      h_LF_rf h_rest_rf
  -- Commutation via the general theorem
  calc
    splitLeaf (huffman (insortTree LF rest)) s1 s1 s2 f1 f2
        = huffman ((insortTree LF rest).map (λ t => splitLeaf t s1 s1 s2 f1 f2)) :=
      splitLeaf_huffman_commute_general (insortTree LF rest) s1 s2 f1 f2
        (by
          -- insortTree LF rest is always nonempty
          intro h_empty
          have : (insortTree LF rest).length = 0 := by simpa [h_empty] using rfl
          -- Actually insortTree returns length = rest.length + 1 ≥ 1
          have h_len : (insortTree LF rest).length = rest.length + 1 := insortTree_length LF rest
          rw [h_len] at this; omega)
        h_rf_forest
    _ = huffman (insortTree (splitLeaf LF s1 s1 s2 f1 f2) (rest.map (λ t => splitLeaf t s1 s1 s2 f1 f2))) := by
      have hLF_rf' : rootFreq (splitLeaf LF s1 s1 s2 f1 f2) = rootFreq LF :=
        h_rf_forest LF ((mem_insortTree LF rest LF).mpr (Or.inl rfl))
      have h_rest_rf' : ∀ t ∈ rest, rootFreq (splitLeaf t s1 s1 s2 f1 f2) = rootFreq t :=
        fun t ht => h_rf_forest t ((mem_insortTree LF rest t).mpr (Or.inr ht))
      rw [map_splitLeaf_insortTree LF rest s1 s2 f1 f2 hLF_rf' h_rest_rf']
    _ = huffman (insortTree IF (rest.map (λ t => splitLeaf t s1 s1 s2 f1 f2))) := by
      simp [LF, IF, splitLeaf]
    _ = huffman (insortTree IF rest) := by
      -- splitLeaf is identity on rest (s1 ∉ alphabet), so the map doesn't change rest
      have h_map_id := map_splitLeaf_id_of_not_mem s1 s2 f1 f2 rest h_s1_notin_rest
      rw [h_map_id]
```
{% endraw %}
</details>

<details>
<summary><b>Optimal.lean</b> — optimum_splitLeaf 与 optimum_huffman</summary>

{% raw %}
```lean
import CfProofs.Greedy.Huffman.Base
import CfProofs.Greedy.Huffman.SwapBasic
import CfProofs.Greedy.Huffman.SwapFreqDepth
import CfProofs.Greedy.Huffman.SwapDisjoint
import CfProofs.Greedy.Huffman.MergeLemmas
import CfProofs.Greedy.Huffman.Preservation

open HuffTree

def deepestSiblingPair (t : HuffTree) : ℕ × ℕ :=
  match t with
  | htLeaf s _ => (s, s)
  | htInner l r =>
    match l, r with
    | htLeaf x _, htLeaf y _ => (x, y)
    | htLeaf _ _, _ => deepestSiblingPair r
    | _, htLeaf _ _ => deepestSiblingPair l
    | _, _ => if height l ≥ height r then deepestSiblingPair l else deepestSiblingPair r

lemma deepestSiblingPair_mem1 (t : HuffTree) : (deepestSiblingPair t).1 ∈ alphabet t := by
  induction t with
  | htLeaf s f => simp [deepestSiblingPair, alphabet]
  | htInner l r ihl ihr =>
    cases l with
    | htLeaf x fx => cases r with
      | htLeaf y fy => simp [deepestSiblingPair, alphabet]
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htLeaf x fx) (htInner rl rr)) = deepestSiblingPair (htInner rl rr) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htLeaf x fx) (htInner rl rr)) = {x} ∪ alphabet (htInner rl rr) := by simp [alphabet]
        rw [h_dsp, h_alph]; exact Finset.mem_union_right {x} ihr
    | htInner ll lr => cases r with
      | htLeaf y fy =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htLeaf y fy)) = deepestSiblingPair (htInner ll lr) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htInner ll lr) (htLeaf y fy)) = alphabet (htInner ll lr) ∪ {y} := by simp [alphabet]
        rw [h_dsp, h_alph]; exact Finset.mem_union_left {y} ihl
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htInner rl rr)) = (if height (htInner ll lr) ≥ height (htInner rl rr) then deepestSiblingPair (htInner ll lr) else deepestSiblingPair (htInner rl rr)) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htInner ll lr) (htInner rl rr)) = alphabet (htInner ll lr) ∪ alphabet (htInner rl rr) := by simp [alphabet]
        rw [h_dsp, h_alph]
        by_cases h_ge : height (htInner ll lr) ≥ height (htInner rl rr)
        · rw [if_pos h_ge]; exact Finset.mem_union_left (alphabet (htInner rl rr)) ihl
        · rw [if_neg h_ge]; exact Finset.mem_union_right (alphabet (htInner ll lr)) ihr

lemma deepestSiblingPair_mem2 (t : HuffTree) : (deepestSiblingPair t).2 ∈ alphabet t := by
  induction t with
  | htLeaf s f => simp [deepestSiblingPair, alphabet]
  | htInner l r ihl ihr =>
    cases l with
    | htLeaf x fx => cases r with
      | htLeaf y fy => simp [deepestSiblingPair, alphabet]
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htLeaf x fx) (htInner rl rr)) = deepestSiblingPair (htInner rl rr) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htLeaf x fx) (htInner rl rr)) = {x} ∪ alphabet (htInner rl rr) := by simp [alphabet]
        rw [h_dsp, h_alph]; exact Finset.mem_union_right {x} ihr
    | htInner ll lr => cases r with
      | htLeaf y fy =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htLeaf y fy)) = deepestSiblingPair (htInner ll lr) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htInner ll lr) (htLeaf y fy)) = alphabet (htInner ll lr) ∪ {y} := by simp [alphabet]
        rw [h_dsp, h_alph]; exact Finset.mem_union_left {y} ihl
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htInner rl rr)) = (if height (htInner ll lr) ≥ height (htInner rl rr) then deepestSiblingPair (htInner ll lr) else deepestSiblingPair (htInner rl rr)) := by simp [deepestSiblingPair]
        have h_alph : alphabet (htInner (htInner ll lr) (htInner rl rr)) = alphabet (htInner ll lr) ∪ alphabet (htInner rl rr) := by simp [alphabet]
        rw [h_dsp, h_alph]
        by_cases h_ge : height (htInner ll lr) ≥ height (htInner rl rr)
        · rw [if_pos h_ge]; exact Finset.mem_union_left (alphabet (htInner rl rr)) ihl
        · rw [if_neg h_ge]; exact Finset.mem_union_right (alphabet (htInner ll lr)) ihr

lemma depthOf_getD_inner_of_mem_left {s : ℕ} {l r : HuffTree} (h : s ∈ alphabet l) :
    (depthOf s (htInner l r)).getD 0 = (depthOf s l).getD 0 + 1 := by
  have ⟨d, hd⟩ := depthOf_some_of_mem s l h
  simp [depthOf, hd]

lemma depthOf_getD_inner_of_mem_right {s : ℕ} {l r : HuffTree} (h : s ∈ alphabet r) (h_not : s ∉ alphabet l) :
    (depthOf s (htInner l r)).getD 0 = (depthOf s r).getD 0 + 1 := by
  have ⟨d, hd⟩ := depthOf_some_of_mem s r h
  simp [depthOf, depthOf_none_of_not_mem s l h_not, hd]

lemma deepestSiblingPair_depth (t : HuffTree) (h_cons : consistent t) :
    (depthOf (deepestSiblingPair t).1 t).getD 0 = height t ∧ (depthOf (deepestSiblingPair t).2 t).getD 0 = height t := by
  induction t with
  | htLeaf s f => simp [deepestSiblingPair, depthOf, height]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    cases l with
    | htLeaf x fx =>
      cases r with
      | htLeaf y fy =>
        simp [deepestSiblingPair, height]
        have hx : (depthOf x (htInner (htLeaf x fx) (htLeaf y fy))).getD 0 = 1 := by
          simp [depthOf, Option.getD]
        have hy : (depthOf y (htInner (htLeaf x fx) (htLeaf y fy))).getD 0 = 1 := by
          by_cases h_eq : x = y
          · subst h_eq; simp [depthOf, Option.getD]
          · simp [depthOf, h_eq, Option.getD]
        exact And.intro hx hy
      | htInner rl rr =>
        have h_dsp : deepestSiblingPair (htInner (htLeaf x fx) (htInner rl rr)) = deepestSiblingPair (htInner rl rr) := by
          simp [deepestSiblingPair]
        have h_height : height (htInner (htLeaf x fx) (htInner rl rr)) = height (htInner rl rr) + 1 := by
          simp [height]
        rw [h_dsp, h_height]
        rcases ihr hcr with ⟨h1, h2⟩
        have h_mem1 : (deepestSiblingPair (htInner rl rr)).1 ∈ alphabet (htInner rl rr) :=
          deepestSiblingPair_mem1 (htInner rl rr)
        have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
        have h_not_mem_l1 : (deepestSiblingPair (htInner rl rr)).1 ∉ alphabet (htLeaf x fx) := by
          intro hm; have hi := Finset.mem_inter.mpr ⟨hm, h_mem1⟩; rw [h_empty] at hi; simp at hi
        have h_mem2 : (deepestSiblingPair (htInner rl rr)).2 ∈ alphabet (htInner rl rr) :=
          deepestSiblingPair_mem2 (htInner rl rr)
        have h_not_mem_l2 : (deepestSiblingPair (htInner rl rr)).2 ∉ alphabet (htLeaf x fx) := by
          intro hm; have hi := Finset.mem_inter.mpr ⟨hm, h_mem2⟩; rw [h_empty] at hi; simp at hi
        constructor
        · rw [depthOf_getD_inner_of_mem_right h_mem1 h_not_mem_l1, h1]
        · rw [depthOf_getD_inner_of_mem_right h_mem2 h_not_mem_l2, h2]
    | htInner ll lr =>
      cases r with
      | htLeaf y fy =>
        have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htLeaf y fy)) = deepestSiblingPair (htInner ll lr) := by
          simp [deepestSiblingPair]
        have h_height : height (htInner (htInner ll lr) (htLeaf y fy)) = height (htInner ll lr) + 1 := by
          simp [height]
        rw [h_dsp, h_height]
        rcases ihl hcl with ⟨h1, h2⟩
        have h_mem1 : (deepestSiblingPair (htInner ll lr)).1 ∈ alphabet (htInner ll lr) :=
          deepestSiblingPair_mem1 (htInner ll lr)
        have h_mem2 : (deepestSiblingPair (htInner ll lr)).2 ∈ alphabet (htInner ll lr) :=
          deepestSiblingPair_mem2 (htInner ll lr)
        constructor
        · rw [depthOf_getD_inner_of_mem_left h_mem1, h1]
        · rw [depthOf_getD_inner_of_mem_left h_mem2, h2]
      | htInner rl rr =>
        have h_height : height (htInner (htInner ll lr) (htInner rl rr)) = max (height (htInner ll lr)) (height (htInner rl rr)) + 1 := by
          simp [height]
        rw [h_height]
        by_cases h_ge : height (htInner ll lr) ≥ height (htInner rl rr)
        · have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htInner rl rr)) = deepestSiblingPair (htInner ll lr) := by
            simp [deepestSiblingPair, h_ge]
          have h_max : max (height (htInner ll lr)) (height (htInner rl rr)) = height (htInner ll lr) := by
            simp [h_ge]
          rw [h_dsp, h_max]
          rcases ihl hcl with ⟨h1, h2⟩
          have h_mem1 : (deepestSiblingPair (htInner ll lr)).1 ∈ alphabet (htInner ll lr) :=
            deepestSiblingPair_mem1 (htInner ll lr)
          have h_mem2 : (deepestSiblingPair (htInner ll lr)).2 ∈ alphabet (htInner ll lr) :=
            deepestSiblingPair_mem2 (htInner ll lr)
          constructor
          · rw [depthOf_getD_inner_of_mem_left h_mem1, h1]
          · rw [depthOf_getD_inner_of_mem_left h_mem2, h2]
        · have h_dsp : deepestSiblingPair (htInner (htInner ll lr) (htInner rl rr)) = deepestSiblingPair (htInner rl rr) := by
            simp [deepestSiblingPair, h_ge]
          have h_max : max (height (htInner ll lr)) (height (htInner rl rr)) = height (htInner rl rr) :=
            Nat.max_eq_right (by omega)
          rw [h_dsp, h_max]
          rcases ihr hcr with ⟨h1, h2⟩
          have h_mem1 : (deepestSiblingPair (htInner rl rr)).1 ∈ alphabet (htInner rl rr) :=
            deepestSiblingPair_mem1 (htInner rl rr)
          have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
          have h_not_mem_l1 : (deepestSiblingPair (htInner rl rr)).1 ∉ alphabet (htInner ll lr) := by
            intro hm; have hi := Finset.mem_inter.mpr ⟨hm, h_mem1⟩; rw [h_empty] at hi; simp at hi
          have h_mem2 : (deepestSiblingPair (htInner rl rr)).2 ∈ alphabet (htInner rl rr) :=
            deepestSiblingPair_mem2 (htInner rl rr)
          have h_not_mem_l2 : (deepestSiblingPair (htInner rl rr)).2 ∉ alphabet (htInner ll lr) := by
            intro hm; have hi := Finset.mem_inter.mpr ⟨hm, h_mem2⟩; rw [h_empty] at hi; simp at hi
          constructor
          · rw [depthOf_getD_inner_of_mem_right h_mem1 h_not_mem_l1, h1]
          · rw [depthOf_getD_inner_of_mem_right h_mem2 h_not_mem_l2, h2]

lemma deepestSiblingPair_areSiblings (t : HuffTree) (h_cons : consistent t)
    (h_height : height t ≥ 1) :
    areSiblings (deepestSiblingPair t).1 (deepestSiblingPair t).2 t := by
  induction t with
  | htLeaf s f => simp [height] at h_height
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    cases l with
    | htLeaf x fx =>
      cases r with
      | htLeaf y fy => exact areSiblings.here (a := x) (b := y) fx fy
      | htInner rl rr =>
        have hh_r : height (htInner rl rr) ≥ 1 := by simp [height]
        have hh := ihr hcr hh_r
        exact areSiblings.inRight (htLeaf x fx) (htInner rl rr) hh
    | htInner ll lr =>
      cases r with
      | htLeaf y fy =>
        have hh_l : height (htInner ll lr) ≥ 1 := by simp [height]
        have hh := ihl hcl hh_l
        exact areSiblings.inLeft (htInner ll lr) (htLeaf y fy) hh
      | htInner rl rr =>
        have hh_l : height (htInner ll lr) ≥ 1 := by simp [height]
        have hh_r : height (htInner rl rr) ≥ 1 := by simp [height]
        by_cases h_ge : height (htInner ll lr) ≥ height (htInner rl rr)
        · have hh := ihl hcl hh_l
          simpa [deepestSiblingPair, h_ge] using
            areSiblings.inLeft (htInner ll lr) (htInner rl rr) hh
        · have hh := ihr hcr hh_r
          simpa [deepestSiblingPair, h_ge] using
            areSiblings.inRight (htInner ll lr) (htInner rl rr) hh

lemma areSiblings_exchangeLeft (t : HuffTree) (a x y : ℕ) (h_sib : areSiblings x y t)
    (h_ne_ax : a ≠ x) (h_ne_ay : a ≠ y) (h_ne_xy : x ≠ y) : areSiblings a y (swapLeaves a x t) := by
  induction h_sib with
  | here fa fb =>
    simp [swapLeaves, h_ne_ax.symm, h_ne_ay.symm, h_ne_xy.symm]
    refine areSiblings.here (a := a) (b := y) ?_ ?_ <;> simp
  | here' fa fb =>
    simp [swapLeaves, h_ne_ax.symm, h_ne_ay.symm, h_ne_xy, h_ne_xy.symm]
    refine areSiblings.here' (a := a) (b := y) ?_ ?_ <;> simp
  | inLeft l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inLeft _ _ ih
  | inRight l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inRight _ _ ih

lemma areSiblings_exchangeRight (t : HuffTree) (a b x : ℕ) (h_sib : areSiblings a x t)
    (h_ne_ba : b ≠ a) (h_ne_bx : b ≠ x) (h_ne_ax : a ≠ x) : areSiblings a b (swapLeaves b x t) := by
  induction h_sib with
  | here fa fx =>
    simp [swapLeaves, h_ne_bx.symm, h_ne_ba.symm, h_ne_ax]
    refine areSiblings.here (a := a) (b := b) ?_ ?_ <;> simp
  | here' fa fx =>
    simp [swapLeaves, h_ne_bx.symm, h_ne_ba.symm, h_ne_ax, h_ne_ax.symm]
    refine areSiblings.here' (a := a) (b := b) ?_ ?_ <;> simp
  | inLeft l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inLeft _ _ ih
  | inRight l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inRight _ _ ih

lemma areSiblings_replaceFreq (t : HuffTree) (a b sym freq : ℕ) (h_sib : areSiblings a b t) :
    areSiblings a b (replaceFreq sym freq t) := by
  induction h_sib with
  | here fa fb =>
    simp [replaceFreq]; split <;> split <;> apply areSiblings.here
  | here' fa fb =>
    simp [replaceFreq]; split <;> split <;> apply areSiblings.here'
  | inLeft l r h ih =>
    simp [replaceFreq]; exact areSiblings.inLeft _ _ ih
  | inRight l r h ih =>
    simp [replaceFreq]; exact areSiblings.inRight _ _ ih

lemma areSiblings_swapFreqs_preserved (t : HuffTree) (a b x y : ℕ) (h_sib : areSiblings a b t) :
    areSiblings a b (swapFreqs x y t) := by
  dsimp [swapFreqs]
  apply areSiblings_replaceFreq _ _ _ _ _ (areSiblings_replaceFreq _ _ _ _ _ h_sib)

lemma areSiblings_ne (t : HuffTree) (a b : ℕ) (h_cons : consistent t) (h_sib : areSiblings a b t) : a ≠ b := by
  induction h_sib with
  | here fa fb =>
    rcases h_cons with ⟨_, _, hd⟩
    intro heq; subst heq
    simp [alphabet, Finset.disjoint_iff_inter_eq_empty] at hd
  | here' fa fb =>
    rcases h_cons with ⟨_, _, hd⟩
    intro heq; subst heq
    simp [alphabet, Finset.disjoint_iff_inter_eq_empty] at hd
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, _, _⟩
    exact ih hcl
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨_, hcr, _⟩
    exact ih hcr

private lemma areSiblings_swapLeaves_of_ne {a b z w : ℕ} {t : HuffTree}
    (h_sib : areSiblings a b t) (hz_ne_a : z ≠ a) (hz_ne_b : z ≠ b)
    (hw_ne_a : w ≠ a) (hw_ne_b : w ≠ b) : areSiblings a b (swapLeaves z w t) := by
  induction h_sib with
  | here fa fb =>
    simp [swapLeaves, Ne.symm hz_ne_a, Ne.symm hz_ne_b, hw_ne_a.symm, hw_ne_b.symm]
    exact areSiblings.here (a := a) (b := b) fa fb
  | here' fa fb =>
    simp [swapLeaves, Ne.symm hz_ne_a, Ne.symm hz_ne_b, hw_ne_a.symm, hw_ne_b.symm]
    exact areSiblings.here' (a := a) (b := b) fa fb
  | inLeft l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inLeft _ _ ih
  | inRight l r h ih =>
    simp [swapLeaves]
    exact areSiblings.inRight _ _ ih

lemma depthOf_getD_le_height (t : HuffTree) (s : ℕ) : (depthOf s t).getD 0 ≤ height t := by
  induction t with
  | htLeaf sym f => simp [depthOf, height]; split <;> simp
  | htInner l r ihl ihr =>
    simp [depthOf, height]
    cases h_l : depthOf s l with
    | none =>
      simp [h_l]
      cases h_r : depthOf s r with
      | none => simp
      | some d =>
        simp [h_r]
        have hd : d ≤ height r := by simpa [h_r] using ihr
        omega
    | some d =>
        simp [h_l]
        have hd : d ≤ height l := by simpa [h_l] using ihl
        omega

lemma rootFreq_ge_freqOf (t : HuffTree) (s : ℕ) : rootFreq t ≥ freqOf s t := by
  induction t with
  | htLeaf sym f => simp [rootFreq, freqOf]; split <;> omega
  | htInner l r ihl ihr => simp [rootFreq, freqOf]; omega

lemma optimum_leaf (s f : ℕ) (h_f_pos : f > 0) : optimum (htLeaf s f) := by
  refine ⟨by simp [consistent], ?_, ?_⟩
  · simp [alphabet, freqOf, h_f_pos]
  · intro u _ h_sameFreqs
    simpa [cost] using cost_nonneg u

lemma rootFreq_ge_freqOf_add (t : HuffTree) (a b : ℕ) (h_ne : a ≠ b) (h_cons : consistent t) :
    rootFreq t ≥ freqOf a t + freqOf b t := by
  induction t with
  | htLeaf s f =>
    simp [rootFreq, freqOf]
    by_cases h_a : s = a
    · subst h_a; simp [h_ne.symm]; omega
    · by_cases h_b : s = b
      · subst h_b; simp [h_ne]; omega
      · simp [h_a, h_b]
  | htInner l r ihl ihr =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    simp [rootFreq, freqOf]
    have h1 : rootFreq l ≥ freqOf a l + freqOf b l := ihl hcl
    have h2 : rootFreq r ≥ freqOf a r + freqOf b r := ihr hcr
    omega

lemma optimum_two_distinct_leaves (sa fa sb fb : ℕ) (h_ne : sa ≠ sb) (h_fa_pos : fa > 0) (h_fb_pos : fb > 0) :
    optimum (htInner (htLeaf sa fa) (htLeaf sb fb)) := by
  have h_ne' : sb ≠ sa := Ne.symm h_ne
  have h_pos : ∀ s ∈ alphabet (htInner (htLeaf sa fa) (htLeaf sb fb)), freqOf s (htInner (htLeaf sa fa) (htLeaf sb fb)) > 0 := by
    intro s hs
    simp [alphabet, Finset.mem_insert, Finset.mem_singleton] at hs
    rcases hs with (rfl | rfl)
    · simp [freqOf, h_ne', h_fa_pos]
    · simp [freqOf, h_ne, h_fb_pos]
  refine ⟨by simp [consistent, alphabet, h_ne], h_pos, ?_⟩
  intro u h_cons_u h_sameFreqs
  have h_fa : freqOf sa u = fa := by
    simpa [freqOf, h_ne'] using (h_sameFreqs sa).symm
  have h_fb : freqOf sb u = fb := by
    simpa [freqOf, h_ne] using (h_sameFreqs sb).symm
  simp [cost]
  induction u with
  | htLeaf sym f =>
    simp [freqOf] at h_fa h_fb
    split at h_fa <;> split at h_fb <;> omega
  | htInner l r ihl ihr =>
    rw [cost]
    have h_root : rootFreq l + rootFreq r ≥ fa + fb := by
      simp [freqOf] at h_fa h_fb
      have h_l : rootFreq l ≥ freqOf sa l + freqOf sb l :=
        rootFreq_ge_freqOf_add l sa sb h_ne (by rcases h_cons_u with ⟨hcl, _, _⟩; exact hcl)
      have h_r : rootFreq r ≥ freqOf sa r + freqOf sb r :=
        rootFreq_ge_freqOf_add r sa sb h_ne (by rcases h_cons_u with ⟨_, hcr, _⟩; exact hcr)
      omega
    have h_cost_nonneg : cost l + cost r ≥ 0 := by
      have hl := cost_nonneg l; have hr := cost_nonneg r; omega
    have := add_le_add h_cost_nonneg h_root
    simpa [add_comm, add_left_comm, add_assoc, add_zero] using this
-- swapLeaves is commutative (a↔b = b↔a)
private lemma swapLeaves_comm (a b : ℕ) (t : HuffTree) : swapLeaves a b t = swapLeaves b a t := by
  induction t with
  | htLeaf s f =>
    dsimp [swapLeaves]
    by_cases h1 : s = a
    · rw [h1]
      by_cases h2 : a = b
      · rw [h2]
      · simp [h2]
    · by_cases h2 : s = b
      · rw [h2]; simp [h1, Ne.symm h1]
      · simp [h1, h2]
  | htInner l r ihl ihr =>
    simp [swapLeaves, ihl, ihr]

-- Swap the sibling order: areSiblings a b t → areSiblings b a (swapLeaves a b t)
private lemma areSiblings_swap_siblings {a b : ℕ} {t : HuffTree} (h_sib : areSiblings a b t) (h_ne : a ≠ b) :
    areSiblings b a (swapLeaves a b t) := by
  induction h_sib with
  | here fa fb =>
    simp [swapLeaves, h_ne, h_ne.symm]
    exact areSiblings.here fa fb
  | here' fa fb =>
    simp [swapLeaves, h_ne, h_ne.symm]
    exact areSiblings.here' fa fb
  | inLeft l r h ih => simp [swapLeaves]; exact areSiblings.inLeft _ _ ih
  | inRight l r h ih => simp [swapLeaves]; exact areSiblings.inRight _ _ ih

-- freqOf merge lemma when merge target is one of the siblings (z = a), relaxes hz_fresh
private lemma freqOf_mergePair_same_sibling (t : HuffTree) (b z s : ℕ)
    (h_sib : areSiblings z b t) (h_cons : consistent t) (hz_ne_b : z ≠ b) :
    freqOf s (mergePair z b z (freqOf z t + freqOf b t) t) =
    if s = z then freqOf z t + freqOf b t else if s = b then 0 else freqOf s t := by
  induction h_sib with
  | here fa fb =>
    -- t = htInner (htLeaf z fa) (htLeaf b fb)
    have h_freq_sum : freqOf z (htInner (htLeaf z fa) (htLeaf b fb)) +
                     freqOf b (htInner (htLeaf z fa) (htLeaf b fb)) = fa + fb := by
      simp [freqOf, hz_ne_b, hz_ne_b.symm]
    have h_merge_val : mergePair z b z (fa + fb) (htInner (htLeaf z fa) (htLeaf b fb)) =
                       htLeaf z (fa + fb) := by
      simp [mergePair, hz_ne_b]
    have h_freq_sum : freqOf z (htInner (htLeaf z fa) (htLeaf b fb)) +
                     freqOf b (htInner (htLeaf z fa) (htLeaf b fb)) = fa + fb := by
      simp [freqOf, hz_ne_b, hz_ne_b.symm]
    have h_merge_val : mergePair z b z (freqOf z (htInner (htLeaf z fa) (htLeaf b fb)) +
                                        freqOf b (htInner (htLeaf z fa) (htLeaf b fb)))
                                        (htInner (htLeaf z fa) (htLeaf b fb)) =
                       htLeaf z (fa + fb) := by
      rw [h_freq_sum]; simp [mergePair]
    rw [h_merge_val, freqOf, h_freq_sum]
    by_cases hsz : s = z
    · subst s; simp [hz_ne_b]
    · rw [if_neg (Ne.symm hsz), if_neg hsz]
      by_cases hsb : s = b
      · subst s; simp [hz_ne_b]
      · have h_freq_s : freqOf s (htInner (htLeaf z fa) (htLeaf b fb)) = 0 := by
          simp [freqOf, hsz, hsb, Ne.symm hsz, Ne.symm hsb]
        simp [hsz, hsb, h_freq_s]
  | here' fa fb =>
    have h_freq_sum : freqOf z (htInner (htLeaf b fb) (htLeaf z fa)) +
                     freqOf b (htInner (htLeaf b fb) (htLeaf z fa)) = fa + fb := by
      simp [freqOf, hz_ne_b, hz_ne_b.symm]
    have h_merge_val : mergePair z b z (freqOf z (htInner (htLeaf b fb) (htLeaf z fa)) +
                                        freqOf b (htInner (htLeaf b fb) (htLeaf z fa)))
                                        (htInner (htLeaf b fb) (htLeaf z fa)) =
                       htLeaf z (fa + fb) := by
      rw [h_freq_sum]; simp [mergePair]
    rw [h_merge_val, freqOf, h_freq_sum]
    by_cases hsz : s = z
    · subst s; simp [hz_ne_b]
    · rw [if_neg (Ne.symm hsz), if_neg hsz]
      by_cases hsb : s = b
      · subst s; simp [hz_ne_b]
      · have h_freq_s : freqOf s (htInner (htLeaf b fb) (htLeaf z fa)) = 0 := by
          simp [freqOf, hsz, hsb, Ne.symm hsz, Ne.symm hsb]
        simp [hsz, hsb, h_freq_s]
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨hz_l, hb_l⟩
    have hz_r : z ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hz_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_r : b ∉ alphabet r := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hb_l, hm⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_freq_zr : freqOf z r = 0 := freqOf_eq_zero_of_not_mem _ _ hz_r
    have h_freq_br : freqOf b r = 0 := freqOf_eq_zero_of_not_mem _ _ hb_r
    cases l with
    | htLeaf _ _ => exfalso; cases h_sib_l
    | htInner ll lr =>
      -- t = htInner (htInner ll lr) r; freqOf z r = freqOf b r = 0, so sum reduces to l's sum
      have h_freq_sum : freqOf z (htInner (htInner ll lr) r) + freqOf b (htInner (htInner ll lr) r) =
                       freqOf z (htInner ll lr) + freqOf b (htInner ll lr) := by
        simp [freqOf, h_freq_zr, h_freq_br]
      rw [h_freq_sum]
      have h_merge_r : mergePair z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr)) r = r :=
        mergePair_eq_self_of_not_mem z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr)) r hz_r hb_r
      have h_freq_l := ih hcl
      have h_mp : mergePair z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr))
                                 (htInner (htInner ll lr) r) =
                 htInner (mergePair z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr)) (htInner ll lr))
                        (mergePair z b z (freqOf z (htInner ll lr) + freqOf b (htInner ll lr)) r) := by
        delta mergePair; simp
      rw [h_mp, h_merge_r]
      conv => lhs; rw [freqOf]
      rw [h_freq_l]
      by_cases hsz : s = z
      · subst s; simp [h_freq_zr]
      · by_cases hsb : s = b
        · subst s; simp [h_freq_br]
        · simp [hsz, hsb, freqOf]
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨hz_r, hb_r⟩
    have hz_l : z ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hz_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have hb_l : b ∉ alphabet l := by
      intro hm; have hm_inter := Finset.mem_inter.mpr ⟨hm, hb_r⟩
      rw [h_disjoint] at hm_inter; simp at hm_inter
    have h_freq_zl : freqOf z l = 0 := freqOf_eq_zero_of_not_mem _ _ hz_l
    have h_freq_bl : freqOf b l = 0 := freqOf_eq_zero_of_not_mem _ _ hb_l
    cases r with
    | htLeaf _ _ => exfalso; cases h_sib_r
    | htInner rl rr =>
      have h_freq_sum : freqOf z (htInner l (htInner rl rr)) + freqOf b (htInner l (htInner rl rr)) =
                       freqOf z (htInner rl rr) + freqOf b (htInner rl rr) := by
        simp [freqOf, h_freq_zl, h_freq_bl]
      rw [h_freq_sum]
      have h_merge_l : mergePair z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr)) l = l :=
        mergePair_eq_self_of_not_mem z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr)) l hz_l hb_l
      have h_freq_r := ih hcr
      have h_mp : mergePair z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr))
                                 (htInner l (htInner rl rr)) =
                 htInner (mergePair z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr)) l)
                        (mergePair z b z (freqOf z (htInner rl rr) + freqOf b (htInner rl rr)) (htInner rl rr)) := by
        delta mergePair; simp
      rw [h_mp, h_merge_l]
      conv => lhs; rw [freqOf]
      rw [h_freq_r]
      by_cases hsz : s = z
      · subst s; simp [h_freq_zl]
      · by_cases hsb : s = b
        · subst s; simp [h_freq_bl]
        · simp [hsz, hsb, freqOf]

-- NEW: consistent merge when merge target is one of the siblings (z = a)
-- Relaxes hz_fresh from consistent_mergePair_of_areSiblings
private lemma consistent_mergePair_same_sibling (t : HuffTree) (b z fz : ℕ)
    (h_sib : areSiblings z b t) (h_cons : consistent t) (hz_ne_b : z ≠ b) :
    consistent (mergePair z b z fz t) := by
  induction h_sib with
  | here fa fb => simp [mergePair, consistent]
  | here' fa fb => simp [mergePair, consistent]
  | inLeft l r h_sib_l ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_l with ⟨hz_l, hb_l⟩
    -- z is in l (as sibling), so z ∉ r by consistency
    have hz_not_r : z ∉ alphabet r := by
      intro hzr; have hi := Finset.mem_inter.mpr ⟨hz_l, hzr⟩
      rw [h_empty] at hi; simp at hi
    have hb_not_r : b ∉ alphabet r := by
      intro hbr; have hi := Finset.mem_inter.mpr ⟨hb_l, hbr⟩
      rw [h_empty] at hi; simp at hi
    have h_merge_r : mergePair z b z fz r = r :=
      mergePair_eq_self_of_not_mem z b z fz r hz_not_r hb_not_r
    have h_l : consistent (mergePair z b z fz l) := ih hcl
    have h_disjoint_merge : Disjoint (alphabet (mergePair z b z fz l)) (alphabet r) := by
      have h_sub : alphabet (mergePair z b z fz l) ⊆ alphabet l ∪ {z} :=
        alphabet_mergePair_subset z b z fz l
      have h_disj_sup : Disjoint (alphabet l ∪ {z}) (alphabet r) := by
        rw [Finset.disjoint_union_left]
        exact ⟨hd, by rw [Finset.disjoint_singleton_left]; exact hz_not_r⟩
      exact Finset.disjoint_of_subset_left h_sub h_disj_sup
    cases l with
    | htLeaf s f => exfalso; cases h_sib_l
    | htInner ll lr =>
      simp [mergePair, h_merge_r, consistent]
      exact ⟨h_l, hcr, h_disjoint_merge⟩
  | inRight l r h_sib_r ih =>
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
    rcases areSiblings_mem_alphabet h_sib_r with ⟨hz_r, hb_r⟩
    have hz_not_l : z ∉ alphabet l := by
      intro hzl; have hi := Finset.mem_inter.mpr ⟨hzl, hz_r⟩
      rw [h_empty] at hi; simp at hi
    have hb_not_l : b ∉ alphabet l := by
      intro hbl; have hi := Finset.mem_inter.mpr ⟨hbl, hb_r⟩
      rw [h_empty] at hi; simp at hi
    have h_merge_l : mergePair z b z fz l = l :=
      mergePair_eq_self_of_not_mem z b z fz l hz_not_l hb_not_l
    have h_r : consistent (mergePair z b z fz r) := ih hcr
    have h_disjoint_merge : Disjoint (alphabet l) (alphabet (mergePair z b z fz r)) := by
      have h_sub : alphabet (mergePair z b z fz r) ⊆ alphabet r ∪ {z} :=
        alphabet_mergePair_subset z b z fz r
      have h_disj_sup : Disjoint (alphabet l) (alphabet r ∪ {z}) := by
        rw [Finset.disjoint_union_right]
        exact ⟨hd, by rw [Finset.disjoint_singleton_right]; exact hz_not_l⟩
      exact Finset.disjoint_of_subset_right h_sub h_disj_sup
    cases r with
    | htLeaf s f => exfalso; cases h_sib_r
    | htInner rl rr =>
      simp [mergePair, h_merge_l, consistent]
      exact ⟨hcl, h_r, h_disjoint_merge⟩

-- Isabelle-style splitLeaf: keep z as left child, add b as right child
private lemma mem_alphabet_splitLeaf_of_ne (t : HuffTree) (z b fa fb x : ℕ) (hx_ne_z : x ≠ z) (hx_ne_b : x ≠ b) :
    x ∈ alphabet (splitLeaf t z z b fa fb) → x ∈ alphabet t := by
  induction t with
  | htLeaf sym f =>
    by_cases hz : sym = z
    · subst hz; simp [splitLeaf, alphabet, hx_ne_z, hx_ne_b]
    · simp [splitLeaf, alphabet, hz]
  | htInner l r ihl ihr =>
    simp [splitLeaf, alphabet, Finset.mem_union]
    intro h
    rcases h with (h | h)
    · exact Or.inl (ihl h)
    · exact Or.inr (ihr h)

private lemma freqOf_splitLeaf_of_ne (t : HuffTree) (z b fa fb x : ℕ) (hx_ne_z : x ≠ z) (hx_ne_b : x ≠ b) :
    freqOf x (splitLeaf t z z b fa fb) = freqOf x t := by
  induction t with
  | htLeaf sym f =>
    by_cases hz : sym = z
    · subst hz; simp [splitLeaf, freqOf, hx_ne_z, hx_ne_b, Ne.symm hx_ne_z, Ne.symm hx_ne_b]
    · simp [splitLeaf, freqOf, hz]
  | htInner l r ihl ihr =>
    simp [splitLeaf, freqOf, ihl, ihr]

private lemma freqOf_splitLeaf_left (t : HuffTree) (z b fa fb : ℕ) (h_cons : consistent t)
    (hz_in : z ∈ alphabet t) (hb_not : b ∉ alphabet t) (hz_ne_b : z ≠ b) :
    freqOf z (splitLeaf t z z b fa fb) = fa := by
  revert h_cons hz_in hb_not hz_ne_b
  induction t with
  | htLeaf sym f =>
    intro h_cons hz_in hb_not hz_ne_b
    have hz_sym : z = sym := by simpa [alphabet] using hz_in
    subst hz_sym
    simp [splitLeaf, freqOf, hz_ne_b, hz_ne_b.symm, add_zero]
  | htInner l r ihl ihr =>
    intro h_cons hz_in hb_not hz_ne_b
    rcases h_cons with ⟨hcl, hcr, hd⟩
    simp [splitLeaf, freqOf]
    have hz_union : z ∈ alphabet l ∨ z ∈ alphabet r := by simpa [alphabet] using hz_in
    rcases hz_union with (hz_l | hz_r)
    · have hz_not_r : z ∉ alphabet r := by
        intro hzr; have hi := Finset.mem_inter.mpr ⟨hz_l, hzr⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      rw [splitLeaf_eq_of_z_not_mem r z z b fa fb hz_not_r]
      have hz_freq_r : freqOf z r = 0 := freqOf_eq_zero_of_not_mem z r hz_not_r
      rw [hz_freq_r, add_zero]
      apply ihl hcl hz_l (by intro h; apply hb_not; simp [alphabet, h]) hz_ne_b
    · have hz_not_l : z ∉ alphabet l := by
        intro hzl; have hi := Finset.mem_inter.mpr ⟨hzl, hz_r⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      rw [splitLeaf_eq_of_z_not_mem l z z b fa fb hz_not_l]
      have hz_freq_l : freqOf z l = 0 := freqOf_eq_zero_of_not_mem z l hz_not_l
      rw [hz_freq_l, zero_add]
      apply ihr hcr hz_r (by intro h; apply hb_not; simp [alphabet, h]) hz_ne_b

private lemma freqOf_splitLeaf_right (t : HuffTree) (z b fa fb : ℕ) (h_cons : consistent t)
    (hz_in : z ∈ alphabet t) (hb_not : b ∉ alphabet t) (hz_ne_b : z ≠ b) :
    freqOf b (splitLeaf t z z b fa fb) = fb := by
  revert h_cons hz_in hb_not hz_ne_b
  induction t with
  | htLeaf sym f =>
    intro h_cons hz_in hb_not hz_ne_b
    have hz_sym : z = sym := by simpa [alphabet] using hz_in
    subst hz_sym
    simp [splitLeaf, freqOf, hz_ne_b, hz_ne_b.symm, add_zero]
  | htInner l r ihl ihr =>
    intro h_cons hz_in hb_not hz_ne_b
    rcases h_cons with ⟨hcl, hcr, hd⟩
    simp [splitLeaf, freqOf]
    have hz_union : z ∈ alphabet l ∨ z ∈ alphabet r := by simpa [alphabet] using hz_in
    rcases hz_union with (hz_l | hz_r)
    · have hz_not_r : z ∉ alphabet r := by
        intro hzr; have hi := Finset.mem_inter.mpr ⟨hz_l, hzr⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      rw [splitLeaf_eq_of_z_not_mem r z z b fa fb hz_not_r]
      have hb_freq_r : freqOf b r = 0 := freqOf_eq_zero_of_not_mem b r (by intro h; apply hb_not; simp [alphabet, h])
      rw [hb_freq_r, add_zero]
      apply ihl hcl hz_l (by intro h; apply hb_not; simp [alphabet, h]) hz_ne_b
    · have hz_not_l : z ∉ alphabet l := by
        intro hzl; have hi := Finset.mem_inter.mpr ⟨hzl, hz_r⟩
        rw [Finset.disjoint_iff_inter_eq_empty.mp hd] at hi; simp at hi
      rw [splitLeaf_eq_of_z_not_mem l z z b fa fb hz_not_l]
      have hb_freq_l : freqOf b l = 0 := freqOf_eq_zero_of_not_mem b l (by intro h; apply hb_not; simp [alphabet, h])
      rw [hb_freq_l, zero_add]
      apply ihr hcr hz_r (by intro h; apply hb_not; simp [alphabet, h]) hz_ne_b

private lemma consistent_splitLeaf_v2 (t : HuffTree) (z b fa fb : ℕ) (h_cons : consistent t)
    (hz_in : z ∈ alphabet t) (hb_not : b ∉ alphabet t) (hz_ne_b : z ≠ b) :
    consistent (splitLeaf t z z b fa fb) := by
  revert h_cons hz_in hb_not hz_ne_b
  induction t with
  | htLeaf sym f =>
    intro h_cons hz_in hb_not hz_ne_b
    by_cases hz : sym = z
    · subst hz; simp [splitLeaf, consistent, alphabet, hz_ne_b]
    · simp [splitLeaf, consistent, hz]
  | htInner l r ihl ihr =>
    intro h_cons hz_in hb_not hz_ne_b
    rcases h_cons with ⟨hcl, hcr, hd⟩
    have h_empty := Finset.disjoint_iff_inter_eq_empty.mp hd
    have hb_not_l : b ∉ alphabet l := by intro h; apply hb_not; simp [alphabet, h]
    have hb_not_r : b ∉ alphabet r := by intro h; apply hb_not; simp [alphabet, h]
    have hz_union : z ∈ alphabet l ∨ z ∈ alphabet r := by
      simpa [alphabet] using hz_in
    rcases hz_union with (hz_l | hz_r)
    · have hz_not_r : z ∉ alphabet r := by
        intro hzr; have hi := Finset.mem_inter.mpr ⟨hz_l, hzr⟩
        rw [h_empty] at hi; simp at hi
      have h_split_r : splitLeaf r z z b fa fb = r :=
        splitLeaf_eq_of_z_not_mem r z z b fa fb hz_not_r
      rw [splitLeaf, consistent, h_split_r]
      have h_l := ihl hcl hz_l hb_not_l hz_ne_b
      have h_disjoint : Disjoint (alphabet (splitLeaf l z z b fa fb)) (alphabet r) := by
        rw [Finset.disjoint_iff_inter_eq_empty]
        by_contra h_ne
        have h_nonempty := Finset.nonempty_iff_ne_empty.mpr h_ne
        rcases h_nonempty with ⟨s, hs⟩
        rcases Finset.mem_inter.mp hs with ⟨hs_lsplit, hs_r⟩
        by_cases hsb : s = b
        · subst s; apply hb_not; simp [alphabet, hs_r]
        · by_cases hsz : s = z
          · subst s; exact hz_not_r hs_r
          · have hs_l : s ∈ alphabet l :=
              mem_alphabet_splitLeaf_of_ne l z b fa fb s hsz hsb hs_lsplit
            have hi := Finset.mem_inter.mpr ⟨hs_l, hs_r⟩
            rw [h_empty] at hi; simp at hi
      exact And.intro h_l (And.intro hcr h_disjoint)
    · have hz_not_l : z ∉ alphabet l := by
        intro hzl; have hi := Finset.mem_inter.mpr ⟨hzl, hz_r⟩
        rw [h_empty] at hi; simp at hi
      have h_split_l : splitLeaf l z z b fa fb = l :=
        splitLeaf_eq_of_z_not_mem l z z b fa fb hz_not_l
      rw [splitLeaf, consistent, h_split_l]
      have h_r := ihr hcr hz_r hb_not_r hz_ne_b
      have h_disjoint : Disjoint (alphabet l) (alphabet (splitLeaf r z z b fa fb)) := by
        rw [Finset.disjoint_iff_inter_eq_empty]
        by_contra h_ne
        have h_nonempty := Finset.nonempty_iff_ne_empty.mpr h_ne
        rcases h_nonempty with ⟨s, hs⟩
        rcases Finset.mem_inter.mp hs with ⟨hs_l, hs_rsplit⟩
        by_cases hsb : s = b
        · subst s; apply hb_not; simp [alphabet, hs_l]
        · by_cases hsz : s = z
          · subst s; exact hz_not_l hs_l
          · have hs_r : s ∈ alphabet r :=
              mem_alphabet_splitLeaf_of_ne r z b fa fb s hsz hsb hs_rsplit
            have hi := Finset.mem_inter.mpr ⟨hs_l, hs_r⟩
            rw [h_empty] at hi; simp at hi
      exact And.intro hcl (And.intro h_r h_disjoint)

theorem optimum_splitLeaf (t : HuffTree) (z b fa fb : ℕ)
    (h_opt : optimum t) (h_z_in : z ∈ alphabet t)
    (hb_not_mem : b ∉ alphabet t) (hz_ne_b : z ≠ b)
    (h_fa_pos : fa > 0) (h_fb_pos : fb > 0) (h_fa_le_fb : fa ≤ fb)
    (h_fa_min : ∀ s ∈ alphabet t, fa ≤ freqOf s t)
    (h_fb_min : ∀ s ∈ alphabet t, s ≠ z → fb ≤ freqOf s t)
    (h_sum : freqOf z t = fa + fb) :
    optimum (splitLeaf t z z b fa fb) := by
  rcases h_opt with ⟨h_cons_t, h_pos_t, h_opt_t⟩
  have hb_fb_t : freqOf b t = 0 := freqOf_eq_zero_of_not_mem b t hb_not_mem
  -- Part 1: consistency
  have h_cons_split : consistent (splitLeaf t z z b fa fb) :=
    consistent_splitLeaf_v2 t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b
  -- Part 2: positivity
  have h_pos_split : ∀ s ∈ alphabet (splitLeaf t z z b fa fb), freqOf s (splitLeaf t z z b fa fb) > 0 := by
    intro s hs
    by_cases hsz : s = z
    · subst s; rw [freqOf_splitLeaf_left t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b]; exact h_fa_pos
    · by_cases hsb : s = b
      · subst s; rw [freqOf_splitLeaf_right t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b]; exact h_fb_pos
      · rw [freqOf_splitLeaf_of_ne t z b fa fb s hsz hsb]
        have hs_t : s ∈ alphabet t := mem_alphabet_splitLeaf_of_ne t z b fa fb s hsz hsb hs
        exact h_pos_t s hs_t
  refine ⟨h_cons_split, h_pos_split, ?_⟩
  intro u h_cons_u h_sameFreqs
  -- Strong induction on cost u for pruning zero-frequency symbols
  have h_cost_split_eq : cost (splitLeaf t z z b fa fb) = cost t + fa + fb :=
    cost_splitLeaf_eq t z z b fa fb h_cons_t h_z_in h_sum
  rw [h_cost_split_eq]
  let P (n : ℕ) : Prop := ∀ (v : HuffTree), nodeCount v = n → consistent v →
    sameFreqs (splitLeaf t z z b fa fb) v → cost t + fa + fb ≤ cost v
  have hP : ∀ n, (∀ m < n, P m) → P n := by
    intro n IH v hn h_cons_v h_sameFreqs_v
    have hz_fa_v : freqOf z v = fa := by
      rw [← h_sameFreqs_v z]
      exact freqOf_splitLeaf_left t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b
    have hb_fb_v : freqOf b v = fb := by
      rw [← h_sameFreqs_v b]
      exact freqOf_splitLeaf_right t z b fa fb h_cons_t h_z_in hb_not_mem hz_ne_b
    have hz_in_v : z ∈ alphabet v := by
      by_contra! h_not; have h_zero := freqOf_eq_zero_of_not_mem z v h_not
      rw [hz_fa_v] at h_zero; omega
    have hb_in_v : b ∈ alphabet v := by
      by_contra! h_not; have h_zero := freqOf_eq_zero_of_not_mem b v h_not
      rw [hb_fb_v] at h_zero; omega
    have h_height : height v ≥ 1 := by
      by_contra! h_lt
      have h_le : height v = 0 := by omega
      induction v with
      | htLeaf s f =>
        have h_alph : alphabet (htLeaf s f) = {s} := by simp [alphabet]
        rw [h_alph] at hz_in_v hb_in_v
        simp at hz_in_v hb_in_v; subst hz_in_v hb_in_v; exact hz_ne_b rfl
      | htInner l r => simp [height] at h_le
    have h_dsp_sib : areSiblings (deepestSiblingPair v).1 (deepestSiblingPair v).2 v :=
      deepestSiblingPair_areSiblings v h_cons_v h_height
    set x := (deepestSiblingPair v).1 with hx_def
    set y := (deepestSiblingPair v).2 with hy_def
    have h_dsp_sib_xy : areSiblings x y v := by simpa [hx_def, hy_def] using h_dsp_sib
    have hx_in : x ∈ alphabet v := by simpa [hx_def] using deepestSiblingPair_mem1 v
    have hy_in : y ∈ alphabet v := by simpa [hy_def] using deepestSiblingPair_mem2 v
    have h_depth_pair := deepestSiblingPair_depth v h_cons_v
    rcases h_depth_pair with ⟨h_depth_x_raw, h_depth_y_raw⟩
    have h_depth_x : (depthOf x v).getD 0 = height v := by simpa [hx_def] using h_depth_x_raw
    have h_depth_y : (depthOf y v).getD 0 = height v := by simpa [hy_def] using h_depth_y_raw
    have h_depth_z_le_dx : (depthOf z v).getD 0 ≤ (depthOf x v).getD 0 := by
      rw [h_depth_x]; exact depthOf_getD_le_height v z
    have h_depth_b_le_dy : (depthOf b v).getD 0 ≤ (depthOf y v).getD 0 := by
      rw [h_depth_y]; exact depthOf_getD_le_height v b
    have h_depth_z_le_dy : (depthOf z v).getD 0 ≤ (depthOf y v).getD 0 := by
      rw [h_depth_y]; exact depthOf_getD_le_height v z
    have h_depth_b_le_dx : (depthOf b v).getD 0 ≤ (depthOf x v).getD 0 := by
      rw [h_depth_x]; exact depthOf_getD_le_height v b
    -- Merge helper
    have h_merge_conclude (v' : HuffTree) (h_sib_zb : areSiblings z b v') (h_cons_v' : consistent v')
        (h_fz_v' : freqOf z v' = fa) (h_fb_v' : freqOf b v' = fb)
        (h_freq_rel : ∀ s, freqOf s v' = freqOf s (splitLeaf t z z b fa fb))
        (h_cost_v'_le : (cost v' : ℤ) ≤ (cost v : ℤ)) : cost t + fa + fb ≤ cost v := by
      let v'' := mergePair z b z (fa + fb) v'
      have h_cost_v'' : (cost v'' : ℤ) = (cost v' : ℤ) - (fa : ℤ) - (fb : ℤ) :=
        cost_mergePair_of_areSiblings v' z b z fa fb h_sib_zb h_cons_v' hz_ne_b h_fz_v' h_fb_v' rfl
      have h_cons_v'' : consistent v'' :=
        consistent_mergePair_same_sibling v' b z (fa + fb) h_sib_zb h_cons_v' hz_ne_b
      have h_sameFreqs_v'' : sameFreqs t v'' := by
        intro s
        dsimp [v'']
        have h_freq_sum : freqOf z v' + freqOf b v' = fa + fb := by rw [h_fz_v', h_fb_v']
        have h_lemma := freqOf_mergePair_same_sibling v' b z s h_sib_zb h_cons_v' hz_ne_b
        have h_merge_eq : freqOf s (mergePair z b z (fa + fb) v') =
                          freqOf s (mergePair z b z (freqOf z v' + freqOf b v') v') := by
          rw [← h_freq_sum]
        rw [h_merge_eq, h_lemma]
        split_ifs with hsz hsb
        · rw [hsz, h_fz_v', h_fb_v', h_sum]
        · rw [hsb, hb_fb_t]
        · rw [h_freq_rel s, freqOf_splitLeaf_of_ne t z b fa fb s hsz hsb]
      have h_cost_t_le_v'' : cost t ≤ cost v'' := h_opt_t v'' h_cons_v'' h_sameFreqs_v''
      have h_t_le : (cost t : ℤ) ≤ (cost v'' : ℤ) := by exact_mod_cast h_cost_t_le_v''
      have h_goal_ℤ : (cost t : ℤ) + (fa : ℤ) + (fb : ℤ) ≤ (cost v : ℤ) := by linarith
      exact_mod_cast h_goal_ℤ
    -- Case analysis on x, y relative to z, b
    by_cases hxz : x = z
    · -- x=z case
      rw [hxz] at h_dsp_sib_xy hx_in h_depth_x h_depth_z_le_dx h_depth_b_le_dx
      by_cases hyb : y = b
      · rw [hyb] at h_dsp_sib_xy
        have h_freq_rel_v : ∀ s, freqOf s v = freqOf s (splitLeaf t z z b fa fb) :=
          fun s => (h_sameFreqs_v s).symm
        exact h_merge_conclude v h_dsp_sib_xy h_cons_v hz_fa_v hb_fb_v h_freq_rel_v (le_refl _)
      · have hb_ne_y : b ≠ y := Ne.symm hyb
        have hx_ne_y : z ≠ y := areSiblings_ne v z y h_cons_v h_dsp_sib_xy
        by_cases hy_in_t : y ∈ alphabet t
        · -- Standard: swap b↔y
          have h_freq_b_y : freqOf b v ≤ freqOf y v := by
            rw [hb_fb_v]
            have hy_freq_v : freqOf y v = freqOf y (splitLeaf t z z b fa fb) := (h_sameFreqs_v y).symm
            have hy_ne_z : y ≠ z := Ne.symm hx_ne_y
            have hy_freq_t : freqOf y (splitLeaf t z z b fa fb) = freqOf y t :=
              freqOf_splitLeaf_of_ne t z b fa fb y hy_ne_z hyb
            rw [hy_freq_v, hy_freq_t]
            exact h_fb_min y hy_in_t hy_ne_z
          let v1 := swapFreqs b y (swapLeaves b y v)
          have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
            cost_exchangeLeaf_le v b y h_cons_v hb_in_v hy_in hb_ne_y h_freq_b_y h_depth_b_le_dy
          have h_sib_zb_swap : areSiblings z b (swapLeaves b y v) :=
            areSiblings_exchangeRight v z b y h_dsp_sib_xy (Ne.symm hz_ne_b) hb_ne_y hx_ne_y
          have h_sib_zb_v1 : areSiblings z b v1 :=
            areSiblings_swapFreqs_preserved (swapLeaves b y v) z b b y h_sib_zb_swap
          have h_cons_v1 : consistent v1 := by
            dsimp [v1, swapFreqs]
            apply consistent_replaceFreq y _ (replaceFreq b _ (swapLeaves b y v))
            apply consistent_replaceFreq b _ (swapLeaves b y v)
            exact consistent_swapLeaves b y v h_cons_v
          have h_freq_rel_v1 : ∀ s, freqOf s v1 = freqOf s (splitLeaf t z z b fa fb) := by
            intro s
            have h_ex : freqOf s (swapFreqs b y (swapLeaves b y v)) = freqOf s v :=
              freqOf_exchangeLeaf v b y s hb_ne_y hb_in_v hy_in h_cons_v
            dsimp [v1]; rw [h_ex]; exact (h_sameFreqs_v s).symm
          have h_fz_v1 : freqOf z v1 = fa := by
            dsimp [v1]; rw [freqOf_exchangeLeaf v b y z hb_ne_y hb_in_v hy_in h_cons_v, hz_fa_v]
          have h_fb_v1 : freqOf b v1 = fb := by
            dsimp [v1]; rw [freqOf_exchangeLeaf v b y b hb_ne_y hb_in_v hy_in h_cons_v, hb_fb_v]
          exact h_merge_conclude v1 h_sib_zb_v1 h_cons_v1 h_fz_v1 h_fb_v1 h_freq_rel_v1 h_cost_v1
        · -- Edge: y ∉ alphabet t, prune z,y and use IH
          have h_freq_y_t : freqOf y t = 0 := freqOf_eq_zero_of_not_mem y t hy_in_t
          have h_freq_y_v : freqOf y v = 0 := by
            rw [(h_sameFreqs_v y).symm, freqOf_splitLeaf_of_ne t z b fa fb y (Ne.symm hx_ne_y) hyb, h_freq_y_t]
          let v_pruned := mergePair z y z (freqOf z v + freqOf y v) v
          have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
            have h_ne : z ≠ y := hx_ne_y
            have h_lt : nodeCount v_pruned < nodeCount v :=
              nodeCount_mergePair_lt_of_areSiblings v z y z (freqOf z v + freqOf y v) h_dsp_sib_xy h_ne
            omega
          have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
            have h_cost_int : (cost v_pruned : ℤ) = (cost v : ℤ) - (fa : ℤ) := by
              have h := cost_mergePair_of_areSiblings v z y z fa 0 h_dsp_sib_xy h_cons_v hx_ne_y
                hz_fa_v h_freq_y_v (by ring)
              simpa [v_pruned, hz_fa_v, h_freq_y_v, add_zero] using h
            have h_fa_pos_int : (0 : ℤ) < fa := by exact_mod_cast h_fa_pos
            omega
          have h_cons_pruned : consistent v_pruned :=
            consistent_mergePair_same_sibling v y z (freqOf z v + freqOf y v) h_dsp_sib_xy h_cons_v hx_ne_y
          have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
            intro s
            have h_freq_pruned : freqOf s v_pruned = freqOf s v := by
              dsimp [v_pruned]
              rw [freqOf_mergePair_same_sibling v y z s h_dsp_sib_xy h_cons_v hx_ne_y, hz_fa_v, h_freq_y_v]
              by_cases hsz : s = z
              · subst s; simp [hz_fa_v, h_freq_y_v]
              · by_cases hsy : s = y
                · subst s; simp [hsz, h_freq_y_v]
                · simp [hsz, hsy, hz_fa_v, h_freq_y_v]
            rw [h_freq_pruned, h_sameFreqs_v s]
          have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
          have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
            h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
          omega
    · by_cases hxb : x = b
      · -- x=b case: areSiblings b y v
        rw [hxb] at h_dsp_sib_xy hx_in h_depth_x h_depth_z_le_dx h_depth_b_le_dx
        have hb_ne_y : b ≠ y := areSiblings_ne v b y h_cons_v h_dsp_sib_xy
        by_cases hyz : y = z
        · -- areSiblings b z v, swap b↔z to get z,b order
          rw [hyz] at h_dsp_sib_xy
          -- h_dsp_sib_xy : areSiblings b z v
          let v1 := swapFreqs z b (swapLeaves z b v)
          have h_sib_v1 : areSiblings z b v1 := by
            dsimp [v1]
            have h := areSiblings_swap_siblings h_dsp_sib_xy (Ne.symm hz_ne_b)
            -- h : areSiblings z b (swapLeaves b z v)
            rw [swapLeaves_comm b z v] at h
            exact areSiblings_swapFreqs_preserved (swapLeaves z b v) z b z b h
          have h_cons_v1 : consistent v1 := by
            dsimp [v1, swapFreqs]
            apply consistent_replaceFreq b _ (replaceFreq z _ (swapLeaves z b v))
            apply consistent_replaceFreq z _ (swapLeaves z b v)
            exact consistent_swapLeaves z b v h_cons_v
          have h_fz_le_fb_v : freqOf z v ≤ freqOf b v := by
            rw [hz_fa_v, hb_fb_v]; exact h_fa_le_fb
          have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
            cost_exchangeLeaf_le v z b h_cons_v hz_in_v hb_in_v hz_ne_b h_fz_le_fb_v h_depth_z_le_dx
          have h_freq_rel_v1 : ∀ s, freqOf s v1 = freqOf s (splitLeaf t z z b fa fb) := by
            intro s
            dsimp [v1]
            rw [freqOf_exchangeLeaf v z b s hz_ne_b hz_in_v hb_in_v h_cons_v]
            exact (h_sameFreqs_v s).symm
          have h_fz_v1 : freqOf z v1 = fa := by
            dsimp [v1]; rw [freqOf_exchangeLeaf v z b z hz_ne_b hz_in_v hb_in_v h_cons_v, hz_fa_v]
          have h_fb_v1 : freqOf b v1 = fb := by
            dsimp [v1]; rw [freqOf_exchangeLeaf v z b b hz_ne_b hz_in_v hb_in_v h_cons_v, hb_fb_v]
          exact h_merge_conclude v1 h_sib_v1 h_cons_v1 h_fz_v1 h_fb_v1 h_freq_rel_v1 h_cost_v1
        · -- y ≠ z
          have hz_ne_y : z ≠ y := by intro h_eq; apply hyz; exact h_eq.symm
          have hy_ne_b : y ≠ b := Ne.symm hb_ne_y
          by_cases hy_in_t : y ∈ alphabet t
          · -- Standard case: two swaps. v1 = swap z↔b, v2 = swap b↔y on v1
            let v1 := swapFreqs z b (swapLeaves z b v)
            have h_sib_v1 : areSiblings z y v1 :=
              areSiblings_swapFreqs_preserved (swapLeaves z b v) z y z b
                (areSiblings_exchangeLeft v z b y h_dsp_sib_xy hz_ne_b hz_ne_y hb_ne_y)
            have h_cons_v1 : consistent v1 := by
              dsimp [v1, swapFreqs]
              apply consistent_replaceFreq b _ (replaceFreq z _ (swapLeaves z b v))
              apply consistent_replaceFreq z _ (swapLeaves z b v)
              exact consistent_swapLeaves z b v h_cons_v
            have h_fz_le_fb_v : freqOf z v ≤ freqOf b v := by
              rw [hz_fa_v, hb_fb_v]; exact h_fa_le_fb
            have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
              cost_exchangeLeaf_le v z b h_cons_v hz_in_v hb_in_v hz_ne_b h_fz_le_fb_v h_depth_z_le_dx
            have hy_in_v1 : y ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              exact ⟨y, hy_in, by dsimp [swapSym]; simp [hyz, hy_ne_b]⟩
            have hz_in_v1 : z ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              exact ⟨b, hb_in_v, by dsimp [swapSym]; simp [hz_ne_b]⟩
            have hb_in_v1 : b ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              exact ⟨z, hz_in_v, by dsimp [swapSym]; simp⟩
            -- Depth inequality for second swap: depthOf b v1 ≤ depthOf y v1
            have h_depth_b_y_v1 : (depthOf b v1).getD 0 ≤ (depthOf y v1).getD 0 := by
              have h_dep_b : (depthOf b v1).getD 0 = (depthOf z v).getD 0 := by
                dsimp [v1, swapFreqs]
                rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_at_b z b v hz_ne_b]
              have h_dep_y : (depthOf y v1).getD 0 = (depthOf y v).getD 0 := by
                dsimp [v1, swapFreqs]
                rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_of_not_is z b y v (Ne.symm hz_ne_y) hy_ne_b]
              rw [h_dep_b, h_dep_y, h_depth_y, ← h_depth_x]
              exact h_depth_z_le_dx
            -- Frequency inequality for second swap: freqOf b v1 ≤ freqOf y v1
            have h_freq_b_y_v1 : freqOf b v1 ≤ freqOf y v1 := by
              have h_fb_v1 : freqOf b v1 = fb := by
                dsimp [v1]
                rw [freqOf_exchangeLeaf v z b b hz_ne_b hz_in_v hb_in_v h_cons_v, hb_fb_v]
              have h_fy_v1 : freqOf y v1 = freqOf y v := by
                dsimp [v1]
                rw [freqOf_exchangeLeaf v z b y hz_ne_b hz_in_v hb_in_v h_cons_v]
              rw [h_fb_v1, h_fy_v1]
              have hy_freq_v : freqOf y v = freqOf y (splitLeaf t z z b fa fb) := (h_sameFreqs_v y).symm
              have hy_freq_t : freqOf y (splitLeaf t z z b fa fb) = freqOf y t :=
                freqOf_splitLeaf_of_ne t z b fa fb y (Ne.symm hz_ne_y) hy_ne_b
              rw [hy_freq_v, hy_freq_t]
              exact h_fb_min y hy_in_t (Ne.symm hz_ne_y)
            -- Second swap: b↔y
            let v2 := swapFreqs b y (swapLeaves b y v1)
            have h_sib_v2 : areSiblings z b v2 :=
              areSiblings_swapFreqs_preserved (swapLeaves b y v1) z b b y
                (areSiblings_exchangeRight v1 z b y h_sib_v1 (Ne.symm hz_ne_b) hb_ne_y hz_ne_y)
            have h_cons_v2 : consistent v2 := by
              dsimp [v2, swapFreqs]
              apply consistent_replaceFreq y _ (replaceFreq b _ (swapLeaves b y v1))
              apply consistent_replaceFreq b _ (swapLeaves b y v1)
              exact consistent_swapLeaves b y v1 h_cons_v1
            have h_cost_v2 : (cost v2 : ℤ) ≤ (cost v1 : ℤ) :=
              cost_exchangeLeaf_le v1 b y h_cons_v1 hb_in_v1 hy_in_v1 hb_ne_y h_freq_b_y_v1 h_depth_b_y_v1
            have h_freq_rel_v2 : ∀ s, freqOf s v2 = freqOf s (splitLeaf t z z b fa fb) := by
              intro s
              have h_ex1 : freqOf s v1 = freqOf s v :=
                freqOf_exchangeLeaf v z b s hz_ne_b hz_in_v hb_in_v h_cons_v
              have h_ex2 : freqOf s (swapFreqs b y (swapLeaves b y v1)) = freqOf s v1 :=
                freqOf_exchangeLeaf v1 b y s hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1
              dsimp [v2]; rw [h_ex2, h_ex1]; exact (h_sameFreqs_v s).symm
            have h_fz_v2 : freqOf z v2 = fa := by
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 b y z hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v z b z hz_ne_b hz_in_v hb_in_v h_cons_v, hz_fa_v]
            have h_fb_v2 : freqOf b v2 = fb := by
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 b y b hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v z b b hz_ne_b hz_in_v hb_in_v h_cons_v, hb_fb_v]
            have h_cost_total : (cost v2 : ℤ) ≤ (cost v : ℤ) := by linarith
            exact h_merge_conclude v2 h_sib_v2 h_cons_v2 h_fz_v2 h_fb_v2 h_freq_rel_v2 h_cost_total
          · -- Edge: y ∉ alphabet t, prune b,y and use IH
            have h_freq_y_t : freqOf y t = 0 := freqOf_eq_zero_of_not_mem y t hy_in_t
            have h_freq_y_v : freqOf y v = 0 := by
              rw [(h_sameFreqs_v y).symm, freqOf_splitLeaf_of_ne t z b fa fb y (Ne.symm hz_ne_y) hy_ne_b, h_freq_y_t]
            let v_pruned := mergePair b y b (freqOf b v + freqOf y v) v
            have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
              have h_ne : b ≠ y := hb_ne_y
              have h_lt : nodeCount v_pruned < nodeCount v :=
                nodeCount_mergePair_lt_of_areSiblings v b y b (freqOf b v + freqOf y v) h_dsp_sib_xy h_ne
              omega
            have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
              have h_cost_int : (cost v_pruned : ℤ) = (cost v : ℤ) - (fb : ℤ) := by
                have h := cost_mergePair_of_areSiblings v b y b fb 0 h_dsp_sib_xy h_cons_v hb_ne_y
                  hb_fb_v h_freq_y_v (by ring)
                simpa [v_pruned, hb_fb_v, h_freq_y_v, add_zero] using h
              have h_fb_pos_int : (0 : ℤ) < fb := by exact_mod_cast h_fb_pos
              omega
            have h_cons_pruned : consistent v_pruned :=
              consistent_mergePair_same_sibling v y b (freqOf b v + freqOf y v) h_dsp_sib_xy h_cons_v hb_ne_y
            have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
              intro s
              have h_freq_pruned : freqOf s v_pruned = freqOf s v := by
                dsimp [v_pruned]
                rw [freqOf_mergePair_same_sibling v y b s h_dsp_sib_xy h_cons_v hb_ne_y, hb_fb_v, h_freq_y_v, add_zero]
                by_cases hsb : s = b
                · rw [hsb, if_pos rfl, hb_fb_v]
                · by_cases hsy : s = y
                  · rw [hsy]
                    by_cases hyb : y = b
                    · rw [hyb] at h_freq_y_v; rw [hb_fb_v] at h_freq_y_v; omega
                    · rw [if_neg hyb, if_pos rfl, h_freq_y_v]
                  · rw [if_neg hsb, if_neg hsy]
              rw [h_freq_pruned, h_sameFreqs_v s]
            have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
            have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
              h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
            omega
      · -- x≠z,b case: areSiblings x y v with x∉{z,b}
        have hx_ne_z : x ≠ z := hxz
        have hx_ne_b : x ≠ b := hxb
        have hz_ne_x : z ≠ x := Ne.symm hxz
        have hb_ne_x : b ≠ x := Ne.symm hxb
        have hx_ne_y : x ≠ y := areSiblings_ne v x y h_cons_v h_dsp_sib_xy
        by_cases hyz : y = z
        · -- areSiblings x z v (after rw hyz), swap b↔x to get z,b siblings
          rw [hyz] at h_dsp_sib_xy
          by_cases hx_in_t' : x ∈ alphabet t
          · -- Standard: x ∈ alphabet t, swap b↔x then swap order
            have h_freq_b_x : freqOf b v ≤ freqOf x v := by
              rw [hb_fb_v]
              have hx_freq_v : freqOf x v = freqOf x t := by
                rw [(h_sameFreqs_v x).symm, freqOf_splitLeaf_of_ne t z b fa fb x hx_ne_z hx_ne_b]
              rw [hx_freq_v]
              exact h_fb_min x hx_in_t' hx_ne_z
            have h_depth_b_x : (depthOf b v).getD 0 ≤ (depthOf x v).getD 0 := h_depth_b_le_dx
            -- First swap: b↔x → areSiblings b z (swapLeaves b x v)
            let v1 := swapFreqs b x (swapLeaves b x v)
            have hb_in_v1 : b ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              refine ⟨x, hx_in, ?_⟩
              dsimp [swapSym]; simp [hb_ne_x, hx_ne_b.symm]
            have hz_in_v1 : z ∈ alphabet v1 := by
              dsimp [v1, swapFreqs]
              rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
              apply Finset.mem_image.mpr
              refine ⟨z, hz_in_v, ?_⟩
              dsimp [swapSym]; rw [if_neg hz_ne_b, if_neg (Ne.symm hx_ne_z)]
            have h_sib_v1 : areSiblings b z v1 :=
              areSiblings_swapFreqs_preserved (swapLeaves b x v) b z b x
                (areSiblings_exchangeLeft v b x z h_dsp_sib_xy hb_ne_x (Ne.symm hz_ne_b) hx_ne_z)
            have h_cons_v1 : consistent v1 := by
              dsimp [v1, swapFreqs]
              apply consistent_replaceFreq x _ (replaceFreq b _ (swapLeaves b x v))
              apply consistent_replaceFreq b _ (swapLeaves b x v)
              exact consistent_swapLeaves b x v h_cons_v
            have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
              cost_exchangeLeaf_le v b x h_cons_v hb_in_v hx_in hb_ne_x h_freq_b_x h_depth_b_x
            -- Second swap: z↔b to get z,b order
            let v2 := swapFreqs z b (swapLeaves z b v1)
            have h_sib_v2 : areSiblings z b v2 := by
              dsimp [v2]
              have h := areSiblings_swap_siblings h_sib_v1 (Ne.symm hz_ne_b)
              -- h : areSiblings z b (swapLeaves b z v1)
              rw [swapLeaves_comm b z v1] at h
              exact areSiblings_swapFreqs_preserved (swapLeaves z b v1) z b z b h
            have h_cons_v2 : consistent v2 := by
              dsimp [v2, swapFreqs]
              apply consistent_replaceFreq b _ (replaceFreq z _ (swapLeaves z b v1))
              apply consistent_replaceFreq z _ (swapLeaves z b v1)
              exact consistent_swapLeaves z b v1 h_cons_v1
            have h_cost_v2 : (cost v2 : ℤ) ≤ (cost v1 : ℤ) := by
              have hb_freq_v1 : freqOf b v1 = fb := by
                dsimp [v1]; rw [freqOf_exchangeLeaf v b x b hb_ne_x hb_in_v hx_in h_cons_v, hb_fb_v]
              have hz_freq_v1 : freqOf z v1 = fa := by
                dsimp [v1]; rw [freqOf_exchangeLeaf v b x z hb_ne_x hb_in_v hx_in h_cons_v, hz_fa_v]
              have h_freq_z_b_v1 : freqOf z v1 ≤ freqOf b v1 := by
                rw [hz_freq_v1, hb_freq_v1]; exact h_fa_le_fb
              have h_depth_z_b_v1 : (depthOf z v1).getD 0 ≤ (depthOf b v1).getD 0 := by
                have h_dep_b : (depthOf b v1).getD 0 = (depthOf x v).getD 0 := by
                  dsimp [v1, swapFreqs]
                  rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_at_a b x v hb_ne_x]
                have h_dep_z : (depthOf z v1).getD 0 = (depthOf z v).getD 0 := by
                  dsimp [v1, swapFreqs]
                  rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_of_not_is b x z v hz_ne_b (Ne.symm hx_ne_z)]
                rw [h_dep_z, h_dep_b, h_depth_x]
                exact depthOf_getD_le_height v z
              simpa [v2] using cost_exchangeLeaf_le v1 z b h_cons_v1 hz_in_v1 hb_in_v1 hz_ne_b h_freq_z_b_v1 h_depth_z_b_v1
            have h_freq_rel_v2 : ∀ s, freqOf s v2 = freqOf s (splitLeaf t z z b fa fb) := by
              intro s
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 z b s hz_ne_b hz_in_v1 hb_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v b x s hb_ne_x hb_in_v hx_in h_cons_v]
              exact (h_sameFreqs_v s).symm
            have h_fz_v2 : freqOf z v2 = fa := by
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 z b z hz_ne_b hz_in_v1 hb_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v b x z hb_ne_x hb_in_v hx_in h_cons_v, hz_fa_v]
            have h_fb_v2 : freqOf b v2 = fb := by
              dsimp [v2]
              rw [freqOf_exchangeLeaf v1 z b b hz_ne_b hz_in_v1 hb_in_v1 h_cons_v1]
              dsimp [v1]
              rw [freqOf_exchangeLeaf v b x b hb_ne_x hb_in_v hx_in h_cons_v, hb_fb_v]
            have h_cost_total : (cost v2 : ℤ) ≤ (cost v : ℤ) := by linarith
            exact h_merge_conclude v2 h_sib_v2 h_cons_v2 h_fz_v2 h_fb_v2 h_freq_rel_v2 h_cost_total
          · -- Edge: x ∉ alphabet t, y=z. Both x and z are deepest siblings (same depth).
            -- Swap x↔z (same depth, cost preserved) so z becomes first sibling, then merge into z.
            have h_freq_x_v : freqOf x v = 0 := by
              rw [(h_sameFreqs_v x).symm, freqOf_splitLeaf_of_ne t z b fa fb x hx_ne_z hx_ne_b]
              exact freqOf_eq_zero_of_not_mem x t hx_in_t'
            -- Both x and z are deepest siblings: y=z and y is deepest
            have h_depth_z_eq : (depthOf z v).getD 0 = height v := by
              rw [← hyz]; exact h_depth_y
            have h_depth_x_eq_z : (depthOf x v).getD 0 = (depthOf z v).getD 0 := by
              rw [h_depth_x, h_depth_z_eq]
            have h_depth_x_le_z : (depthOf x v).getD 0 ≤ (depthOf z v).getD 0 := by rw [h_depth_x_eq_z]
            -- Swap x↔z: x (freq 0) into z's position. freq 0 ≤ fa, depth equal → cost non-increasing.
            let v_pre := swapFreqs x z (swapLeaves x z v)
            have h_sib_pre : areSiblings z x v_pre := by
              dsimp [v_pre]
              have h := areSiblings_swap_siblings h_dsp_sib_xy hx_ne_z
              -- h : areSiblings z x (swapLeaves x z v)
              exact areSiblings_swapFreqs_preserved (swapLeaves x z v) z x x z h
            have h_cons_pre : consistent v_pre := by
              dsimp [v_pre, swapFreqs]
              apply consistent_replaceFreq z _ (replaceFreq x _ (swapLeaves x z v))
              apply consistent_replaceFreq x _ (swapLeaves x z v)
              exact consistent_swapLeaves x z v h_cons_v
            have h_cost_pre : (cost v_pre : ℤ) ≤ (cost v : ℤ) :=
              cost_exchangeLeaf_le v x z h_cons_v hx_in hz_in_v hx_ne_z
                (by rw [h_freq_x_v, hz_fa_v]; omega) h_depth_x_le_z
            have h_fz_pre : freqOf z v_pre = fa := by
              dsimp [v_pre]; rw [freqOf_exchangeLeaf v x z z hx_ne_z hx_in hz_in_v h_cons_v, hz_fa_v]
            have h_fx_pre : freqOf x v_pre = 0 := by
              dsimp [v_pre]; rw [freqOf_exchangeLeaf v x z x hx_ne_z hx_in hz_in_v h_cons_v, h_freq_x_v]
            -- Now z is first sibling, merge into z
            let v_pruned := mergePair z x z (freqOf z v_pre + freqOf x v_pre) v_pre
            have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
              have h_ne : z ≠ x := Ne.symm hx_ne_z
              have h_lt : nodeCount v_pruned < nodeCount v_pre :=
                nodeCount_mergePair_lt_of_areSiblings v_pre z x z (freqOf z v_pre + freqOf x v_pre) h_sib_pre h_ne
              have h_eq_pre : nodeCount v_pre = nodeCount v := by
                dsimp [v_pre, swapFreqs]
                rw [nodeCount_replaceFreq_eq, nodeCount_replaceFreq_eq, nodeCount_swapLeaves_eq]
              omega
            have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
              have h_cost_int : (cost v_pruned : ℤ) = (cost v_pre : ℤ) - (fa : ℤ) := by
                have h := cost_mergePair_of_areSiblings v_pre z x z fa 0 (fz := freqOf z v_pre + freqOf x v_pre)
                  h_sib_pre h_cons_pre (Ne.symm hx_ne_z) h_fz_pre h_fx_pre
                  (by rw [h_fz_pre, h_fx_pre, add_zero])
                simpa [v_pruned, add_zero] using h
              have h_fa_pos_int : (0 : ℤ) < fa := by exact_mod_cast h_fa_pos
              have h_cost_pre_le_v : (cost v_pre : ℤ) ≤ (cost v : ℤ) := h_cost_pre
              omega
            have h_cons_pruned : consistent v_pruned :=
              consistent_mergePair_same_sibling v_pre x z (freqOf z v_pre + freqOf x v_pre)
                h_sib_pre h_cons_pre (Ne.symm hx_ne_z)
            have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
              intro s
              have h_freq_pruned : freqOf s v_pruned = freqOf s v_pre := by
                dsimp [v_pruned]
                rw [freqOf_mergePair_same_sibling v_pre x z s h_sib_pre h_cons_pre (Ne.symm hx_ne_z),
                  h_fz_pre, h_fx_pre, add_zero]
                by_cases hsz : s = z
                · rw [hsz, if_pos rfl, h_fz_pre]
                · by_cases hsx : s = x
                  · rw [hsx]
                    by_cases hxz' : x = z; · exfalso; exact hx_ne_z hxz'
                    rw [if_neg hxz', if_pos rfl, h_fx_pre]
                  · rw [if_neg hsz, if_neg hsx]
              rw [h_freq_pruned]
              dsimp [v_pre]
              rw [freqOf_exchangeLeaf v x z s hx_ne_z hx_in hz_in_v h_cons_v]
              exact h_sameFreqs_v s
            have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
            have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
              h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
            omega
        · -- y ≠ z, can do the standard swap z↔x
          have hz_ne_y : z ≠ y := Ne.symm hyz
          have hy_ne_z : y ≠ z := hyz
          by_cases hx_in_t : x ∈ alphabet t
          · -- x ∈ alphabet t, so freqOf x v ≥ fa. Standard exchange approach.
            have h_freq_z_x : freqOf z v ≤ freqOf x v := by
              rw [hz_fa_v]
              have hx_freq_v : freqOf x v = freqOf x t := by
                rw [(h_sameFreqs_v x).symm, freqOf_splitLeaf_of_ne t z b fa fb x hx_ne_z hx_ne_b]
              rw [hx_freq_v]
              exact h_fa_min x hx_in_t
            -- First swap: z↔x to get z as first sibling
            let v1 := swapFreqs z x (swapLeaves z x v)
            have h_sib_v1 : areSiblings z y v1 :=
              areSiblings_swapFreqs_preserved (swapLeaves z x v) z y z x
                (areSiblings_exchangeLeft v z x y h_dsp_sib_xy hz_ne_x hz_ne_y hx_ne_y)
            have h_cons_v1 : consistent v1 := by
              dsimp [v1, swapFreqs]
              apply consistent_replaceFreq x _ (replaceFreq z _ (swapLeaves z x v))
              apply consistent_replaceFreq z _ (swapLeaves z x v)
              exact consistent_swapLeaves z x v h_cons_v
            have h_cost_v1 : (cost v1 : ℤ) ≤ (cost v : ℤ) :=
              cost_exchangeLeaf_le v z x h_cons_v hz_in_v hx_in hz_ne_x h_freq_z_x h_depth_z_le_dx
            -- Now areSiblings z y v1. Same situation as x=z case.
            by_cases hyb : y = b
            · -- z,b already siblings in v1
              rw [hyb] at h_sib_v1
              have h_freq_rel_v1 : ∀ s, freqOf s v1 = freqOf s (splitLeaf t z z b fa fb) := by
                intro s
                dsimp [v1]
                rw [freqOf_exchangeLeaf v z x s hz_ne_x hz_in_v hx_in h_cons_v]
                exact (h_sameFreqs_v s).symm
              have h_fz_v1 : freqOf z v1 = fa := by
                dsimp [v1]; rw [freqOf_exchangeLeaf v z x z hz_ne_x hz_in_v hx_in h_cons_v, hz_fa_v]
              have h_fb_v1 : freqOf b v1 = fb := by
                dsimp [v1]; rw [freqOf_exchangeLeaf v z x b hz_ne_x hz_in_v hx_in h_cons_v, hb_fb_v]
              exact h_merge_conclude v1 h_sib_v1 h_cons_v1 h_fz_v1 h_fb_v1 h_freq_rel_v1 h_cost_v1
            · -- y ≠ b, need second swap b↔y or pruning
              have hb_ne_y : b ≠ y := Ne.symm hyb
              have hy_ne_x : y ≠ x := Ne.symm hx_ne_y
              by_cases hy_in_t : y ∈ alphabet t
              · -- Standard: second swap b↔y on v1
                have hz_in_v1 : z ∈ alphabet v1 := by
                  dsimp [v1, swapFreqs]
                  rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
                  apply Finset.mem_image.mpr
                  exact ⟨x, hx_in, by dsimp [swapSym]; simp [hz_ne_x]⟩
                have hy_in_v1 : y ∈ alphabet v1 := by
                  dsimp [v1, swapFreqs]
                  rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
                  apply Finset.mem_image.mpr
                  exact ⟨y, hy_in, by dsimp [swapSym]; simp [hy_ne_z, hy_ne_x]⟩
                have hb_in_v1 : b ∈ alphabet v1 := by
                  dsimp [v1, swapFreqs]
                  rw [alphabet_replaceFreq, alphabet_replaceFreq, alphabet_swapLeaves_eq_image]
                  apply Finset.mem_image.mpr
                  refine ⟨b, hb_in_v, ?_⟩
                  dsimp [swapSym]
                  simp [Ne.symm hz_ne_b, hb_ne_x]
                -- depth inequality for second swap
                have h_depth_b_y_v1 : (depthOf b v1).getD 0 ≤ (depthOf y v1).getD 0 := by
                  have h_dep_b : (depthOf b v1).getD 0 = (depthOf b v).getD 0 := by
                    dsimp [v1, swapFreqs]
                    rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_of_not_is z x b v (Ne.symm hz_ne_b) hb_ne_x]
                  have h_dep_y : (depthOf y v1).getD 0 = (depthOf y v).getD 0 := by
                    dsimp [v1, swapFreqs]
                    rw [depthOf_replaceFreq_eq, depthOf_replaceFreq_eq, depthOf_swapLeaves_of_not_is z x y v hy_ne_z hy_ne_x]
                  rw [h_dep_b, h_dep_y, h_depth_y, ← h_depth_x]
                  exact h_depth_b_le_dx
                -- frequency inequality for second swap
                have h_freq_b_y_v1 : freqOf b v1 ≤ freqOf y v1 := by
                  have h_fb_v1 : freqOf b v1 = fb := by
                    dsimp [v1]; rw [freqOf_exchangeLeaf v z x b hz_ne_x hz_in_v hx_in h_cons_v, hb_fb_v]
                  have h_fy_v1 : freqOf y v1 = freqOf y v := by
                    dsimp [v1]; rw [freqOf_exchangeLeaf v z x y hz_ne_x hz_in_v hx_in h_cons_v]
                  rw [h_fb_v1, h_fy_v1]
                  have hy_freq_v : freqOf y v = freqOf y (splitLeaf t z z b fa fb) := (h_sameFreqs_v y).symm
                  have hy_freq_t : freqOf y (splitLeaf t z z b fa fb) = freqOf y t :=
                    freqOf_splitLeaf_of_ne t z b fa fb y hy_ne_z hyb
                  rw [hy_freq_v, hy_freq_t]
                  exact h_fb_min y hy_in_t hy_ne_z
                -- Second swap
                let v2 := swapFreqs b y (swapLeaves b y v1)
                have h_sib_v2 : areSiblings z b v2 :=
                  areSiblings_swapFreqs_preserved (swapLeaves b y v1) z b b y
                    (areSiblings_exchangeRight v1 z b y h_sib_v1 (Ne.symm hz_ne_b) hb_ne_y hz_ne_y)
                have h_cons_v2 : consistent v2 := by
                  dsimp [v2, swapFreqs]
                  apply consistent_replaceFreq y _ (replaceFreq b _ (swapLeaves b y v1))
                  apply consistent_replaceFreq b _ (swapLeaves b y v1)
                  exact consistent_swapLeaves b y v1 h_cons_v1
                have h_cost_v2 : (cost v2 : ℤ) ≤ (cost v1 : ℤ) :=
                  cost_exchangeLeaf_le v1 b y h_cons_v1 hb_in_v1 hy_in_v1 hb_ne_y h_freq_b_y_v1 h_depth_b_y_v1
                have h_freq_rel_v2 : ∀ s, freqOf s v2 = freqOf s (splitLeaf t z z b fa fb) := by
                  intro s
                  dsimp [v2]
                  rw [freqOf_exchangeLeaf v1 b y s hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x s hz_ne_x hz_in_v hx_in h_cons_v]
                  exact (h_sameFreqs_v s).symm
                have h_fz_v2 : freqOf z v2 = fa := by
                  dsimp [v2]
                  rw [freqOf_exchangeLeaf v1 b y z hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x z hz_ne_x hz_in_v hx_in h_cons_v, hz_fa_v]
                have h_fb_v2 : freqOf b v2 = fb := by
                  dsimp [v2]
                  rw [freqOf_exchangeLeaf v1 b y b hb_ne_y hb_in_v1 hy_in_v1 h_cons_v1]
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x b hz_ne_x hz_in_v hx_in h_cons_v, hb_fb_v]
                have h_cost_total : (cost v2 : ℤ) ≤ (cost v : ℤ) := by linarith
                exact h_merge_conclude v2 h_sib_v2 h_cons_v2 h_fz_v2 h_fb_v2 h_freq_rel_v2 h_cost_total
              · -- y ∉ alphabet t, prune z,y from v1 and use IH
                have h_freq_y_t : freqOf y t = 0 := freqOf_eq_zero_of_not_mem y t hy_in_t
                have h_freq_y_v1 : freqOf y v1 = 0 := by
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x y hz_ne_x hz_in_v hx_in h_cons_v]
                  rw [(h_sameFreqs_v y).symm, freqOf_splitLeaf_of_ne t z b fa fb y hy_ne_z hyb, h_freq_y_t]
                have h_fz_v1_val : freqOf z v1 = fa := by
                  dsimp [v1]; rw [freqOf_exchangeLeaf v z x z hz_ne_x hz_in_v hx_in h_cons_v, hz_fa_v]
                let v_pruned := mergePair z y z (freqOf z v1 + freqOf y v1) v1
                have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
                  have h_ne : z ≠ y := hz_ne_y
                  have h_lt : nodeCount v_pruned < nodeCount v1 :=
                    nodeCount_mergePair_lt_of_areSiblings v1 z y z (freqOf z v1 + freqOf y v1) h_sib_v1 h_ne
                  have h_eq_v1 : nodeCount v1 = nodeCount v := by
                    dsimp [v1, swapFreqs]
                    rw [nodeCount_replaceFreq_eq, nodeCount_replaceFreq_eq, nodeCount_swapLeaves_eq]
                  omega
                have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
                  have h_cost_int : (cost v_pruned : ℤ) = (cost v1 : ℤ) - (fa : ℤ) := by
                    have h := cost_mergePair_of_areSiblings v1 z y z fa 0 h_sib_v1 h_cons_v1 hz_ne_y
                      h_fz_v1_val h_freq_y_v1 (by ring)
                    simpa [v_pruned, h_fz_v1_val, h_freq_y_v1, add_zero] using h
                  have h_fa_pos_int : (0 : ℤ) < fa := by exact_mod_cast h_fa_pos
                  have h_cost_v1_le_v : (cost v1 : ℤ) ≤ (cost v : ℤ) := h_cost_v1
                  omega
                have h_cons_pruned : consistent v_pruned :=
                  consistent_mergePair_same_sibling v1 y z (freqOf z v1 + freqOf y v1) h_sib_v1 h_cons_v1 hz_ne_y
                have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
                  intro s
                  have h_freq_pruned : freqOf s v_pruned = freqOf s v1 := by
                    dsimp [v_pruned]
                    rw [freqOf_mergePair_same_sibling v1 y z s h_sib_v1 h_cons_v1 hz_ne_y, h_fz_v1_val, h_freq_y_v1, add_zero]
                    by_cases hsz : s = z
                    · rw [hsz, if_pos rfl, h_fz_v1_val]
                    · by_cases hsy : s = y
                      · rw [hsy]
                        by_cases hyz' : y = z
                        · rw [hyz'] at h_freq_y_v1; rw [h_fz_v1_val] at h_freq_y_v1; omega
                        · rw [if_neg hyz', if_pos rfl, h_freq_y_v1]
                      · rw [if_neg hsz, if_neg hsy]
                  rw [h_freq_pruned]
                  dsimp [v1]
                  rw [freqOf_exchangeLeaf v z x s hz_ne_x hz_in_v hx_in h_cons_v]
                  exact (h_sameFreqs_v s)
                have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
                have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
                  h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
                omega
          · -- Edge: x ∉ alphabet t. Both x,y are deepest siblings (same depth).
            -- Swap x↔y (same depth, cost preserved) so y becomes first sibling, then merge into y.
            have h_freq_x_v : freqOf x v = 0 := by
              rw [(h_sameFreqs_v x).symm, freqOf_splitLeaf_of_ne t z b fa fb x hx_ne_z hx_ne_b]
              exact freqOf_eq_zero_of_not_mem x t hx_in_t
            have h_depth_x_eq_y : (depthOf x v).getD 0 = (depthOf y v).getD 0 := by
              rw [h_depth_x, h_depth_y]
            have h_depth_x_le_y : (depthOf x v).getD 0 ≤ (depthOf y v).getD 0 := by rw [h_depth_x_eq_y]
            by_cases h_freq_y_pos : freqOf y v > 0
            · -- Swap x↔y: x (freq 0) into y's position. freq 0 ≤ freqOf y v, depth equal → cost non-increasing.
              let v_pre := swapFreqs x y (swapLeaves x y v)
              have h_sib_pre : areSiblings y x v_pre := by
                dsimp [v_pre]
                have h := areSiblings_swap_siblings h_dsp_sib_xy hx_ne_y
                exact areSiblings_swapFreqs_preserved (swapLeaves x y v) y x x y h
              have h_cons_pre : consistent v_pre := by
                dsimp [v_pre, swapFreqs]
                apply consistent_replaceFreq y _ (replaceFreq x _ (swapLeaves x y v))
                apply consistent_replaceFreq x _ (swapLeaves x y v)
                exact consistent_swapLeaves x y v h_cons_v
              have h_cost_pre : (cost v_pre : ℤ) ≤ (cost v : ℤ) :=
                cost_exchangeLeaf_le v x y h_cons_v hx_in hy_in hx_ne_y
                  (by rw [h_freq_x_v]; omega) h_depth_x_le_y
              have h_fy_pre : freqOf y v_pre = freqOf y v := by
                dsimp [v_pre]; rw [freqOf_exchangeLeaf v x y y hx_ne_y hx_in hy_in h_cons_v]
              have h_fx_pre : freqOf x v_pre = 0 := by
                dsimp [v_pre]; rw [freqOf_exchangeLeaf v x y x hx_ne_y hx_in hy_in h_cons_v, h_freq_x_v]
              let v_pruned := mergePair y x y (freqOf y v_pre + freqOf x v_pre) v_pre
              have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
                have h_ne : y ≠ x := Ne.symm hx_ne_y
                have h_lt : nodeCount v_pruned < nodeCount v_pre :=
                  nodeCount_mergePair_lt_of_areSiblings v_pre y x y (freqOf y v_pre + freqOf x v_pre) h_sib_pre h_ne
                have h_eq_pre : nodeCount v_pre = nodeCount v := by
                  dsimp [v_pre, swapFreqs]
                  rw [nodeCount_replaceFreq_eq, nodeCount_replaceFreq_eq, nodeCount_swapLeaves_eq]
                omega
              have h_cost_pruned_le_v : cost v_pruned ≤ cost v := by
                have h_cost_int : (cost v_pruned : ℤ) = (cost v_pre : ℤ) - (freqOf y v : ℤ) := by
                  have h := cost_mergePair_of_areSiblings v_pre y x y (freqOf y v_pre) 0
                    (fz := freqOf y v_pre + freqOf x v_pre)
                    h_sib_pre h_cons_pre (Ne.symm hx_ne_y) (by rw [h_fy_pre]) h_fx_pre
                    (by rw [h_fy_pre, h_fx_pre, add_zero])
                  simpa [v_pruned, h_fy_pre, h_fx_pre, add_zero] using h
                have h_fy_pos_int : (0 : ℤ) < freqOf y v := by exact_mod_cast h_freq_y_pos
                have h_cost_pre_le_v : (cost v_pre : ℤ) ≤ (cost v : ℤ) := h_cost_pre
                omega
              have h_cons_pruned : consistent v_pruned :=
                consistent_mergePair_same_sibling v_pre x y (freqOf y v_pre + freqOf x v_pre)
                  h_sib_pre h_cons_pre (Ne.symm hx_ne_y)
              have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
                intro s
                have h_freq_pruned : freqOf s v_pruned = freqOf s v_pre := by
                  dsimp [v_pruned]
                  rw [freqOf_mergePair_same_sibling v_pre x y s h_sib_pre h_cons_pre (Ne.symm hx_ne_y),
                    h_fy_pre, h_fx_pre, add_zero]
                  by_cases hsy : s = y
                  · rw [hsy, if_pos rfl, h_fy_pre]
                  · by_cases hsx : s = x
                    · rw [hsx]
                      by_cases hxy' : x = y; · exfalso; exact hx_ne_y hxy'
                      rw [if_neg hxy', if_pos rfl, h_fx_pre]
                    · rw [if_neg hsy, if_neg hsx]
                rw [h_freq_pruned]
                dsimp [v_pre]
                rw [freqOf_exchangeLeaf v x y s hx_ne_y hx_in hy_in h_cons_v]
                exact h_sameFreqs_v s
              have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
              have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
                h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
              omega
            · -- Both x and y have zero frequency (degenerate case). Cost doesn't decrease on pruning.
              have h_freq_y_v : freqOf y v = 0 := by omega
              let v_pruned := mergePair x y x (freqOf x v + freqOf y v) v
              have h_nodeCount_pruned_lt : nodeCount v_pruned < n := by
                have h_ne : x ≠ y := hx_ne_y
                have h_lt : nodeCount v_pruned < nodeCount v :=
                  nodeCount_mergePair_lt_of_areSiblings v x y x (freqOf x v + freqOf y v) h_dsp_sib_xy h_ne
                omega
              have h_cons_pruned : consistent v_pruned :=
                consistent_mergePair_same_sibling v y x (freqOf x v + freqOf y v) h_dsp_sib_xy h_cons_v hx_ne_y
              have h_sameFreqs_pruned : sameFreqs (splitLeaf t z z b fa fb) v_pruned := by
                intro s
                have h_freq_pruned : freqOf s v_pruned = freqOf s v := by
                  dsimp [v_pruned]
                  rw [freqOf_mergePair_same_sibling v y x s h_dsp_sib_xy h_cons_v hx_ne_y]
                  by_cases hsx : s = x
                  · subst s; simp [hx_ne_y, h_freq_x_v, h_freq_y_v]
                  · by_cases hsy : s = y
                    · subst s; simp [hx_ne_y, h_freq_x_v, h_freq_y_v]
                    · simp [hsx, hsy, h_freq_x_v, h_freq_y_v]
                rw [h_freq_pruned, h_sameFreqs_v s]
              have h_IH_pruned := IH (nodeCount v_pruned) h_nodeCount_pruned_lt
              have h_cost_pruned_bound : cost t + fa + fb ≤ cost v_pruned :=
                h_IH_pruned v_pruned rfl h_cons_pruned h_sameFreqs_pruned
              have h_cost_pruned_eq : cost v_pruned = cost v := by
                have h := cost_mergePair_of_areSiblings v x y x (freqOf x v) (freqOf y v)
                  (fz := freqOf x v + freqOf y v)
                  h_dsp_sib_xy h_cons_v hx_ne_y (by rfl) (by rfl) (by ring)
                simpa [v_pruned, h_freq_x_v, h_freq_y_v, add_zero] using h
              omega

  have h_all : ∀ n, P n := by
    intro n; exact Nat.strong_induction_on n hP
  exact h_all (nodeCount u) u rfl h_cons_u h_sameFreqs

theorem optimum_huffman (ts : List HuffTree)
    (h_sorted : forest_sorted ts)
    (h_cons : forest_consistent ts)
    (h_all_leaves : ∀ t ∈ ts, height t = 0)
    (h_pos : ∀ t ∈ ts, rootFreq t > 0)
    (h_nonempty : ts ≠ []) :
    optimum (huffman ts) := by
  generalize hlen : ts.length = n
  induction n using Nat.strong_induction_on generalizing ts with
  | h n ih =>
    cases ts with
    | nil => exfalso; exact h_nonempty rfl
    | cons ta ts' =>
      cases ts' with
      | nil =>
        have h_leaf : height ta = 0 := h_all_leaves ta (by simp)
        have h_rf_pos : rootFreq ta > 0 := h_pos ta (by simp)
        cases ta with
        | htInner _ _ =>
          exfalso
          simp [height] at h_leaf
        | htLeaf s f =>
          simp [huffman]
          have h_f_pos : f > 0 := by simpa [rootFreq] using h_rf_pos
          exact optimum_leaf s f h_f_pos
      | cons tb ts'' =>
        have h1 : height ta = 0 := h_all_leaves ta (by simp)
        have h2 : height tb = 0 := h_all_leaves tb (by simp)
        have hp1 : rootFreq ta > 0 := h_pos ta (by simp)
        have hp2 : rootFreq tb > 0 := h_pos tb (by simp)
        cases ta with
        | htInner _ _ =>
          exfalso
          simp [height] at h1
        | htLeaf sa fa =>
          cases tb with
          | htInner _ _ =>
            exfalso
            simp [height] at h2
          | htLeaf sb fb =>
            have h_ne : sa ≠ sb := by
              intro h_eq; subst h_eq
              simp [forest_consistent] at h_cons
              rcases h_cons with ⟨_, _, hd⟩
              have h_disjoint := Finset.disjoint_iff_inter_eq_empty.mp hd.1
              have : sa ∈ alphabet (htLeaf sa fa) ∩ alphabet (htLeaf sa fb) :=
                Finset.mem_inter.mpr ⟨by simp [alphabet], by simp [alphabet]⟩
              rw [h_disjoint] at this
              simp at this
            have h_fa_pos : fa > 0 := by simpa [rootFreq] using hp1
            have h_fb_pos : fb > 0 := by simpa [rootFreq] using hp2
            cases ts'' with
            | nil =>
              simpa [huffman, insortTree, unite] using
                optimum_two_distinct_leaves sa fa sb fb h_ne h_fa_pos h_fb_pos
            | cons tc rest =>
              let reduced := insortTree (htLeaf sa (fa + fb)) (tc :: rest)
              have h_reduced_nonempty : reduced ≠ [] := by
                rw [← List.length_pos_iff_ne_nil, insortTree_length]
                omega
              have h_reduced_sorted : forest_sorted reduced := by
                apply forest_sorted_insortTree_of_sorted
                exact forest_sorted_tail (htLeaf sb fb) (tc :: rest)
                  (forest_sorted_tail (htLeaf sa fa) (htLeaf sb fb :: tc :: rest) h_sorted)
              have h_a_notin_rest : ∀ t ∈ tc :: rest, sa ∉ alphabet t := by
                intro t ht
                have h_disj : Disjoint (alphabet (htLeaf sa fa)) (alphabet t) := by
                  rw [forest_consistent_cons_iff] at h_cons
                  exact h_cons.2.2 t (by simp [ht])
                intro h_mem
                have : sa ∈ alphabet (htLeaf sa fa) ∩ alphabet t :=
                  Finset.mem_inter.mpr ⟨by simp [alphabet], h_mem⟩
                rw [Finset.disjoint_iff_inter_eq_empty.mp h_disj] at this
                simp at this
              have h_reduced_cons : forest_consistent reduced := by
                apply forest_consistent_insortTree_fresh sa (fa + fb) (tc :: rest)
                · exact h_a_notin_rest
                · exact forest_consistent_tail (htLeaf sb fb) (tc :: rest)
                    (forest_consistent_tail (htLeaf sa fa) (htLeaf sb fb :: tc :: rest) h_cons)
              have h_reduced_leaves : ∀ t ∈ reduced, height t = 0 := by
                intro t ht
                rw [mem_insortTree] at ht
                rcases ht with rfl | ht
                · simp [height]
                · exact h_all_leaves t (by simp [ht])
              have h_reduced_pos : ∀ t ∈ reduced, rootFreq t > 0 := by
                intro t ht
                rw [mem_insortTree] at ht
                rcases ht with rfl | ht
                · simp [rootFreq]; omega
                · exact h_pos t (by simp [ht])
              have h_len : reduced.length < n := by
                rw [← hlen]
                simp [reduced, insortTree_length]
              have h_opt_reduced : optimum (huffman reduced) :=
                ih reduced.length h_len reduced h_reduced_sorted h_reduced_cons
                  h_reduced_leaves h_reduced_pos h_reduced_nonempty rfl
              have h_cons_reduced : consistent (huffman reduced) :=
                consistent_huffman_of_consistent reduced h_reduced_nonempty h_reduced_cons
              have h_a_in_reduced : sa ∈ alphabet (huffman reduced) := by
                rw [alphabet_huffman_eq_forest_alphabet reduced h_reduced_nonempty]
                rw [mem_forest_alphabet]
                use htLeaf sa (fa + fb)
                constructor
                · rw [mem_insortTree]; simp
                · simp [alphabet]
              have h_b_notin_reduced : sb ∉ alphabet (huffman reduced) := by
                rw [alphabet_huffman_eq_forest_alphabet reduced h_reduced_nonempty]
                rw [mem_forest_alphabet]
                rintro ⟨t, ht, h_mem⟩
                rw [mem_insortTree] at ht
                rcases ht with rfl | ht
                · simp [alphabet] at h_mem
                  have : sa = sb := h_mem.symm
                  contradiction
                · have h_mem_sb : sb ∈ alphabet t := by simpa using h_mem
                  have h_disj : Disjoint (alphabet (htLeaf sb fb)) (alphabet t) := by
                    rw [forest_consistent_cons_iff] at h_cons
                    exact h_cons.2.1.2.2 t (by simp [ht])
                  have : sb ∈ alphabet (htLeaf sb fb) ∩ alphabet t :=
                    Finset.mem_inter.mpr ⟨by simp [alphabet], h_mem_sb⟩
                  rw [Finset.disjoint_iff_inter_eq_empty.mp h_disj] at this
                  simp at this
              have h_freq_a : freqOf sa (huffman reduced) = fa + fb := by
                rw [freqOf_huffman_eq_forest_freq reduced sa h_reduced_nonempty]
                rw [forest_freq_insortTree]
                have h_zero : forest_freq (tc :: rest) sa = 0 := by
                  apply forest_freq_eq_zero_of_not_mem
                  rw [mem_forest_alphabet]
                  rintro ⟨t, ht, h_mem⟩
                  exact h_a_notin_rest t ht h_mem
                simp [forest_freq, freqOf] at h_zero ⊢
                omega
              have h_min : ∀ s ∈ alphabet (huffman reduced),
                  fa ≤ freqOf s (huffman reduced) ∧ fb ≤ freqOf s (huffman reduced) := by
                intro s hs
                rw [alphabet_huffman_eq_forest_alphabet reduced h_reduced_nonempty] at hs
                rw [mem_forest_alphabet] at hs
                rcases hs with ⟨t, ht, h_mem⟩
                rw [mem_insortTree] at ht
                rcases ht with rfl | ht
                · -- the combined leaf
                  have hs_eq : s = sa := by simpa [alphabet] using h_mem
                  rw [hs_eq]
                  rw [h_freq_a]
                  constructor <;> omega
                · -- a leaf from the original tail
                  have h_leaf_t : height t = 0 := h_all_leaves t (by simp [ht])
                  have h_s_ne_a : s ≠ sa := by
                    intro h_eq
                    rw [h_eq] at h_mem
                    exact h_a_notin_rest t ht h_mem
                  have h_freq_leaf : freqOf s (htLeaf sa (fa + fb)) = 0 := by
                    apply freqOf_eq_zero_of_not_mem
                    simp [alphabet, h_s_ne_a]
                  have h_freq_s : freqOf s (huffman reduced) = rootFreq t := by
                    rw [freqOf_huffman_eq_forest_freq reduced s h_reduced_nonempty]
                    rw [forest_freq_insortTree]
                    simp [forest_freq, h_freq_leaf]
                    exact forest_freq_eq_rootFreq_of_mem_leaf (tc :: rest) s t
                      (fun u hu => h_all_leaves u (by simp [hu]))
                      (forest_consistent_tail (htLeaf sb fb) (tc :: rest)
                        (forest_consistent_tail (htLeaf sa fa) (htLeaf sb fb :: tc :: rest) h_cons))
                      ht h_mem
                  rw [h_freq_s]
                  constructor
                  · have h_le := rootFreq_le_of_mem_sorted (htLeaf sa fa) (htLeaf sb fb :: tc :: rest)
                      h_sorted t (by simp [ht])
                    simp [rootFreq] at h_le ⊢
                    omega
                  · have h_le := rootFreq_le_of_mem_sorted (htLeaf sb fb) (tc :: rest)
                      (forest_sorted_tail (htLeaf sa fa) (htLeaf sb fb :: tc :: rest) h_sorted) t
                      (by simp [ht])
                    simp [rootFreq] at h_le ⊢
                    omega
              have h_opt_split : optimum (splitLeaf (huffman reduced) sa sa sb fa fb) := by
                apply optimum_splitLeaf (huffman reduced) sa sb fa fb
                  h_opt_reduced h_a_in_reduced h_b_notin_reduced h_ne
                  h_fa_pos h_fb_pos _ _ _ h_freq_a
                · -- fa ≤ fb
                  have h_le : rootFreq (htLeaf sa fa) ≤ rootFreq (htLeaf sb fb) := by
                    simp [forest_sorted] at h_sorted
                    exact h_sorted.1
                  simp [rootFreq] at h_le ⊢
                  omega
                · -- fa minimum
                  intro s hs
                  exact (h_min s hs).1
                · -- fb minimum for s ≠ sa
                  intro s hs h_s_ne_a
                  exact (h_min s hs).2
              have h_eq : splitLeaf (huffman reduced) sa sa sb fa fb =
                  huffman (htLeaf sa fa :: htLeaf sb fb :: tc :: rest) := by
                have h_a_notin_tc_rest : ∀ t ∈ tc :: rest, sa ∉ alphabet t := h_a_notin_rest
                rw [show reduced = insortTree (htLeaf sa (fa + fb)) (tc :: rest) by rfl]
                rw [splitLeaf_huffman_commute sa sb fa fb (tc :: rest) h_a_notin_tc_rest]
                simp [huffman, insortTree, unite]
              rw [h_eq] at h_opt_split
              exact h_opt_split
```
{% endraw %}
</details>
